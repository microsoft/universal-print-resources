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
    private readonly string graphBetaBaseUrl;
    private readonly HttpClient httpClient;

    public PrinterSharing(string graphBaseUrl, HttpMessageHandler? httpMessageHandler = null)
    {
        this.graphBaseUrl = graphBaseUrl.TrimEnd('/');
        graphBetaBaseUrl = ReplaceApiVersion(this.graphBaseUrl, "beta");
        httpClient = httpMessageHandler == null
            ? new HttpClient()
            : new HttpClient(httpMessageHandler);
    }

    public void Dispose() => httpClient.Dispose();

    /// <summary>
    /// Creates a printer share, enables secure-release holding through the beta share
    /// endpoint, and validates that the setting was applied. Returns the share ID.
    /// </summary>
    public async Task<string> CreateShareAsync(string accessToken, string printerId, string displayName)
    {
        var requestBody = new Dictionary<string, object>
        {
            ["displayName"] = displayName,
            ["allowAllUsers"] = true,
            ["printer@odata.bind"] = $"{graphBaseUrl}/print/printers/{printerId}",
        };

        var json = JsonSerializer.Serialize(requestBody);
        using var request = new HttpRequestMessage(HttpMethod.Post, $"{graphBaseUrl}/print/shares");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Content = new StringContent(json, Encoding.UTF8, "application/json");

        using var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Failed to create printer share: {response.StatusCode} - {responseBody}");
        }

        var shareDoc = JsonSerializer.Deserialize<JsonElement>(responseBody);
        var shareId = shareDoc.GetProperty("id").GetString()
            ?? throw new InvalidOperationException("No share ID in response.");

        try
        {
            await EnableSecureReleaseAsync(accessToken, shareId);
            await ValidateSecureReleaseAsync(accessToken, shareId);
            return shareId;
        }
        catch
        {
            try
            {
                await DeleteShareAsync(accessToken, shareId);
            }
            catch (Exception cleanupException)
            {
                ConsoleHelper.WriteWarning(
                    $"Failed to delete share during rollback: {cleanupException.Message}");
            }

            throw;
        }
    }

    private async Task EnableSecureReleaseAsync(string accessToken, string shareId)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Patch,
            $"{graphBetaBaseUrl}/print/shares/{Uri.EscapeDataString(shareId)}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Content = new StringContent(
            """{"holdJobsForSecureRelease":true}""",
            Encoding.UTF8,
            "application/json");

        using var response = await httpClient.SendAsync(request);
        if (!response.IsSuccessStatusCode)
        {
            var responseBody = await response.Content.ReadAsStringAsync();
            throw new HttpRequestException(
                $"Failed to enable secure release on printer share: {response.StatusCode} - {responseBody}");
        }
    }

    private async Task ValidateSecureReleaseAsync(string accessToken, string shareId)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            $"{graphBetaBaseUrl}/print/shares/{Uri.EscapeDataString(shareId)}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        using var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();
        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException(
                $"Failed to validate printer share secure release: {response.StatusCode} - {responseBody}");
        }

        var share = JsonSerializer.Deserialize<JsonElement>(responseBody);
        if (!share.TryGetProperty("holdJobsForSecureRelease", out var holdJobs) ||
            holdJobs.ValueKind != JsonValueKind.True)
        {
            throw new InvalidOperationException(
                "Printer share validation did not confirm holdJobsForSecureRelease=true.");
        }
    }

    /// <summary>
    /// Deletes a printer share.
    /// </summary>
    public async Task DeleteShareAsync(string accessToken, string shareId)
    {
        using var request = new HttpRequestMessage(HttpMethod.Delete,
            $"{graphBaseUrl}/print/shares/{Uri.EscapeDataString(shareId)}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        using var response = await httpClient.SendAsync(request);
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

        using var response = await httpClient.SendAsync(request);
        if (!response.IsSuccessStatusCode && response.StatusCode != System.Net.HttpStatusCode.NotFound)
        {
            var body = await response.Content.ReadAsStringAsync();
            ConsoleHelper.WriteWarning($"Failed to delete printer: {response.StatusCode} - {body}");
        }
    }

    private static string ReplaceApiVersion(string baseUrl, string apiVersion)
    {
        var uri = new Uri(baseUrl);
        var pathSegments = uri.AbsolutePath.Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (pathSegments.Length == 0)
        {
            throw new ArgumentException("Graph base URL must include an API version.", nameof(baseUrl));
        }

        pathSegments[^1] = apiVersion;
        var builder = new UriBuilder(uri)
        {
            Path = string.Join('/', pathSegments)
        };
        return builder.Uri.ToString().TrimEnd('/');
    }
}
