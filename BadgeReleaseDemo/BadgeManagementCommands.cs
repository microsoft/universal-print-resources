// <copyright file="BadgeManagementCommands.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

using System.CommandLine;
using System.Text.Json;
using BadgeReleaseDemo.Auth;
using BadgeReleaseDemo.GraphApi;
using BadgeReleaseDemo.Helpers;
using Microsoft.Identity.Client;

namespace BadgeReleaseDemo;

public static class BadgeManagementCommands
{
    public static Command Create()
    {
        var badgesCommand = new Command("badges", "Manage badge collections and mappings");
        badgesCommand.Subcommands.Add(CreateCollectionsCommand());
        badgesCommand.Subcommands.Add(CreateMappingsCommand());
        return badgesCommand;
    }

    private static Command CreateCollectionsCommand()
    {
        var collectionsCommand = new Command("collections", "Manage badge collections");

        var listCommand = new Command("list", "List badge collections");
        listCommand.SetAction(_ => RunAuthenticatedAsync(async (client, token) =>
        {
            var collections = await client.ListBadgeCollectionsAsync(token);
            ConsoleHelper.WriteInfo($"Badge collections: {collections.Count}");
            foreach (var collection in collections)
            {
                ConsoleHelper.WriteKeyValue("Collection ID", collection.Id);
            }

            return 0;
        }));

        var createCommand = new Command("create", "Create a badge collection if one does not exist");
        createCommand.SetAction(_ => RunAuthenticatedAsync(async (client, token) =>
        {
            var collectionId = await client.CreateBadgeCollectionAsync(token);
            ConsoleHelper.WriteSuccess("Badge collection is ready.");
            ConsoleHelper.WriteKeyValue("Collection ID", collectionId);
            return 0;
        }));

        var collectionIdOption = CreateCollectionIdOption();
        var forceOption = new Option<bool>("--force")
        {
            Description = "Delete without prompting for confirmation"
        };
        var deleteCommand = new Command("delete", "Delete a badge collection");
        deleteCommand.Options.Add(collectionIdOption);
        deleteCommand.Options.Add(forceOption);
        deleteCommand.SetAction(parseResult => RunAuthenticatedAsync(async (client, token) =>
        {
            var collectionId = await ResolveCollectionIdAsync(
                client,
                token,
                parseResult.GetValue(collectionIdOption));
            if (!parseResult.GetValue(forceOption) &&
                !ConsoleHelper.PromptYesNo($"Delete badge collection '{collectionId}'?"))
            {
                ConsoleHelper.WriteWarning("Badge collection deletion cancelled.");
                return 0;
            }

            var deleted = await client.DeleteBadgeCollectionAsync(token, collectionId);
            if (!deleted)
            {
                ConsoleHelper.WriteWarning($"Badge collection '{collectionId}' was not found.");
                return 1;
            }

            ConsoleHelper.WriteSuccess($"Badge collection '{collectionId}' deletion requested.");
            return 0;
        }));

        collectionsCommand.Subcommands.Add(listCommand);
        collectionsCommand.Subcommands.Add(createCommand);
        collectionsCommand.Subcommands.Add(deleteCommand);
        return collectionsCommand;
    }

    private static Command CreateMappingsCommand()
    {
        var mappingsCommand = new Command("mappings", "Manage badge-to-user mappings");
        mappingsCommand.Subcommands.Add(CreateListMappingsCommand());
        mappingsCommand.Subcommands.Add(CreateGetMappingCommand());
        mappingsCommand.Subcommands.Add(CreateAddMappingCommand());
        mappingsCommand.Subcommands.Add(CreateUpdateMappingCommand());
        mappingsCommand.Subcommands.Add(CreateDeleteMappingCommand());
        return mappingsCommand;
    }

