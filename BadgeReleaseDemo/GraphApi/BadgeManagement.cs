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
    private const string SingleCollectionId = "0";
    private readonly string graphBaseUrl;
    private readonly HttpClient httpClient;

    public BadgeManagement(string graphBaseUrl)
    {
        this.graphBaseUrl = graphBaseUrl;
        httpClient = new HttpClient();
    }

    /// <summary>
    /// Creates a badge collection. Handles 409 Conflict if it already exists.
    /// Returns the collection ID (always "0").
    /// </summary>
    public async Task<string> CreateBadgeCollectionAsync(string accessToken)
    {
        httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        var content = new StringContent("{}", Encoding.UTF8, "application/json");
        var response = await httpClient.PostAsync($"{graphBaseUrl}/print/badgeCollections", content);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (response.StatusCode == HttpStatusCode.Conflict)
        {
            ConsoleHelper.WriteInfo("Badge collection already exists (this is OK).");
            return SingleCollectionId;
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
            await WaitForBadgeCollectionProvisioningAsync(accessToken);
        }

        return SingleCollectionId;
    }

    private async Task WaitForBadgeCollectionProvisioningAsync(string accessToken)
    {
        httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        const int maxAttempts = 60;
        const int delayMilliseconds = 10000;

        for (var attempt = 1; attempt <= maxAttempts; attempt++)
        {
            var response = await httpClient.GetAsync($"{graphBaseUrl}/print/badgeCollections/{SingleCollectionId}");

            if (response.IsSuccessStatusCode)
            {
                return;
            }

            var responseBody = await response.Content.ReadAsStringAsync();

            if (response.StatusCode != HttpStatusCode.NotFound)
            {
                throw new HttpRequestException(
                    $"Failed while waiting for badge collection provisioning: {response.StatusCode} - {responseBody}");
            }

            if (attempt < maxAttempts)
            {
                await Task.Delay(delayMilliseconds);
            }
        }

        throw new TimeoutException("Timed out waiting for badge collection provisioning to complete.");
    }

    /// <summary>
    /// Adds a badge to the collection with the given badge ID and user UPN.
    /// </summary>
    public async Task AddBadgeAsync(string accessToken, string badgeId, string upn)
    {
        httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        var requestBody = new
        {
            id = badgeId,
            upn
        };

        var json = JsonSerializer.Serialize(requestBody);
        var content = new StringContent(json, Encoding.UTF8, "application/json");

        var response = await httpClient.PostAsync(
            $"{graphBaseUrl}/print/badgeCollections/{SingleCollectionId}/badges",
            content);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (response.StatusCode == HttpStatusCode.Conflict)
        {
            ConsoleHelper.WriteInfo($"Badge '{badgeId}' already exists. Updating...");
            await UpdateBadgeAsync(accessToken, badgeId, upn);
            return;
        }

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Failed to add badge: {response.StatusCode} - {responseBody}");
        }
    }

    /// <summary>
    /// Updates an existing badge's UPN.
    /// </summary>
    private async Task UpdateBadgeAsync(string accessToken, string badgeId, string upn)
    {
        var requestBody = new { upn };
        var json = JsonSerializer.Serialize(requestBody);
        var request = new HttpRequestMessage(HttpMethod.Patch,
            $"{graphBaseUrl}/print/badgeCollections/{SingleCollectionId}/badges/{badgeId}")
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Failed to update badge: {response.StatusCode} - {responseBody}");
        }
    }

    /// <summary>
    /// Deletes a badge from the collection.
    /// </summary>
    public async Task DeleteBadgeAsync(string accessToken, string badgeId)
    {
        using var request = new HttpRequestMessage(HttpMethod.Delete,
            $"{graphBaseUrl}/print/badgeCollections/{SingleCollectionId}/badges/{badgeId}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        var response = await httpClient.SendAsync(request);
        if (!response.IsSuccessStatusCode && response.StatusCode != HttpStatusCode.NotFound)
        {
            var body = await response.Content.ReadAsStringAsync();
            ConsoleHelper.WriteWarning($"Failed to delete badge: {response.StatusCode} - {body}");
        }
    }
}
