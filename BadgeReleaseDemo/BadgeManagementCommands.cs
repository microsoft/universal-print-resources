// <copyright file="BadgeManagementCommands.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

using System.CommandLine;
using System.CommandLine.Parsing;
using System.Text.Json;
using BadgeReleaseDemo.Auth;
using BadgeReleaseDemo.GraphApi;
using BadgeReleaseDemo.Helpers;
using Microsoft.Identity.Client;

namespace BadgeReleaseDemo;

public sealed class BadgeManagementCommands
{
    private readonly Option<bool> useV3GraphBadgeApiOption;

    private BadgeManagementCommands(Option<bool> useV3GraphBadgeApiOption) =>
        this.useV3GraphBadgeApiOption = useV3GraphBadgeApiOption;

    public static Command Create(Option<bool> useV3GraphBadgeApiOption) =>
        new BadgeManagementCommands(useV3GraphBadgeApiOption).CreateCommand();

    private Command CreateCommand()
    {
        var badgesCommand = new Command("badges", "Manage badge groups and mappings");
        badgesCommand.Subcommands.Add(CreateBadgeGroupsCommand());
        badgesCommand.Subcommands.Add(CreateMappingsCommand());
        return badgesCommand;
    }

    private Command CreateBadgeGroupsCommand()
    {
        var badgeGroupsCommand = new Command("groups", "Manage badge groups");
        badgeGroupsCommand.Aliases.Add("collections");

        var listCommand = new Command("list", "List badge groups");
        listCommand.SetAction(parseResult => RunAuthenticatedAsync(parseResult, async (client, token) =>
        {
            var badgeGroups = await client.ListBadgeGroupsAsync(token);
            ConsoleHelper.WriteInfo($"Badge groups: {badgeGroups.Count}");
            foreach (var badgeGroup in badgeGroups)
            {
                ConsoleHelper.WriteKeyValue("Group ID", badgeGroup.Id);
                ConsoleHelper.WriteKeyValue("Display name", badgeGroup.DisplayName);
                ConsoleHelper.WriteKeyValue("Created date/time", badgeGroup.CreatedDateTime);
            }
            ConsoleHelper.WriteInfo("Listing badge groups fits in a single service response; pagination is not required.");

            return 0;
        }));

        var createCommand = new Command("create", "Create a badge group if one does not exist");
        createCommand.SetAction(parseResult => RunAuthenticatedAsync(parseResult, async (client, token) =>
        {
            var result = await client.CreateBadgeGroupAsync(token);
            ConsoleHelper.WriteSuccess(
                result.Created
                    ? "The badge group provisioning completed."
                    : "Using existing badge group.");
            ConsoleHelper.WriteKeyValue("Group ID", result.Id);
            if (result.Created)
            {
                ConsoleHelper.WriteWarning(client.SettlingNote);
            }

            return 0;
        }));

        var badgeGroupIdOption = CreateBadgeGroupIdOption();
        var forceOption = new Option<bool>("--force")
        {
            Description = "Delete without prompting for confirmation"
        };
        var deleteCommand = new Command("delete", "Delete a badge group");
        deleteCommand.Options.Add(badgeGroupIdOption);
        deleteCommand.Options.Add(forceOption);
        deleteCommand.SetAction(parseResult => RunAuthenticatedAsync(parseResult, async (client, token) =>
        {
            var badgeGroupId = await ResolveBadgeGroupIdAsync(
                client,
                token,
                parseResult.GetValue(badgeGroupIdOption));
            if (!parseResult.GetValue(forceOption) &&
                !ConsoleHelper.PromptYesNo($"Delete badge group '{badgeGroupId}'?"))
            {
                ConsoleHelper.WriteWarning("The badge group deletion was cancelled.");
                return 0;
            }

            var deleted = await client.DeleteBadgeGroupAsync(token, badgeGroupId);
            if (!deleted)
            {
                ConsoleHelper.WriteWarning($"The badge group '{badgeGroupId}' was not found.");
                return 1;
            }

            ConsoleHelper.WriteSuccess($"The badge group '{badgeGroupId}' deletion was requested.");
            return 0;
        }));

        badgeGroupsCommand.Subcommands.Add(listCommand);
        badgeGroupsCommand.Subcommands.Add(createCommand);
        badgeGroupsCommand.Subcommands.Add(deleteCommand);
        return badgeGroupsCommand;
    }

