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
    private readonly string graphBaseUrl;
    private readonly HttpClient httpClient;

    public BadgeManagement(string graphBaseUrl)
    {
        this.graphBaseUrl = graphBaseUrl;
        httpClient = new HttpClient();
    }

    public void Dispose() => httpClient.Dispose();

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
        using var request = new HttpRequestMessage(HttpMethod.Post, $"{graphBaseUrl}/print/badgeCollections");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Content = new StringContent("{}", Encoding.UTF8, "application/json");
        var response = await httpClient.SendAsync(request);
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

        while (DateTime.UtcNow - startTime < maxWait)
        {
            using var request = new HttpRequestMessage(
                HttpMethod.Get, $"{graphBaseUrl}/print/operations/{Uri.EscapeDataString(operationId)}");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
            var response = await httpClient.SendAsync(request);
            var responseBody = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                throw new HttpRequestException(
                    $"Failed to poll badge collection operation: {response.StatusCode} - {responseBody}");
            }

            var state = ParseOperationState(responseBody);

            switch (state)
            {
                case "succeeded":
                    return;
                case "failed":
                    throw new InvalidOperationException(
                        $"Badge collection provisioning failed: {responseBody}");
            }

            var delay = response.Headers.RetryAfter?.Delta ?? defaultDelay;
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
        using var request = new HttpRequestMessage(HttpMethod.Get, $"{graphBaseUrl}/print/badgeCollections");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException(
                $"Failed to list badge collections: {response.StatusCode} - {responseBody}");
        }

        var listDoc = JsonSerializer.Deserialize<JsonElement>(responseBody);
        if (!listDoc.TryGetProperty("value", out var collections) || collections.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidOperationException("Badge collections response did not include a valid value array.");
        }

        foreach (var collection in collections.EnumerateArray())
        {
            if (collection.TryGetProperty("id", out var idProperty))
            {
                var collectionId = idProperty.GetString();
                if (!string.IsNullOrWhiteSpace(collectionId))
                {
                    return collectionId;
                }
            }
        }

        return null;
    }

    /// <summary>
    /// Adds a badge to the collection with the given badge ID and user UPN.
    /// </summary>
    public async Task AddBadgeAsync(string accessToken, string collectionId, string badgeId, string upn)
    {
        var requestBody = new
        {
            id = badgeId,
            upn
        };

        var json = JsonSerializer.Serialize(requestBody);
        using var request = new HttpRequestMessage(HttpMethod.Post,
            $"{graphBaseUrl}/print/badgeCollections/{collectionId}/badges");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Content = new StringContent(json, Encoding.UTF8, "application/json");
        var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (response.StatusCode == HttpStatusCode.Conflict)
        {
            throw new InvalidOperationException(
                $"Badge '{badgeId}' already exists. Choose a unique badge ID to avoid overwriting an existing user mapping.");
        }

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Failed to add badge: {response.StatusCode} - {responseBody}");
        }
    }

    /// <summary>
    /// Deletes a badge from the collection.
    /// </summary>
    public async Task DeleteBadgeAsync(string accessToken, string collectionId, string badgeId)
    {
        using var request = new HttpRequestMessage(HttpMethod.Delete,
            $"{graphBaseUrl}/print/badgeCollections/{collectionId}/badges/{Uri.EscapeDataString(badgeId)}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        var response = await httpClient.SendAsync(request);
        if (!response.IsSuccessStatusCode && response.StatusCode != HttpStatusCode.NotFound)
        {
            var body = await response.Content.ReadAsStringAsync();
            ConsoleHelper.WriteWarning($"Failed to delete badge: {response.StatusCode} - {body}");
        }
    }
}
