// <copyright file="BadgeManagement.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

using System.Net;
using System.Net.Http.Headers;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using BadgeReleaseDemo.Helpers;

namespace BadgeReleaseDemo.GraphApi;

/// <summary>
/// Handles badge group and badge CRUD via MS Graph API.
/// </summary>
public class BadgeManagement : IDisposable
{
    private readonly string graphBaseUrl;
    private readonly HttpClient httpClient;

    public bool UseV3BadgeApi { get; }
    public string ResourceIdLabel => "Group ID";
    public string SettlingNote =>
        "NOTE: Badge writes may need additional time to settle after group provisioning succeeds. " +
        "If adding a badge reports that the group was not found, wait a few minutes and retry.";
    private string ResourceUrl => $"{graphBaseUrl}/print/{(UseV3BadgeApi ? "badgeGroups" : "badgeCollections")}";

    public BadgeManagement(
        string graphBaseUrl,
        HttpMessageHandler? httpMessageHandler = null,
        bool useV3BadgeApi = false)
    {
        this.graphBaseUrl = graphBaseUrl;
        UseV3BadgeApi = useV3BadgeApi;
        httpClient = httpMessageHandler == null
            ? new HttpClient()
            : new HttpClient(httpMessageHandler);
    }

    public void Dispose() => httpClient.Dispose();

    public async Task<IReadOnlyList<BadgeCollection>> ListBadgeCollectionsAsync(string accessToken)
    {
        using var request = CreateRequest(HttpMethod.Get, ResourceUrl, accessToken);
        using var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        EnsureSuccess(response, responseBody, "list badge groups");
        return ParseList(responseBody, ParseBadgeCollection, "badge groups");
    }

    /// <summary>
    /// Creates a badge group. Handles 409 Conflict if it already exists.
    /// Returns the actual group ID from the service.
    /// </summary>
    /// <remarks>
    /// Creation is a long-running operation. The service responds with 202 Accepted and a
    /// badgePrintOperation body (V3: printBadgeGroupCreateOperation with printBadgeGroup.id).
    /// The operation carries its ID and the eventual resource ID. The
    /// group appears in the list before it is provisioned, so we must poll
    /// GET /print/operations/{operationId} until the operation state is 'succeeded' before the
    /// group can accept badges — otherwise adding a badge fails with 404.
    /// </remarks>
    public async Task<BadgeCollectionCreationResult> CreateBadgeCollectionAsync(string accessToken)
    {
        using var request = CreateRequest(HttpMethod.Post, ResourceUrl, accessToken);
        request.Content = new StringContent("{}", Encoding.UTF8, "application/json");
        using var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (response.StatusCode == HttpStatusCode.Conflict)
        {
            ConsoleHelper.WriteInfo("The badge group already exists (this is OK).");
            return new BadgeCollectionCreationResult(
                await GetBadgeCollectionIdAsync(accessToken),
                Created: false);
        }

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Failed to create badge group: {response.StatusCode} - {responseBody}", null, response.StatusCode);
        }
        if (UseV3BadgeApi)
        {
            EnsureStatus(response, responseBody, HttpStatusCode.Accepted, "create badge group");
        }

        ConsoleHelper.WriteInfo("The badge group creation was initiated.");

        // 202 Accepted: creation is a long-running operation — poll the operation to completion.
        if (response.StatusCode == HttpStatusCode.Accepted)
        {
            var (operationId, collectionId) = ParseBadgePrintOperation(responseBody);

            if (string.IsNullOrEmpty(operationId))
            {
                throw new InvalidOperationException(
                    "The badge group creation returned 202 Accepted without an operation ID to poll.");
            }

            ConsoleHelper.WriteProgress("Waiting for badge group to be provisioned (this can take up to 10 minutes)...");
            var completedResourceId = await WaitForBadgeCollectionOperationAsync(accessToken, operationId);

            if (UseV3BadgeApi)
            {
                var groupId = !string.IsNullOrWhiteSpace(completedResourceId) ? completedResourceId : collectionId;
                if (string.IsNullOrWhiteSpace(groupId))
                {
                    throw new InvalidOperationException(
                        "Badge group creation succeeded without printBadgeGroup.id.");
                }

                return new BadgeCollectionCreationResult(groupId, Created: true);
            }

            // The collection ID is returned with the operation; fall back to a list lookup if absent.
            return new BadgeCollectionCreationResult(
                !string.IsNullOrEmpty(collectionId)
                    ? collectionId
                    : await GetBadgeCollectionIdAsync(accessToken),
                Created: true);
        }