    private Command CreateMappingsCommand()
    {
        var mappingsCommand = new Command("mappings", "Manage badge-to-user mappings");
        mappingsCommand.Subcommands.Add(CreateListMappingsCommand());
        mappingsCommand.Subcommands.Add(CreateGetMappingCommand());
        mappingsCommand.Subcommands.Add(CreateAddMappingCommand());
        mappingsCommand.Subcommands.Add(CreateUpdateMappingCommand());
        mappingsCommand.Subcommands.Add(CreateDeleteMappingCommand());
        return mappingsCommand;
    }

    private Command CreateListMappingsCommand()
    {
        var badgeGroupIdOption = CreateBadgeGroupIdOption();
        var command = new Command("list", "List badge mappings (requires service support; available in V3)");
        command.Options.Add(badgeGroupIdOption);
        command.SetAction(parseResult => RunAuthenticatedAsync(parseResult, async (client, token) =>
        {
            var badgeGroupId = await ResolveBadgeGroupIdAsync(
                client,
                token,
                parseResult.GetValue(badgeGroupIdOption));
            var result = await client.ListBadgesAsync(token, badgeGroupId);
            if (!result.IsSupported)
            {
                ConsoleHelper.WriteWarning("The service does not implement badge mapping listing yet.");
                return 0;
            }

            ConsoleHelper.WriteInfo($"Badge mappings: {result.Badges.Count}");
            foreach (var badge in result.Badges)
            {
                WriteBadge(badge);
            }

            return 0;
        }));
        return command;
    }

    private Command CreateGetMappingCommand()
    {
        var badgeGroupIdOption = CreateBadgeGroupIdOption();
        var badgeIdOption = CreateRequiredOption("--badge-id", "Badge ID to retrieve");
        var command = new Command("get", "Get a badge mapping");
        command.Options.Add(badgeGroupIdOption);
        command.Options.Add(badgeIdOption);
        AddNonEmptyValidator(command, badgeIdOption);
        command.SetAction(parseResult => RunAuthenticatedAsync(parseResult, async (client, token) =>
        {
            var badgeGroupId = await ResolveBadgeGroupIdAsync(
                client,
                token,
                parseResult.GetValue(badgeGroupIdOption));
            var badgeId = parseResult.GetRequiredValue(badgeIdOption);
            var badge = await client.GetBadgeAsync(token, badgeGroupId, badgeId);
            if (badge == null)
            {
                ConsoleHelper.WriteWarning($"Badge '{badgeId}' was not found.");
                return 1;
            }

            WriteBadge(badge);
            return 0;
        }));
        return command;
    }

    private Command CreateAddMappingCommand()
    {
        var badgeGroupIdOption = CreateBadgeGroupIdOption();
        var badgeIdOption = CreateRequiredOption("--badge-id", "Badge ID to create");
        var upnOption = CreateRequiredOption("--upn", "User principal name for the badge");
        var userIdOption = CreateUserIdOption();
        var command = new Command("create", "Create a badge mapping");
        command.Options.Add(badgeGroupIdOption);
        command.Options.Add(badgeIdOption);
        command.Options.Add(upnOption);
        command.Options.Add(userIdOption);
        AddNonEmptyValidator(command, badgeIdOption);
        AddNonEmptyValidator(command, upnOption);
        command.SetAction(parseResult => RunAuthenticatedAsync(parseResult, async (client, token) =>
        {
            var badgeGroupId = await ResolveBadgeGroupIdAsync(
                client,
                token,
                parseResult.GetValue(badgeGroupIdOption));
            var badge = await client.AddBadgeAsync(
                token,
                badgeGroupId,
                parseResult.GetRequiredValue(badgeIdOption),
                parseResult.GetRequiredValue(upnOption),
                parseResult.GetValue(userIdOption));
            ConsoleHelper.WriteSuccess("Badge mapping created.");
            WriteBadge(badge);
            return 0;
        }));
        return command;
    }

