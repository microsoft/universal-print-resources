// <copyright file="PrinterIppClient.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

using System.Diagnostics;
using System.Net.Http.Headers;
using BadgeReleaseDemo.Helpers;

namespace BadgeReleaseDemo.IppOperations;

/// <summary>
/// Performs IPP INFRA operations as a printer: Get-Jobs, Fetch-Job,
/// Acknowledge-Job, Fetch-Document, and Update-Job-Status.
/// Uses the minimal custom IPP implementation for a focused, auditable approach.
/// </summary>
public class PrinterIppClient
{
    private const int JOB_STATE_COMPLETED = 9;

    private readonly string ippServiceBaseUrl;
    private readonly string ippServicePrinterPath;
    private readonly string badgesApiPath;
    private readonly HttpClient httpClient;

    public PrinterIppClient(string ippServiceBaseUrl, string ippServicePrinterPath, string badgesApiPath)
    {
        this.ippServiceBaseUrl = ippServiceBaseUrl.TrimEnd('/');
        this.ippServicePrinterPath = ippServicePrinterPath;
        this.badgesApiPath = badgesApiPath;
        httpClient = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
    }

    /// <summary>
    /// Calls the IPPService BadgesController to resolve a badge ID to a user.
    /// GET /api/v1.0/badges/{badgeId}
    /// Returns (badgeId, userUri, userId) or null if not found.
    /// </summary>
    public async Task<(string BadgeId, string UserUri, string? UserId)?> ResolveBadgeAsync(
        string printerToken, string badgeId)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get,
            $"{ippServiceBaseUrl}{badgesApiPath}/{badgeId}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", printerToken);

        var response = await httpClient.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();

        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Badge resolution failed: {response.StatusCode} - {body}");
        }

        var doc = System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>(body);
        var resolvedBadgeId = doc.GetProperty("badgeId").GetString()!;
        var userUri = doc.GetProperty("userURI").GetString()!;
        string? userId = doc.TryGetProperty("userId", out var uidProp) ? uidProp.GetString() : null;

        return (resolvedBadgeId, userUri, userId);
    }

    /// <summary>
    /// Sends Get-Jobs IPP request as the printer to find fetchable jobs for a user.
    /// Returns list of (jobId, jobUri) tuples.
    /// </summary>
    public async Task<List<(int JobId, string JobUri)>> GetJobsAsync(
        string printerToken, string printerId, string requestingUserUri)
    {
        var ippHost = new Uri(ippServiceBaseUrl).Host;
        var printerUri = $"ipps://{ippHost}/printers/{printerId}";

        var ippRequest = MinimalIpp.BuildGetJobsRequest(
            requestId: 1,
            printerUri: printerUri,
            jobType: "fetchable",
            requestingUserUri: requestingUserUri,
            outputDeviceUuid: printerId);

        var responseData = await SendIppRequestAsync(printerToken, ippRequest);
        
        var (statusCode, jobAttributes) = MinimalIpp.ParseGetJobsResponse(responseData);

        if (statusCode != 0x0000) // 0x0000 = successful-ok
        {
            ConsoleHelper.WriteWarning($"Get-Jobs returned status: {statusCode:X4}");
            return new List<(int, string)>();
        }

        var jobs = new List<(int JobId, string JobUri)>();

        foreach (var jobAttrs in jobAttributes)
        {
            int jobId = 0;
            string jobUri = string.Empty;

            if (jobAttrs.TryGetValue("job-id", out var jobIdObj) && jobIdObj is int id)
            {
                jobId = id;
            }

            if (jobAttrs.TryGetValue("job-uri", out var jobUriObj) && jobUriObj is string uri)
            {
                jobUri = uri;
            }

            if (jobId > 0)
            {
                jobs.Add((jobId, jobUri));
            }
        }

        return jobs;
    }

    /// <summary>
    /// Sends Fetch-Job IPP request to get job metadata.
    /// </summary>
    public async Task<(ushort StatusCode, Dictionary<string, object> JobAttributes, byte[]? DocumentData)> FetchJobAsync(
        string printerToken, string printerId, int jobId, string requestingUserUri)
    {
        var ippHost = new Uri(ippServiceBaseUrl).Host;
        var printerUri = $"ipps://{ippHost}/printers/{printerId}";

        var ippRequest = MinimalIpp.BuildFetchJobRequest(
            requestId: 2,
            printerUri: printerUri,
            jobId: jobId,
            outputDeviceUuid: printerId,
            requestingUserUri: requestingUserUri);

        var responseData = await SendIppRequestAsync(printerToken, ippRequest);
        return MinimalIpp.ParseFetchJobResponse(responseData);
    }

    /// <summary>
    /// Sends Acknowledge-Job IPP request to confirm receipt of the job.
    /// </summary>
    public async Task<ushort> AcknowledgeJobAsync(
        string printerToken, string printerId, int jobId, string requestingUserUri)
    {
        var ippHost = new Uri(ippServiceBaseUrl).Host;
        var printerUri = $"ipps://{ippHost}/printers/{printerId}";

        var ippRequest = MinimalIpp.BuildAcknowledgeJobRequest(
            requestId: 3,
            printerUri: printerUri,
            jobId: jobId,
            statusMessage: "Badge release demo - job acknowledged",
            outputDeviceUuid: printerId,
            requestingUserUri: requestingUserUri);

        var responseData = await SendIppRequestAsync(printerToken, ippRequest);
        return MinimalIpp.ParseStatusCodeResponse(responseData);
    }

    /// <summary>
    /// Sends Fetch-Document IPP request to download the print document.
    /// Returns the document payload bytes.
    /// </summary>
    public async Task<byte[]?> FetchDocumentAsync(
        string printerToken, string printerId, int jobId, string requestingUserUri, string jobUri = "")
    {
        var ippHost = new Uri(ippServiceBaseUrl).Host;
        var printerUri = $"ipps://{ippHost}/printers/{printerId}";
        var ippRequest = MinimalIpp.BuildFetchDocumentRequest(
            requestId: 4,
            printerUri: printerUri,
            jobId: jobId,
            documentNumber: 1,
            outputDeviceUuid: printerId,
            requestingUserUri: requestingUserUri,
            jobUri: jobUri);

        var responseData = await SendIppRequestAsync(printerToken, ippRequest);
        var (statusCode, _, documentData) = MinimalIpp.ParseFetchJobResponse(responseData);

        if (statusCode != 0x0000)
        {
            ConsoleHelper.WriteError($"Fetch-Document failed: {statusCode:X4}");
            return null;
        }

        if (documentData == null)
        {
            ConsoleHelper.WriteError("Fetch-Document response contained no document data.");
            return null;
        }
        
        return documentData;
    }

    /// <summary>
    /// Sends Update-Job-Status to mark the job as completed.
    /// </summary>
    public async Task<ushort> UpdateJobStatusAsync(
        string printerToken, string printerId, int jobId, string requestingUserUri)
    {
        var ippHost = new Uri(ippServiceBaseUrl).Host;
        var printerUri = $"ipps://{ippHost}/printers/{printerId}";

        var ippRequest = MinimalIpp.BuildUpdateJobStatusRequest(
            requestId: 5,
            printerUri: printerUri,
            jobId: jobId,
            jobState: JOB_STATE_COMPLETED,
            outputDeviceUuid: printerId,
            requestingUserUri: requestingUserUri);

        var responseData = await SendIppRequestAsync(printerToken, ippRequest);
        return MinimalIpp.ParseStatusCodeResponse(responseData);
    }

    /// <summary>
    /// Saves document bytes to a local file and opens it with the default viewer.
    /// Returns the saved file path for cleanup.
    /// </summary>
    public static string SaveAndOpenDocument(byte[] documentData, string fileName = "PrintedDocument.pdf")
    {
        var outputPath = Path.Combine(Environment.CurrentDirectory, fileName);
        File.WriteAllBytes(outputPath, documentData);
        ConsoleHelper.WriteInfo($"Document saved to: {outputPath}");

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = outputPath,
                UseShellExecute = true
            });
            ConsoleHelper.WriteInfo("Opening document with default viewer...");
        }
        catch (Exception ex)
        {
            ConsoleHelper.WriteWarning($"Could not open document automatically: {ex.Message}");
            ConsoleHelper.WriteInfo($"Please open manually: {outputPath}");
        }

        return outputPath;
    }

    /// <summary>
    /// Sends a minimal IPP request over HTTP, returns the raw response bytes.
    /// </summary>
    private async Task<byte[]> SendIppRequestAsync(string accessToken, byte[] ippRequest)
    {
        var printerEndpoint = $"{ippServiceBaseUrl}{ippServicePrinterPath}";

        using var request = new HttpRequestMessage(HttpMethod.Post, printerEndpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Headers.Add("User-Agent", "BadgeReleaseDemo/1.0");
        request.Content = new ByteArrayContent(ippRequest);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/ipp");

        var response = await httpClient.SendAsync(request);

        if (!response.IsSuccessStatusCode)
        {
            var errorBody = await response.Content.ReadAsStringAsync();
            ConsoleHelper.WriteError($"IPP HTTP {(int)response.StatusCode}: {errorBody}");

            if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized)
            {
                throw new UnauthorizedAccessException($"Printer token expired or invalid: {errorBody}");
            }

            throw new HttpRequestException(
                $"IPP request failed: {(int)response.StatusCode} {response.StatusCode} - {errorBody}");
        }

        return await response.Content.ReadAsByteArrayAsync();
    }
}