        return new BadgeCollectionCreationResult(
            await GetBadgeCollectionIdAsync(accessToken),
            Created: true);
    }

    /// <summary>
    /// Polls GET /print/operations/{operationId} until the badge group provisioning
    /// operation reaches a terminal state, honoring the service's Retry-After hint.
    /// </summary>
    private async Task<string> WaitForBadgeCollectionOperationAsync(string accessToken, string operationId)
    {
        var maxWait = TimeSpan.FromMinutes(10);
        var defaultDelay = TimeSpan.FromSeconds(5);
        var stopwatch = Stopwatch.StartNew();
        ConsoleHelper.WriteInfo($"The badge group operation ID: {operationId}");

        while (stopwatch.Elapsed < maxWait)
        {
            using var request = CreateRequest(
                HttpMethod.Get,
                $"{graphBaseUrl}/print/operations/{Uri.EscapeDataString(operationId)}",
                accessToken);
            using var response = await httpClient.SendAsync(request);
            var responseBody = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                throw new HttpRequestException(
                    $"Failed to poll badge group operation: {response.StatusCode} - {responseBody}", null, response.StatusCode);
            }

            var state = ParseOperationState(responseBody);
            var displayState = string.IsNullOrWhiteSpace(state) ? "unknown" : state;
            ConsoleHelper.WriteInfo($"The badge group operation state: {displayState}");

            switch (state?.ToLowerInvariant())
            {
                case "succeeded":
                    ConsoleHelper.WriteSuccess("The badge group provisioning completed.");
                    return UseV3BadgeApi ? ParseBadgePrintOperation(responseBody).CollectionId : string.Empty;
                case "failed":
                    throw new InvalidOperationException(
                        $"The badge group provisioning failed: {responseBody}");
            }

            var remainingWait = maxWait - stopwatch.Elapsed;
            if (remainingWait <= TimeSpan.Zero)
            {
                break;
            }

            var delay = GetRetryDelay(
                response.Headers.RetryAfter,
                defaultDelay,
                remainingWait,
                DateTimeOffset.UtcNow);
            ConsoleHelper.WriteProgress(
                $"The badge group provisioning is still in progress; retrying in {delay.TotalSeconds:0.#}s...");
            await Task.Delay(delay);
        }

        throw new TimeoutException("Timed out waiting for badge group provisioning to complete.");
    }

    internal static TimeSpan GetRetryDelay(
        RetryConditionHeaderValue? retryAfter,
        TimeSpan defaultDelay,
        TimeSpan remainingWait,
        DateTimeOffset now)
    {
        var requestedDelay = retryAfter?.Delta
            ?? (retryAfter?.Date is { } retryDate ? retryDate - now : defaultDelay);
        requestedDelay = requestedDelay < TimeSpan.Zero ? TimeSpan.Zero : requestedDelay;
        return requestedDelay < remainingWait ? requestedDelay : remainingWait;
    }

    private (string OperationId, string CollectionId) ParseBadgePrintOperation(string responseBody)
    {
        if (string.IsNullOrWhiteSpace(responseBody))
        {
            return (string.Empty, string.Empty);
        }

        var doc = JsonSerializer.Deserialize<JsonElement>(responseBody);
        var operationId = doc.TryGetProperty("id", out var idProp) ? idProp.GetString() ?? string.Empty : string.Empty;
        var collectionId = UseV3BadgeApi
            ? doc.TryGetProperty("printBadgeGroup", out var group) && group.ValueKind == JsonValueKind.Object
                ? ReadNullableString(group, "id") ?? string.Empty
                : string.Empty
            : ReadNullableString(doc, "collectionId") ?? string.Empty;

        return (operationId, collectionId);
    }

    private static string ParseOperationState(string responseBody)
    {
        if (string.IsNullOrWhiteSpace(responseBody))
        {
            return string.Empty;
        }

        var doc = JsonSerializer.Deserialize<JsonElement>(responseBody);
        if (doc.TryGetProperty("status", out var statusProp) &&
            statusProp.TryGetProperty("state", out var stateProp))
        {
            return stateProp.GetString() ?? string.Empty;
        }

        return string.Empty;
    }

    private async Task<string> GetBadgeCollectionIdAsync(string accessToken)
    {
        var collectionId = await TryGetBadgeCollectionIdAsync(accessToken);
        return collectionId ?? throw new InvalidOperationException("No badge group ID was returned by the service.");
    }

    private async Task<string?> TryGetBadgeCollectionIdAsync(string accessToken)
    {
        var collections = await ListBadgeCollectionsAsync(accessToken);
        if (UseV3BadgeApi && collections.Count != 1)
        {
            throw new InvalidOperationException("Expected exactly one badge group when resolving the creation result.");
        }
        return collections.FirstOrDefault()?.Id;
    }

    public async Task<bool> DeleteBadgeCollectionAsync(string accessToken, string collectionId)
    {
        using var request = CreateRequest(
            HttpMethod.Delete,
            $"{ResourceUrl}/{Uri.EscapeDataString(collectionId)}",
            accessToken);
        using var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            return false;
        }

        EnsureSuccess(response, responseBody, "delete badge group");
        return true;
    }

    /// <summary>
    /// Adds a badge to the group with the given badge ID and user UPN.
    /// </summary>
    public async Task<BadgeMapping> AddBadgeAsync(
        string accessToken,
        string collectionId,
        string badgeId,
        string upn,
        string? userId = null)
    {
        if (UseV3BadgeApi && string.IsNullOrWhiteSpace(upn))
        {
            throw new ArgumentException("User principal name must be provided.", nameof(upn));
        }

        var requestBody = new Dictionary<string, string>
        {
            ["id"] = badgeId,
            [UseV3BadgeApi ? "userPrincipalName" : "upn"] = upn
        };

        if (!string.IsNullOrWhiteSpace(userId))
        {
            requestBody["userId"] = userId;
        }

        var json = JsonSerializer.Serialize(requestBody);
        using var request = CreateRequest(
            HttpMethod.Post,
            $"{ResourceUrl}/{Uri.EscapeDataString(collectionId)}/badges",
            accessToken);
        request.Content = new StringContent(json, Encoding.UTF8, "application/json");
        using var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (response.StatusCode == HttpStatusCode.Conflict)
        {
            throw new InvalidOperationException(
                $"Badge '{badgeId}' already exists. Choose a unique badge ID to avoid overwriting an existing user mapping.");
        }

        EnsureStatus(response, responseBody, HttpStatusCode.Created, "add badge");
        return ParseBadgeMapping(JsonSerializer.Deserialize<JsonElement>(responseBody));
    }

    public async Task<BadgeMappingListResult> ListBadgesAsync(string accessToken, string collectionId)
    {
        using var request = CreateRequest(
            HttpMethod.Get,
            $"{ResourceUrl}/{Uri.EscapeDataString(collectionId)}/badges",
            accessToken);
        using var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!UseV3BadgeApi && response.StatusCode == HttpStatusCode.NotImplemented)
        {
            return new BadgeMappingListResult(false, Array.Empty<BadgeMapping>());
        }

        EnsureSuccess(response, responseBody, "list badges");
        return new BadgeMappingListResult(
            true,
            ParseList(responseBody, ParseBadgeMapping, "badges"));
    }

    public async Task<BadgeMapping?> GetBadgeAsync(string accessToken, string collectionId, string badgeId)
    {
        using var request = CreateBadgeItemRequest(HttpMethod.Get, accessToken, collectionId, badgeId);
        using var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }

        EnsureSuccess(response, responseBody, "get badge");
        return ParseBadgeMapping(JsonSerializer.Deserialize<JsonElement>(responseBody));
    }

    public async Task<BadgeMapping> UpdateBadgeAsync(
        string accessToken,
        string collectionId,
        string badgeId,
        string upn,
        string? userId)
    {
        if (string.IsNullOrWhiteSpace(upn))
        {
            throw new ArgumentException("UPN must be provided.", nameof(upn));
        }

        var requestBody = new Dictionary<string, string>
        {
            [UseV3BadgeApi ? "userPrincipalName" : "upn"] = upn
        };

        if (!string.IsNullOrWhiteSpace(userId))
        {
            requestBody["userId"] = userId;
        }

        using var request = CreateBadgeItemRequest(HttpMethod.Patch, accessToken, collectionId, badgeId);
        request.Content = new StringContent(
            JsonSerializer.Serialize(requestBody),
            Encoding.UTF8,
            "application/json");
        using var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        EnsureStatus(response, responseBody, HttpStatusCode.OK, "update badge");
        return ParseBadgeMapping(JsonSerializer.Deserialize<JsonElement>(responseBody));
    }

    /// <summary>
    /// Deletes a badge from the group.
    /// </summary>
    public async Task<bool> DeleteBadgeAsync(string accessToken, string collectionId, string badgeId)
    {
        using var request = CreateBadgeItemRequest(HttpMethod.Delete, accessToken, collectionId, badgeId);
        using var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            return false;
        }

        EnsureSuccess(response, responseBody, "delete badge");
        return true;
    }

    private HttpRequestMessage CreateBadgeItemRequest(
        HttpMethod method,
        string accessToken,
        string collectionId,
        string badgeId) =>
        CreateRequest(
            method,
            $"{ResourceUrl}/{Uri.EscapeDataString(collectionId)}/badges/{Uri.EscapeDataString(badgeId)}",
            accessToken);

    private static HttpRequestMessage CreateRequest(HttpMethod method, string requestUri, string accessToken)
    {
        var request = new HttpRequestMessage(method, requestUri);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        return request;
    }

    private static void EnsureSuccess(HttpResponseMessage response, string responseBody, string operation)
    {
        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException(
                $"Failed to {operation}: {response.StatusCode} - {responseBody}",
                null,
                response.StatusCode);
        }
    }

    private static void EnsureStatus(
        HttpResponseMessage response,
        string responseBody,
        HttpStatusCode expectedStatus,
        string operation)
    {
        if (response.StatusCode != expectedStatus)
        {
            throw new HttpRequestException(
                $"Failed to {operation}: expected {expectedStatus}, received {response.StatusCode} - {responseBody}",
                null,
                response.StatusCode);
        }
    }

    private static IReadOnlyList<T> ParseList<T>(
        string responseBody,
        Func<JsonElement, T> parseItem,
        string resourceName)
    {
        var document = JsonSerializer.Deserialize<JsonElement>(responseBody);
        if (!document.TryGetProperty("value", out var items) || items.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidOperationException(
                $"{resourceName} response did not include a valid value array.");
        }

        return items.EnumerateArray().Select(parseItem).ToArray();
    }

    private BadgeCollection ParseBadgeCollection(JsonElement collection)
    {
        var id = collection.GetProperty("id").GetString();
        return !string.IsNullOrWhiteSpace(id)
            ? new BadgeCollection(
                id,
                UseV3BadgeApi ? ReadNullableString(collection, "displayName") : null,
                UseV3BadgeApi ? ReadNullableString(collection, "createdDateTime") : null)
            : throw new InvalidOperationException("The badge group response contained an empty ID.");
    }

    private BadgeMapping ParseBadgeMapping(JsonElement badge)
    {
        var id = badge.GetProperty("id").GetString();
        var upn = UseV3BadgeApi
            ? ReadNullableString(badge, "userPrincipalName")
            : badge.GetProperty("upn").GetString();

        if (string.IsNullOrWhiteSpace(id) || (!UseV3BadgeApi && string.IsNullOrWhiteSpace(upn)))
        {
            throw new InvalidOperationException("Badge response contained an empty ID or UPN.");
        }

        var userId = badge.TryGetProperty("userId", out var userIdProperty) &&
                     userIdProperty.ValueKind != JsonValueKind.Null
            ? userIdProperty.GetString()
            : null;

        return new BadgeMapping(
            id, upn, userId,
            UseV3BadgeApi ? ReadNullableString(badge, "physicalBadgeId") : null,
            UseV3BadgeApi ? ReadNullableString(badge, "createdDateTime") : null);
    }

    private static string? ReadNullableString(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property) && property.ValueKind != JsonValueKind.Null
            ? property.GetString()
            : null;
}

public sealed record BadgeCollection(string Id, string? DisplayName = null, string? CreatedDateTime = null);

public sealed record BadgeCollectionCreationResult(string Id, bool Created);

public sealed record BadgeMapping(
    string Id, string? Upn, string? UserId, string? PhysicalBadgeId = null, string? CreatedDateTime = null);

public sealed record BadgeMappingListResult(bool IsSupported, IReadOnlyList<BadgeMapping> Badges);
