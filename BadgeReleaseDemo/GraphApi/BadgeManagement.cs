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
public class BadgeManagement
{
    private readonly string graphBaseUrl;
    private readonly HttpClient httpClient;

    public BadgeManagement(string graphBaseUrl)
    {
        this.graphBaseUrl = graphBaseUrl;
        httpClient = new HttpClient();
    }

    /// <summary>
    /// Creates a badge collection. Handles 409 Conflict if it already exists.
    /// Returns the actual collection ID from the service.
    /// </summary>
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

        if (!response.IsSuccessStatusCode && response.StatusCode != HttpStatusCode.Accepted)
        {
            throw new HttpRequestException($"Failed to create badge collection: {response.StatusCode} - {responseBody}");
        }

        ConsoleHelper.WriteInfo("Badge collection creation initiated.");

        // Poll until the badge collection is provisioned (can take up to 10 minutes)
        if (response.StatusCode == HttpStatusCode.Accepted)
        {
            ConsoleHelper.WriteProgress("Waiting for badge collection to be provisioned (this can take up to 10 minutes)...");
            return await WaitForBadgeCollectionProvisioningAsync(accessToken);
        }

        return await GetBadgeCollectionIdAsync(accessToken);
    }

    private async Task<string> WaitForBadgeCollectionProvisioningAsync(string accessToken)
    {
        const int maxAttempts = 60;
        const int delayMilliseconds = 10000;

        for (var attempt = 1; attempt <= maxAttempts; attempt++)
        {
            var collectionId = await TryGetBadgeCollectionIdAsync(accessToken);

            if (!string.IsNullOrEmpty(collectionId))
            {
                return collectionId;
            }

            if (attempt < maxAttempts)
            {
                await Task.Delay(delayMilliseconds);
            }
        }

        throw new TimeoutException("Timed out waiting for badge collection provisioning to complete.");
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
            $"{graphBaseUrl}/print/badgeCollections/{collectionId}/badges/{badgeId}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        var response = await httpClient.SendAsync(request);
        if (!response.IsSuccessStatusCode && response.StatusCode != HttpStatusCode.NotFound)
        {
            var body = await response.Content.ReadAsStringAsync();
            ConsoleHelper.WriteWarning($"Failed to delete badge: {response.StatusCode} - {body}");
        }
    }
}
