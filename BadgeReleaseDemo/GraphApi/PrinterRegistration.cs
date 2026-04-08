// <copyright file="PrinterRegistration.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using BadgeReleaseDemo.Helpers;

namespace BadgeReleaseDemo.GraphApi;

/// <summary>
/// Handles printer registration via the Universal Print Registration Service
/// (https://register.print.microsoft.com).
/// </summary>
public class PrinterRegistration
{
    private readonly string registrationBaseUrl;
    private readonly HttpClient httpClient;

    public PrinterRegistration(string registrationBaseUrl)
    {
        this.registrationBaseUrl = registrationBaseUrl.TrimEnd('/');
        httpClient = new HttpClient { Timeout = TimeSpan.FromMinutes(2) };
    }

    /// <summary>
    /// Registers a new printer with Universal Print via the registration service.
    /// Returns a record with all fields needed for device token acquisition.
    /// </summary>
    public async Task<PrinterRegistrationResult> RegisterPrinterAsync(
        string accessToken,
        string displayName,
        string csrContent,
        string transportKey)
    {
        httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        // Step 1: Initiate registration via POST /api/v1.0/register
        // Registration API uses snake_case field names
        var requestBody = new Dictionary<string, object>
        {
            ["name"] = displayName,
            ["manufacturer"] = "Badge Release Demo",
            ["model"] = "Virtual Printer",
            ["device_type"] = "printer",
            ["device_capabilities"] = new[] { "print" },
            ["preferred_lang"] = "en-us",
            ["certificate_request"] = new Dictionary<string, string>
            {
                ["type"] = "pkcs10",
                ["data"] = csrContent,
                ["transport_key"] = transportKey,
            },
            ["has_physical_device"] = false,
        };

        var json = JsonSerializer.Serialize(requestBody);
        var content = new StringContent(json, Encoding.UTF8, "application/json");

        var regUrl = $"{registrationBaseUrl}/api/v1.0/register";
        var response = await httpClient.PostAsync(regUrl, content);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Failed to initiate printer registration: {response.StatusCode} - {responseBody}");
        }

        // Parse the registration ID from the response
        var regResp = JsonSerializer.Deserialize<JsonElement>(responseBody);
        var registrationId = regResp.GetProperty("registration_id").GetString()
            ?? throw new InvalidOperationException("No registration_id in registration response.");

        ConsoleHelper.WriteInfo($"Registration initiated (ID: {registrationId})");

        // Step 2: Poll GET /api/v1.0/register?registration_id={id} until 200 OK
        ConsoleHelper.WriteProgress("Polling registration status...");
        var statusUrl = $"{registrationBaseUrl}/api/v1.0/register?registration_id={registrationId}";

        var startTime = DateTime.UtcNow;
        var maxWait = TimeSpan.FromMinutes(5);

        while (DateTime.UtcNow - startTime < maxWait)
        {
            var statusResp = await httpClient.GetAsync(statusUrl);
            var statusBody = await statusResp.Content.ReadAsStringAsync();

            if (statusResp.StatusCode == HttpStatusCode.OK)
            {
                // Registration succeeded — parse printer info
                var printerInfo = JsonSerializer.Deserialize<JsonElement>(statusBody);
                var printerId = printerInfo.GetProperty("cloud_device_id").GetString()!;

                var certPem = string.Empty;
                if (printerInfo.TryGetProperty("certificate", out var certProp))
                {
                    certPem = certProp.GetString() ?? string.Empty;
                }

                var deviceTokenUrl = string.Empty;
                if (printerInfo.TryGetProperty("device_token_url", out var tokenUrlProp))
                {
                    deviceTokenUrl = tokenUrlProp.GetString() ?? string.Empty;
                }

                var printerClientId = string.Empty;
                if (printerInfo.TryGetProperty("printer_client_id", out var clientIdProp))
                {
                    printerClientId = clientIdProp.GetString() ?? string.Empty;
                }

                var printerRedirectUri = string.Empty;
                if (printerInfo.TryGetProperty("printer_redirect_uri", out var redirectProp))
                {
                    printerRedirectUri = redirectProp.GetString() ?? string.Empty;
                }

                var PrintServiceResourceId = string.Empty;
                if (printerInfo.TryGetProperty("mcp_svc_resource_id", out var resourceProp))
                {
                    PrintServiceResourceId = resourceProp.GetString() ?? string.Empty;
                }

                return new PrinterRegistrationResult(
                    printerId, certPem, deviceTokenUrl,
                    printerClientId, printerRedirectUri, PrintServiceResourceId);
            }
            else if (statusResp.StatusCode == HttpStatusCode.Accepted)
            {
                // Still processing — wait for the interval specified in the response
                var statusDoc = JsonSerializer.Deserialize<JsonElement>(statusBody);
                int interval = 3;
                if (statusDoc.TryGetProperty("interval", out var intervalProp))
                {
                    interval = intervalProp.GetInt32();
                }

                ConsoleHelper.WriteInfo($"Registration in progress, retrying in {interval}s...");
                await Task.Delay(interval * 1000);
            }
            else
            {
                throw new HttpRequestException($"Registration polling failed: {statusResp.StatusCode} - {statusBody}");
            }
        }

        throw new TimeoutException("Printer registration timed out after 5 minutes.");
    }
}

/// <summary>
/// Contains all fields returned from printer registration needed for device token acquisition.
/// </summary>
public record PrinterRegistrationResult(
    string PrinterId,
    string CertificatePem,
    string DeviceTokenUrl,
    string PrinterClientId,
    string PrinterRedirectUri,
    string PrintServiceResourceId);
