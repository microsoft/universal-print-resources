// <copyright file="PrinterIppClient.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using BadgeReleaseDemo.Helpers;

namespace BadgeReleaseDemo.IppOperations;

/// <summary>
/// Performs IPP INFRA operations as a printer: Get-Jobs, Fetch-Job,
/// Acknowledge-Job, Fetch-Document, and Update-Job-Status.
/// Uses the minimal custom IPP implementation for a focused, auditable approach.
/// </summary>
public class PrinterIppClient : IDisposable
{
    private const int JOB_STATE_COMPLETED = 9;

    private readonly string ippServiceBaseUrl;
    private readonly string ippServicePrinterPath;
    private readonly string badgesV1ApiPath;
    private readonly string badgesV2ApiPath;
    private readonly bool useV1BadgeApi;
    private readonly HttpClient httpClient;
    private readonly Func<Task<string>>? refreshPrinterToken;
    private int requestIdCounter;

    public PrinterIppClient(
        string ippServiceBaseUrl,
        string ippServicePrinterPath,
        string badgesV1ApiPath,
        string badgesV2ApiPath,
        bool useV1BadgeApi,
        Func<Task<string>>? refreshPrinterToken = null)
    {
        this.ippServiceBaseUrl = ippServiceBaseUrl.TrimEnd('/');
        this.ippServicePrinterPath = ippServicePrinterPath;
        this.badgesV1ApiPath = badgesV1ApiPath;
        this.badgesV2ApiPath = badgesV2ApiPath;
        this.useV1BadgeApi = useV1BadgeApi;
        this.refreshPrinterToken = refreshPrinterToken;
        httpClient = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
    }

    public void Dispose() => httpClient.Dispose();

    /// <summary>
    /// Returns the next IPP request-id. IPP request-ids must be non-zero and are expected to
    /// increment across operations on a connection.
    /// </summary>
    private ushort NextRequestId() => (ushort)Interlocked.Increment(ref requestIdCounter);

    /// <summary>
    /// Calls the IPPService BadgesController to resolve a badge ID to a user.
    /// Uses V2 by default, with V1 available for compatibility.
    /// Returns (badgeId, userUri, userId, userIdPresent) or null if not found.
    /// </summary>
    public async Task<(string BadgeId, string UserUri, string? UserId, bool UserIdPresent)?> ResolveBadgeAsync(
        string printerToken, string badgeId)
    {
        using var request = CreateBadgeLookupRequest(badgeId);
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

        var doc = JsonSerializer.Deserialize<JsonElement>(body);
        var resolvedBadgeId = doc.GetProperty("badgeId").GetString()!;
        var userUri = doc.GetProperty("userURI").GetString()!;
        var userIdPresent = doc.TryGetProperty("userId", out var uidProp);
        string? userId = userIdPresent && uidProp.ValueKind != JsonValueKind.Null
            ? uidProp.GetString()
            : null;

        return (resolvedBadgeId, userUri, userId, userIdPresent);
    }

    private HttpRequestMessage CreateBadgeLookupRequest(string badgeId)
    {
        if (useV1BadgeApi)
        {
            return new HttpRequestMessage(HttpMethod.Get,
                $"{ippServiceBaseUrl}{badgesV1ApiPath}/{Uri.EscapeDataString(badgeId)}");
        }

        var requestBody = JsonSerializer.Serialize(new
        {
            badgeId,
            bypassCache = false
        });

        return new HttpRequestMessage(HttpMethod.Post, $"{ippServiceBaseUrl}{badgesV2ApiPath}")
        {
            Content = new StringContent(requestBody, Encoding.UTF8, "application/json")
        };
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
            requestId: NextRequestId(),
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
            requestId: NextRequestId(),
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
            requestId: NextRequestId(),
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
            requestId: NextRequestId(),
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
            requestId: NextRequestId(),
            printerUri: printerUri,
            jobId: jobId,
            jobState: JOB_STATE_COMPLETED,
            outputDeviceUuid: printerId,
            requestingUserUri: requestingUserUri);

        var responseData = await SendIppRequestAsync(printerToken, ippRequest);
        return MinimalIpp.ParseStatusCodeResponse(responseData);
    }

    /// <summary>
    /// Saves document bytes to a unique file in the system temp folder and, after prompting,
    /// optionally opens it with the default viewer. Returns the saved file path for cleanup.
    /// </summary>
    public static string SaveAndOpenDocument(byte[] documentData, string fileNamePrefix = "PrintedDocument")
    {
        var fileName = $"{fileNamePrefix}-{DateTime.Now:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}.pdf";
        var outputPath = Path.Combine(Path.GetTempPath(), fileName);
        File.WriteAllBytes(outputPath, documentData);
        ConsoleHelper.WriteInfo($"Document saved to: {outputPath}");

        if (!ConsoleHelper.PromptYesNo("Open the downloaded document with the default viewer?"))
        {
            ConsoleHelper.WriteInfo($"Skipped opening. You can open it manually: {outputPath}");
            return outputPath;
        }

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
    /// On a 401 the printer device token is refreshed (if a refresh callback was supplied) and the
    /// request is retried once, since the flow can idle at a prompt long enough for the token to expire.
    /// </summary>
    private async Task<byte[]> SendIppRequestAsync(string accessToken, byte[] ippRequest)
    {
        var printerEndpoint = $"{ippServiceBaseUrl}{ippServicePrinterPath}";
        var token = accessToken;
        var refreshed = false;

        while (true)
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, printerEndpoint);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            request.Headers.Add("User-Agent", "BadgeReleaseDemo/1.0");
            request.Content = new ByteArrayContent(ippRequest);
            request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/ipp");

            var response = await httpClient.SendAsync(request);

            if (response.IsSuccessStatusCode)
            {
                return await response.Content.ReadAsByteArrayAsync();
            }

            var errorBody = await response.Content.ReadAsStringAsync();

            if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized)
            {
                if (!refreshed && refreshPrinterToken != null)
                {
                    ConsoleHelper.WriteWarning("Printer token expired — refreshing and retrying...");
                    token = await refreshPrinterToken();
                    refreshed = true;
                    continue;
                }

                ConsoleHelper.WriteError($"IPP HTTP 401: {errorBody}");
                throw new UnauthorizedAccessException($"Printer token expired or invalid: {errorBody}");
            }

            ConsoleHelper.WriteError($"IPP HTTP {(int)response.StatusCode}: {errorBody}");
            throw new HttpRequestException(
                $"IPP request failed: {(int)response.StatusCode} {response.StatusCode} - {errorBody}");
        }
    }
}
