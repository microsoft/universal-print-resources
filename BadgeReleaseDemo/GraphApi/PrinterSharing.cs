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
public class PrinterSharing : IDisposable
{
    private readonly string graphBaseUrl;
    private readonly HttpClient httpClient;

    public PrinterSharing(string graphBaseUrl)
    {
        this.graphBaseUrl = graphBaseUrl;
        httpClient = new HttpClient();
    }

    public void Dispose() => httpClient.Dispose();

    /// <summary>
    /// Creates a printer share with allowAllUsers=true and secure release enabled.
    /// Setting holdJobsForSecureRelease=true holds jobs in the cloud until the user
    /// authenticates at the printer (e.g. via a badge tap), which is what enables the
    /// badge release flow. Returns the share ID.
    /// </summary>
    public async Task<string> CreateShareAsync(string accessToken, string printerId, string displayName)
    {
        var requestBody = new Dictionary<string, object>
        {
            ["displayName"] = displayName,
            ["allowAllUsers"] = true,
            ["holdJobsForSecureRelease"] = true,
            ["printer@odata.bind"] = $"{graphBaseUrl}/print/printers/{printerId}",
        };

        var json = JsonSerializer.Serialize(requestBody);
        using var request = new HttpRequestMessage(HttpMethod.Post, $"{graphBaseUrl}/print/shares");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Content = new StringContent(json, Encoding.UTF8, "application/json");

        var response = await httpClient.SendAsync(request);
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