    private Command CreateUpdateMappingCommand()
    {
        var badgeGroupIdOption = CreateBadgeGroupIdOption();
        var badgeIdOption = CreateRequiredOption("--badge-id", "Badge ID to update");
        var upnOption = CreateRequiredOption("--upn", "User principal name for the updated badge mapping");
        var userIdOption = CreateUserIdOption();
        var command = new Command("update", "Update a badge mapping");
        command.Options.Add(badgeGroupIdOption);
        command.Options.Add(badgeIdOption);
        command.Options.Add(upnOption);
        command.Options.Add(userIdOption);
        AddNonEmptyValidator(command, badgeIdOption);
        AddNonEmptyValidator(command, upnOption);
        command.SetAction(async parseResult =>
        {
            var upn = parseResult.GetRequiredValue(upnOption);
            var userId = parseResult.GetValue(userIdOption);

            return await RunAuthenticatedAsync(parseResult, async (client, token) =>
            {
                var badgeGroupId = await ResolveBadgeGroupIdAsync(
                    client,
                    token,
                    parseResult.GetValue(badgeGroupIdOption));
                var badge = await client.UpdateBadgeAsync(
                    token,
                    badgeGroupId,
                    parseResult.GetRequiredValue(badgeIdOption),
                    upn,
                    userId);
                ConsoleHelper.WriteSuccess("Badge mapping updated.");
                WriteBadge(badge);
                return 0;
            });
        });
        return command;
    }

    private Command CreateDeleteMappingCommand()
    {
        var badgeGroupIdOption = CreateBadgeGroupIdOption();
        var badgeIdOption = CreateRequiredOption("--badge-id", "Badge ID to delete");
        var command = new Command("delete", "Delete a badge mapping");
        command.Options.Add(badgeGroupIdOption);
        command.Options.Add(badgeIdOption);
        AddNonEmptyValidator(command, badgeIdOption);
        command.SetAction(parseResult => RunAuthenticatedAsync(parseResult, async (client, token) =>
        {
            var badgeGroupId = await ResolveBadgeGroupIdAsync(
                client,
                token,
                parseResult.GetValue(badgeGroupIdOption));
            var badgeId = parseResult.GetRequiredValue(badgeIdOption);
            var deleted = await client.DeleteBadgeAsync(token, badgeGroupId, badgeId);
            if (!deleted)
            {
                ConsoleHelper.WriteWarning($"Badge '{badgeId}' was not found.");
                return 1;
            }

            ConsoleHelper.WriteSuccess($"Badge '{badgeId}' deleted.");
            return 0;
        }));
        return command;
    }

    private static Option<string?> CreateBadgeGroupIdOption() =>
        new("--group-id", "--collection-id")
        {
            Description = "Badge group ID; omit only when the tenant has exactly one group"
        };

    private static Option<string?> CreateUserIdOption() =>
        new("--user-id")
        {
            Description = "Optional Entra user object ID (GUID in V3)"
        };

    private static Option<string> CreateRequiredOption(string name, string description) =>
        new(name)
        {
            Description = description,
            Required = true
        };

    private static void AddNonEmptyValidator(Command command, Option<string> option)
    {
        command.Validators.Add(result =>
        {
            if (string.IsNullOrWhiteSpace(result.GetValue(option)))
            {
                result.AddError($"Option '{option.Name}' cannot be empty.");
            }
        });
    }

