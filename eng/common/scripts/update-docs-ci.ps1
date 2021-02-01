#Requires -Version 6.0
# This script is intended to  update docs.ms CI configuration (currently supports Java, Python, C#, JS)
# as part of the azure-sdk release. For details on calling, check `archtype-<language>-release` in each azure-sdk
# repository.

# Where possible, this script adds as few changes as possible to the target config. We only 
# specifically mark a version for Python Preview and Java. This script is intended to be invoked 
# multiple times. Once for each moniker. Currently only supports "latest" and "preview" artifact selection however.
param (
  [Parameter(Mandatory = $true)]
  $ArtifactLocation, # the root of the artifact folder. DevOps $(System.ArtifactsDirectory)
  
  [Parameter(Mandatory = $true)]
  $WorkDirectory, # a clean folder that we can work in
  
  [Parameter(Mandatory = $true)]
  $ReleaseSHA, # the SHA for the artifacts. DevOps: $(Release.Artifacts.<artifactAlias>.SourceVersion) or $(Build.SourceVersion)
  
  [Parameter(Mandatory = $true)]
  $RepoId, # full repo id. EG azure/azure-sdk-for-net  DevOps: $(Build.Repository.Id). Used as a part of VerifyPackages
  
  [Parameter(Mandatory = $true)]
  [ValidateSet("Nuget","NPM","PyPI","Maven")]
  $Repository, # EG: "Maven", "PyPI", "NPM"

  [Parameter(Mandatory = $true)]
  $DocRepoLocation, # the location of the cloned doc repo

  [Parameter(Mandatory = $true)]
  $Configs # The configuration elements informing important locations within the cloned doc repo
)

. (Join-Path $PSScriptRoot common.ps1)

$targets = ($Configs | ConvertFrom-Json).targets

# $Configs target layout: 
#{
# path_to_config:
# mode:
# monikerid:
# content_folder:
# suffix:
#}


# Creates variables representing latest and preview modes. $Configs should have
# only one of each.
$latestMode = $targets | Where-Object { $_.Mode -eq "Latest" }
$previewMode = $targets | Where-Object { $_.Mode -eq "Preview" }

if (($latestMode | Measure-Object).Count -ne 1 `
  -or ($previewMode | Measure-Object).Count -ne 1) { 
  Write-Error '$Configs contains invalid definition of "Latest" or "Preview" modes'
} 

$apiUrl = "https://api.github.com/repos/$repoId"
$pkgs = VerifyPackages -artifactLocation $ArtifactLocation `
  -workingDirectory $WorkDirectory `
  -apiUrl $apiUrl `
  -continueOnError $True 

# Transition from per-target config logic to logic which can handle multiple 
# modes (e.g. preview and legacy)

# Preview packages must have a prerlease version AND supersede all previously 
# published packages
$previewPackages = $pkgs `
  | Where-Object { $_.IsPrerelease -eq $true } `
  | Where-Object { &$PackageSupersedesAllPublished($_) }
$latestPackages = $pkgs | Where-Object { $_.IsPrerelease -ne $true }

Write-Host "Preview Packages:"
$previewPackages | Format-List -Property PackageId, PackageVersion 
Write-Host "Latest Packages:"
$latestPackages | Format-List -Property PackageId, PackageVersion 

# Update CI configs for GA packages
&$UpdateDocCIFn `
  -pkgs $latestPackages `
  -ciRepo $DocRepoLocation `
  -locationInDocRepo $latestMode.path_to_config `
  -monikerId $latestMode.monikerid

# Update CI configs for preview packages
&$UpdateDocCIFn `
  -pkgs $previewPackages `
  -ciRepo $DocRepoLocation `
  -locationInDocRepo $previewMode.path_to_config `
  -monikerId $previewMode.monikerid

# Remove GA package if GA is greater than existing preview (e.g. GA: 1.1.0 >= Preview: 1.0.1-beta.1)
# Also: Do NOT remove if GA package is less than preview (e.g. GA: 1.1.0 < Preview: 2.0.0-beta.1)
&$UpdateDocMonikerCIFn `
  -SupersedingPackages $latestPackages `
  -CiConfigLocation (Join-Path $DocRepoLocation $previewMode.path_to_config)




