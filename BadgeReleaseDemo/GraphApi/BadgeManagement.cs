// <copyright file="BadgeManagement.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using BadgeReleaseDemo.Helpers;

namespace BadgeReleaseDemo.GraphApi;

/// <summary>
/// Handles badge collection and badge CRUD via MS Graph API.
/// </summary>
public class BadgeManagement : IDisposable
{
    public const string CollectionSettlingNote =
        "NOTE: Badge writes may need additional time to settle after collection provisioning succeeds. " +
        "If adding a badge returns 'Badge collection not found', wait a few minutes and retry.";

    private readonly string graphBaseUrl;
    private readonly HttpClient httpClient;

    public BadgeManagement(string graphBaseUrl, HttpMessageHandler? httpMessageHandler = null)
    {
        this.graphBaseUrl = graphBaseUrl;
        httpClient = httpMessageHandler == null
            ? new HttpClient()
            : new HttpClient(httpMessageHandler);
    }

    public void Dispose() => httpClient.Dispose();

    public async Task<IReadOnlyList<BadgeCollection>> ListBadgeCollectionsAsync(string accessToken)
    {
        using var request = CreateRequest(HttpMethod.Get, $"{graphBaseUrl}/print/badgeCollections", accessToken);
        using var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        EnsureSuccess(response, responseBody, "list badge collections");
        return ParseList(responseBody, ParseBadgeCollection, "badge collections");
    }

    /// <summary>
    /// Creates a badge collection. Handles 409 Conflict if it already exists.
    /// Returns the actual collection ID from the service.
    /// </summary>
    /// <remarks>
    /// Creation is a long-running operation. The service responds with 202 Accepted and a
    /// badgePrintOperation body carrying an operation ID and the eventual collection ID. The
    /// collection appears in the list before it is provisioned, so we must poll
    /// GET /print/operations/{operationId} until the operation state is 'succeeded' before the
    /// collection can accept badges — otherwise adding a badge fails with 404.
    /// </remarks>
    public async Task<string> CreateBadgeCollectionAsync(string accessToken)
    {
        using var request = CreateRequest(HttpMethod.Post, $"{graphBaseUrl}/print/badgeCollections", accessToken);
        request.Content = new StringContent("{}", Encoding.UTF8, "application/json");
        using var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (response.StatusCode == HttpStatusCode.Conflict)
        {
            ConsoleHelper.WriteInfo("Badge collection already exists (this is OK).");
            return await GetBadgeCollectionIdAsync(accessToken);
        }

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Failed to create badge collection: {response.StatusCode} - {responseBody}");
        }

        ConsoleHelper.WriteInfo("Badge collection creation initiated.");

        // 202 Accepted: creation is a long-running operation — poll the operation to completion.
        if (response.StatusCode == HttpStatusCode.Accepted)
        {
            var (operationId, collectionId) = ParseBadgePrintOperation(responseBody);

            if (string.IsNullOrEmpty(operationId))
            {
                throw new InvalidOperationException(
                    "Badge collection creation returned 202 Accepted without an operation ID to poll.");
            }

            ConsoleHelper.WriteProgress("Waiting for badge collection to be provisioned (this can take up to 10 minutes)...");
            await WaitForBadgeCollectionOperationAsync(accessToken, operationId);

            // The collection ID is returned with the operation; fall back to a list lookup if absent.
            return !string.IsNullOrEmpty(collectionId)
                ? collectionId
                : await GetBadgeCollectionIdAsync(accessToken);
        }

