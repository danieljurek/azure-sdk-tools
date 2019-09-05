using Microsoft.Extensions.Logging;
using Microsoft.TeamFoundation.Build.WebApi;
using Microsoft.VisualStudio.Services.Common;
using Microsoft.VisualStudio.Services.WebApi;
using NotificationConfiguration.Enums;
using NotificationConfiguration.Helpers;
using NotificationConfiguration.Models;
using NotificationConfiguration.Services;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace PipelineBulkEditor
{
    class Program
    {
        public static async Task Main(
            string project,
            string organization,
            string tokenVariableName,
            bool dryRun = false
        )
        {
            var devOpsToken = Environment.GetEnvironmentVariable(tokenVariableName);
            var devOpsCreds = new VssBasicCredential("nobody", devOpsToken);
            var devOpsConnection = new VssConnection(new Uri($"https://dev.azure.com/{organization}/"), devOpsCreds);

#pragma warning disable CS0618 // Type or member is obsolete
            var loggerFactory = new LoggerFactory().AddConsole(includeScopes: true);
#pragma warning restore CS0618 // Type or member is obsolete
            var devOpsServiceLogger = loggerFactory.CreateLogger<AzureDevOpsService>();
            var logger = loggerFactory.CreateLogger<Program>();
            
            var devOpsService = new AzureDevOpsService(devOpsConnection, devOpsServiceLogger);

            var teams = await devOpsService.GetTeamsAsync(project);


            var relevantTeams = teams.Where(team =>
            {
                var teamMetadata = YamlHelper
                    .Deserialize<TeamMetadata>(team.Description, swallowExceptions: true);
                if (teamMetadata == default)
                {
                    return false;
                }

                return teamMetadata.Purpose == TeamPurpose.ParentNotificationTeam && team.Name.StartsWith("java -");
            });

            var jonathanDescriptor = await devOpsService.GetDescriptorForPrincipal("jogiles@microsoft.com");

            foreach (var team in relevantTeams)
            {
                logger.LogInformation("Add to Team = {0}", team.Name);
                var teamDescriptor = await devOpsService.GetDescriptorAsync(team.Id);
                await devOpsService.AddToTeamAsync(teamDescriptor, jonathanDescriptor);
            }

            // Flush logs
            loggerFactory.Dispose();

        }
    }
}