    private static Command CreateListMappingsCommand()
    {
        var collectionIdOption = CreateCollectionIdOption();
        var command = new Command("list", "List badge mappings");
        command.Options.Add(collectionIdOption);
        command.SetAction(parseResult => RunAuthenticatedAsync(async (client, token) =>
        {
            var collectionId = await ResolveCollectionIdAsync(
                client,
                token,
                parseResult.GetValue(collectionIdOption));
            var result = await client.ListBadgesAsync(token, collectionId);
            if (!result.IsSupported)
            {
                ConsoleHelper.WriteWarning("Listing badge mappings is not supported by the service.");
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

    private static Command CreateGetMappingCommand()
    {
        var collectionIdOption = CreateCollectionIdOption();
        var badgeIdOption = CreateRequiredOption("--badge-id", "Badge ID to retrieve");
        var command = new Command("get", "Get a badge mapping");
        command.Options.Add(collectionIdOption);
        command.Options.Add(badgeIdOption);
        AddNonEmptyValidator(command, badgeIdOption);
        command.SetAction(parseResult => RunAuthenticatedAsync(async (client, token) =>
        {
            var collectionId = await ResolveCollectionIdAsync(
                client,
                token,
                parseResult.GetValue(collectionIdOption));
            var badgeId = parseResult.GetRequiredValue(badgeIdOption);
            var badge = await client.GetBadgeAsync(token, collectionId, badgeId);
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

    private static Command CreateAddMappingCommand()
    {
        var collectionIdOption = CreateCollectionIdOption();
        var badgeIdOption = CreateRequiredOption("--badge-id", "Badge ID to create");
        var upnOption = CreateRequiredOption("--upn", "User principal name for the badge");
        var userIdOption = CreateUserIdOption();
        var command = new Command("create", "Create a badge mapping");
        command.Options.Add(collectionIdOption);
        command.Options.Add(badgeIdOption);
        command.Options.Add(upnOption);
        command.Options.Add(userIdOption);
        AddNonEmptyValidator(command, badgeIdOption);
        AddNonEmptyValidator(command, upnOption);
        command.SetAction(parseResult => RunAuthenticatedAsync(async (client, token) =>
        {
            var collectionId = await ResolveCollectionIdAsync(
                client,
                token,
                parseResult.GetValue(collectionIdOption));
            var badge = await client.AddBadgeAsync(
                token,
                collectionId,
                parseResult.GetRequiredValue(badgeIdOption),
                parseResult.GetRequiredValue(upnOption),
                parseResult.GetValue(userIdOption));
            ConsoleHelper.WriteSuccess("Badge mapping created.");
            WriteBadge(badge);
            return 0;
        }));
        return command;
    }

    private static Command CreateUpdateMappingCommand()
    {
        var collectionIdOption = CreateCollectionIdOption();
        var badgeIdOption = CreateRequiredOption("--badge-id", "Badge ID to update");
        var upnOption = new Option<string?>("--upn")
        {
            Description = "New user principal name"
        };
        var userIdOption = CreateUserIdOption();
        var command = new Command("update", "Update a badge mapping");
        command.Options.Add(collectionIdOption);
        command.Options.Add(badgeIdOption);
        command.Options.Add(upnOption);
        command.Options.Add(userIdOption);
        AddNonEmptyValidator(command, badgeIdOption);
        command.SetAction(async parseResult =>
        {
            var upn = parseResult.GetValue(upnOption);
            var userId = parseResult.GetValue(userIdOption);
            if (string.IsNullOrWhiteSpace(upn))
            {
                ConsoleHelper.WriteError("--upn is required when updating a badge mapping.");
                return 1;
            }

            return await RunAuthenticatedAsync(async (client, token) =>
            {
                var collectionId = await ResolveCollectionIdAsync(
                    client,
                    token,
                    parseResult.GetValue(collectionIdOption));
                var badge = await client.UpdateBadgeAsync(
                    token,
                    collectionId,
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

    private static Command CreateDeleteMappingCommand()
    {
        var collectionIdOption = CreateCollectionIdOption();
        var badgeIdOption = CreateRequiredOption("--badge-id", "Badge ID to delete");
        var command = new Command("delete", "Delete a badge mapping");
        command.Options.Add(collectionIdOption);
        command.Options.Add(badgeIdOption);
        AddNonEmptyValidator(command, badgeIdOption);
        command.SetAction(parseResult => RunAuthenticatedAsync(async (client, token) =>
        {
            var collectionId = await ResolveCollectionIdAsync(
                client,
                token,
                parseResult.GetValue(collectionIdOption));
            var badgeId = parseResult.GetRequiredValue(badgeIdOption);
            var deleted = await client.DeleteBadgeAsync(token, collectionId, badgeId);
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

    private static Option<string?> CreateCollectionIdOption() =>
        new("--collection-id")
        {
            Description = "Badge collection ID; omit only when the tenant has exactly one collection"
        };

    private static Option<string?> CreateUserIdOption() =>
        new("--user-id")
        {
            Description = "Optional Entra user object ID"
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

    private static async Task<int> RunAuthenticatedAsync(
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
            using var client = new BadgeManagement(graphPrintBaseUrl);
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

    private static async Task<string> ResolveCollectionIdAsync(
        BadgeManagement client,
        string accessToken,
        string? collectionId)
    {
        if (!string.IsNullOrWhiteSpace(collectionId))
        {
            return collectionId;
        }

        var collections = await client.ListBadgeCollectionsAsync(accessToken);
        return collections.Count switch
        {
            0 => throw new InvalidOperationException(
                "No badge collection exists. Create one with 'badges collections create'."),
            1 => collections[0].Id,
            _ => throw new InvalidOperationException(
                $"Multiple badge collections exist. Specify --collection-id with one of: {string.Join(", ", collections.Select(item => item.Id))}")
        };
    }

    private static void WriteBadge(BadgeMapping badge)
    {
        ConsoleHelper.WriteKeyValue("Badge ID", badge.Id);
        ConsoleHelper.WriteKeyValue("UPN", badge.Upn);
        ConsoleHelper.WriteKeyValue("User ID", badge.UserId);
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