    private async Task<int> RunAuthenticatedAsync(
        ParseResult parseResult,
        Func<BadgeManagement, string, Task<int>> operation)
    {
        try
        {
            var config = LoadConfiguration();
            var appId = config.GetProperty("AppId").GetString()!;
            var tenantId = config.TryGetProperty("Tenant", out var tenantProperty)
                ? tenantProperty.GetString() ?? string.Empty
                : string.Empty;
            var graphPrintBaseUrl = config.GetProperty("GraphPrintBaseUrl").GetString()!;

            if (appId == "YOUR_APP_ID_HERE" || tenantId == "YOUR_TENANT_HERE")
            {
                ConsoleHelper.WriteError("Please set your App ID and Tenant in appsettings.json.");
                return 1;
            }

            ConsoleHelper.WriteHeader("🏷️  Universal Print — Badge Management");
            var auth = new AuthHelper(appId, tenantId);
            var upn = await auth.SignInUserAsync();
            ConsoleHelper.WriteSuccess($"Signed in as: {upn}");
            var accessToken = await auth.GetUserTokenAsync();
            using var client = new BadgeManagement(
                graphPrintBaseUrl, useV3GraphBadgeApi: parseResult.GetValue(useV3GraphBadgeApiOption));
            return await operation(client, accessToken);
        }
        catch (FileNotFoundException exception)
        {
            ConsoleHelper.WriteError(exception.Message);
            return 1;
        }
        catch (JsonException exception)
        {
            ConsoleHelper.WriteError($"The service returned invalid JSON: {exception.Message}");
            return 1;
        }
        catch (MsalException exception)
        {
            ConsoleHelper.WriteError($"Authentication failed: {exception.Message}");
            return 1;
        }
        catch (HttpRequestException exception)
        {
            ConsoleHelper.WriteError(exception.Message);
            return 1;
        }
        catch (TimeoutException exception)
        {
            ConsoleHelper.WriteError(exception.Message);
            return 1;
        }
        catch (OperationCanceledException)
        {
            ConsoleHelper.WriteError("The operation was cancelled or timed out.");
            return 1;
        }
        catch (InvalidOperationException exception)
        {
            ConsoleHelper.WriteError(exception.Message);
            return 1;
        }
        catch (ArgumentException exception)
        {
            ConsoleHelper.WriteError(exception.Message);
            return 1;
        }
    }

    private static async Task<string> ResolveBadgeGroupIdAsync(
        BadgeManagement client,
        string accessToken,
        string? badgeGroupId)
    {
        if (!string.IsNullOrWhiteSpace(badgeGroupId))
        {
            return badgeGroupId;
        }

        var badgeGroups = await client.ListBadgeGroupsAsync(accessToken);
        return badgeGroups.Count switch
        {
            0 => throw new InvalidOperationException(
                $"No badge group exists. Create one with 'badges groups create{(client.UseV3GraphBadgeApi ? " --use-v3-badge-api" : "")}'."),
            1 => badgeGroups[0].Id,
            _ => throw new InvalidOperationException(
                $"Multiple badge groups exist. Specify --group-id with one of: {string.Join(", ", badgeGroups.Select(item => item.Id))}")
        };
    }

    private static void WriteBadge(BadgeMapping badge)
    {
        ConsoleHelper.WriteKeyValue("Badge ID", badge.Id);
        ConsoleHelper.WriteKeyValue("User principal name", badge.Upn);
        ConsoleHelper.WriteKeyValue("User ID", badge.UserId);
        ConsoleHelper.WriteKeyValue("Physical badge ID", badge.PhysicalBadgeId);
        ConsoleHelper.WriteKeyValue("Created date/time", badge.CreatedDateTime);
    }

    private static JsonElement LoadConfiguration()
    {
        var configPath = Path.Combine(AppContext.BaseDirectory, "appsettings.json");
        if (!File.Exists(configPath))
        {
            throw new FileNotFoundException(
                "appsettings.json not found. Make sure it's in the output directory.",
                configPath);
        }

        try
        {
            return JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(configPath));
        }
        catch (JsonException exception)
        {
            throw new InvalidOperationException(
                $"appsettings.json contains invalid JSON: {exception.Message}",
                exception);
        }
    }
}