        return await GetBadgeCollectionIdAsync(accessToken);
    }

    /// <summary>
    /// Polls GET /print/operations/{operationId} until the badge collection provisioning
    /// operation reaches a terminal state, honoring the service's Retry-After hint.
    /// </summary>
    private async Task WaitForBadgeCollectionOperationAsync(string accessToken, string operationId)
    {
        var maxWait = TimeSpan.FromMinutes(10);
        var defaultDelay = TimeSpan.FromSeconds(5);
        var startTime = DateTime.UtcNow;
        ConsoleHelper.WriteInfo($"Badge collection operation ID: {operationId}");

        while (DateTime.UtcNow - startTime < maxWait)
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
                    $"Failed to poll badge collection operation: {response.StatusCode} - {responseBody}");
            }

            var state = ParseOperationState(responseBody);
            var displayState = string.IsNullOrWhiteSpace(state) ? "unknown" : state;
            ConsoleHelper.WriteInfo($"Badge collection operation state: {displayState}");

            switch (state?.ToLowerInvariant())
            {
                case "succeeded":
                    ConsoleHelper.WriteSuccess("Badge collection provisioning completed.");
                    return;
                case "failed":
                    throw new InvalidOperationException(
                        $"Badge collection provisioning failed: {responseBody}");
            }

            var delay = response.Headers.RetryAfter?.Delta ?? defaultDelay;
            ConsoleHelper.WriteProgress(
                $"Badge collection provisioning is still in progress; retrying in {delay.TotalSeconds:0.#}s...");
            await Task.Delay(delay);
        }

        throw new TimeoutException("Timed out waiting for badge collection provisioning to complete.");
    }

    private static (string OperationId, string CollectionId) ParseBadgePrintOperation(string responseBody)
    {
        if (string.IsNullOrWhiteSpace(responseBody))
        {
            return (string.Empty, string.Empty);
        }

        var doc = JsonSerializer.Deserialize<JsonElement>(responseBody);
        var operationId = doc.TryGetProperty("id", out var idProp) ? idProp.GetString() ?? string.Empty : string.Empty;
        var collectionId = doc.TryGetProperty("collectionId", out var collectionProp)
            ? collectionProp.GetString() ?? string.Empty
            : string.Empty;

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
        return collectionId ?? throw new InvalidOperationException("No badge collection ID was returned by the service.");
    }

    private async Task<string?> TryGetBadgeCollectionIdAsync(string accessToken)
    {
        var collections = await ListBadgeCollectionsAsync(accessToken);
        return collections.FirstOrDefault()?.Id;
    }

    public async Task<bool> DeleteBadgeCollectionAsync(string accessToken, string collectionId)
    {
        using var request = CreateRequest(
            HttpMethod.Delete,
            $"{graphBaseUrl}/print/badgeCollections/{Uri.EscapeDataString(collectionId)}",
            accessToken);
        using var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            return false;
        }

        EnsureSuccess(response, responseBody, "delete badge collection");
        return true;
    }

    /// <summary>
    /// Adds a badge to the collection with the given badge ID and user UPN.
    /// </summary>
    public async Task<BadgeMapping> AddBadgeAsync(
        string accessToken,
        string collectionId,
        string badgeId,
        string upn,
        string? userId = null)
    {
        var requestBody = new Dictionary<string, string>
        {
            ["id"] = badgeId,
            ["upn"] = upn
        };

        if (!string.IsNullOrWhiteSpace(userId))
        {
            requestBody["userId"] = userId;
        }

        var json = JsonSerializer.Serialize(requestBody);
        using var request = CreateRequest(
            HttpMethod.Post,
            $"{graphBaseUrl}/print/badgeCollections/{Uri.EscapeDataString(collectionId)}/badges",
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
            $"{graphBaseUrl}/print/badgeCollections/{Uri.EscapeDataString(collectionId)}/badges",
            accessToken);
        using var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (response.StatusCode == HttpStatusCode.NotImplemented)
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
            ["upn"] = upn
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
    /// Deletes a badge from the collection.
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
            $"{graphBaseUrl}/print/badgeCollections/{Uri.EscapeDataString(collectionId)}/badges/{Uri.EscapeDataString(badgeId)}",
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

    private static BadgeCollection ParseBadgeCollection(JsonElement collection)
    {
        var id = collection.GetProperty("id").GetString();
        return !string.IsNullOrWhiteSpace(id)
            ? new BadgeCollection(id)
            : throw new InvalidOperationException("Badge collection response contained an empty ID.");
    }

    private static BadgeMapping ParseBadgeMapping(JsonElement badge)
    {
        var id = badge.GetProperty("id").GetString();
        var upn = badge.GetProperty("upn").GetString();

        if (string.IsNullOrWhiteSpace(id) || string.IsNullOrWhiteSpace(upn))
        {
            throw new InvalidOperationException("Badge response contained an empty ID or UPN.");
        }

        var userId = badge.TryGetProperty("userId", out var userIdProperty) &&
                     userIdProperty.ValueKind != JsonValueKind.Null
            ? userIdProperty.GetString()
            : null;

        return new BadgeMapping(id, upn, userId);
    }
}

public sealed record BadgeCollection(string Id);

public sealed record BadgeMapping(string Id, string Upn, string? UserId);

public sealed record BadgeMappingListResult(bool IsSupported, IReadOnlyList<BadgeMapping> Badges);
