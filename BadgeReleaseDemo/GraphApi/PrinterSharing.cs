// <copyright file="PrinterSharing.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using BadgeReleaseDemo.Helpers;

namespace BadgeReleaseDemo.GraphApi;

/// <summary>
/// Handles printer sharing via MS Graph API.
/// </summary>
public class PrinterSharing
{
    private readonly string graphBaseUrl;
    private readonly HttpClient httpClient;

    public PrinterSharing(string graphBaseUrl)
    {
        this.graphBaseUrl = graphBaseUrl;
        httpClient = new HttpClient();
    }

    /// <summary>
    /// Creates a printer share with allowAllUsers=true.
    /// Returns the share ID.
    /// </summary>
    public async Task<string> CreateShareAsync(string accessToken, string printerId, string displayName)
    {
        httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        var requestBody = new Dictionary<string, object>
        {
            ["displayName"] = displayName,
            ["allowAllUsers"] = true,
            ["printer@odata.bind"] = $"{graphBaseUrl}/print/printers/{printerId}",
        };

        var json = JsonSerializer.Serialize(requestBody);
        var content = new StringContent(json, Encoding.UTF8, "application/json");

        var response = await httpClient.PostAsync($"{graphBaseUrl}/print/shares", content);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Failed to create printer share: {response.StatusCode} - {responseBody}");
        }

        var shareDoc = JsonSerializer.Deserialize<JsonElement>(responseBody);
        return shareDoc.GetProperty("id").GetString()
            ?? throw new InvalidOperationException("No share ID in response.");
    }

    /// <summary>
    /// Enables badge release on the printer via Graph PATCH /print/printers/{id}.
    /// Sets releaseMechanisms to qrCode which enables pull-print/badge release.
    /// </summary>
    public async Task EnableBadgeReleaseAsync(string graphToken, string printerId)
    {
        var patchBody = new
        {
            releaseMechanisms = new[]
            {
                new
                {
                    releaseType = "qrCode",
                },
            },
        };

        var json = JsonSerializer.Serialize(patchBody);
        using var request = new HttpRequestMessage(HttpMethod.Patch,
            $"{graphBaseUrl}/print/printers/{printerId}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", graphToken);
        request.Content = new StringContent(json, Encoding.UTF8, "application/json");

        var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException(
                $"Failed to enable badge release: {response.StatusCode} - {responseBody}");
        }
    }

    /// <summary>
    /// Deletes a printer share.
    /// </summary>
    public async Task DeleteShareAsync(string accessToken, string shareId)
    {
        using var request = new HttpRequestMessage(HttpMethod.Delete,
            $"{graphBaseUrl}/print/shares/{shareId}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        var response = await httpClient.SendAsync(request);
        if (!response.IsSuccessStatusCode && response.StatusCode != System.Net.HttpStatusCode.NotFound)
        {
            var body = await response.Content.ReadAsStringAsync();
            ConsoleHelper.WriteWarning($"Failed to delete share: {response.StatusCode} - {body}");
        }
    }

    /// <summary>
    /// Deletes a printer.
    /// </summary>
    public async Task DeletePrinterAsync(string accessToken, string printerId)
    {
        using var request = new HttpRequestMessage(HttpMethod.Delete,
            $"{graphBaseUrl}/print/printers/{printerId}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        var response = await httpClient.SendAsync(request);
        if (!response.IsSuccessStatusCode && response.StatusCode != System.Net.HttpStatusCode.NotFound)
        {
            var body = await response.Content.ReadAsStringAsync();
            ConsoleHelper.WriteWarning($"Failed to delete printer: {response.StatusCode} - {body}");
        }
    }
}
