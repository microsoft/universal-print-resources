// <copyright file="PrinterIppClient.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

using System.Diagnostics;
using System.Net.Http.Headers;
using BadgeReleaseDemo.Helpers;
using BadgeReleaseDemo.IppLibrary;
using BadgeReleaseDemo.IppLibrary.Common;

namespace BadgeReleaseDemo.IppOperations;

/// <summary>
/// Performs IPP INFRA operations as a printer: Get-Jobs, Fetch-Job,
/// Acknowledge-Job, Fetch-Document, and Update-Job-Status.
/// Uses the IppLibrary for IPP request building and serialization.
/// </summary>
public class PrinterIppClient
{
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
        var factory = IppFactoryHelper.CreateIppRequestFactory(
            ippHost, printerId, string.Empty, requestingUserUri);

        var requestedAttributes = new List<IppAttribute>
        {
            new IppAttribute(RequestedAttributes.All)
        };

        var ippRequest = await factory.CreateGetJobsRequestAsync(
            requestId: 1,
            jobType: "fetchable",
            requestingUserName: string.Empty,
            requestingUserUri: requestingUserUri,
            printerUri: $"ipps://{ippHost}/printers/{printerId}",
            outputDeviceUuid: printerId,
            requestedAttributes: requestedAttributes);

        var ippResponse = await SendIppRequestAsync(printerToken, ippRequest);

        if (ippResponse.StatusCode != StatusCode.SuccessfulOk)
        {
            ConsoleHelper.WriteWarning($"Get-Jobs returned status: {ippResponse.StatusCode}");
            return new List<(int, string)>();
        }

        var jobs = new List<(int JobId, string JobUri)>();
        var jobGroups = ippResponse.LookupAttributeGroup(Tag.JobAttributes);

        foreach (var group in jobGroups)
        {
            int jobId = 0;
            string jobUri = string.Empty;

            if (group.Attributes.TryGetValue(JobAttributes.JobId, out var jobIdAttr))
            {
                jobId = jobIdAttr.FirstValue.GetNativeValue<int>();
            }

            if (group.Attributes.TryGetValue(JobAttributes.JobUri, out var jobUriAttr))
            {
                jobUri = jobUriAttr.FirstValue.GetNativeValue<string>() ?? string.Empty;
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
    public async Task<IppResponse> FetchJobAsync(
        string printerToken, string printerId, int jobId, string requestingUserUri)
    {
        var ippHost = new Uri(ippServiceBaseUrl).Host;
        var factory = IppFactoryHelper.CreateIppRequestFactory(
            ippHost, printerId, string.Empty, requestingUserUri);

        var ippRequest = await factory.CreateFetchJobRequestAsync(
            requestId: 2,
            outputDeviceUuid: printerId,
            jobId: jobId);

        return await SendIppRequestAsync(printerToken, ippRequest);
    }

    /// <summary>
    /// Sends Acknowledge-Job IPP request to confirm receipt of the job.
    /// </summary>
    public async Task<StatusCode> AcknowledgeJobAsync(
        string printerToken, string printerId, int jobId, string requestingUserUri)
    {
        var ippHost = new Uri(ippServiceBaseUrl).Host;
        var factory = IppFactoryHelper.CreateIppRequestFactory(
            ippHost, printerId, string.Empty, requestingUserUri);

        var ippRequest = await factory.CreateAcknowledgeJobRequestAsync(
            requestId: 3,
            outputDeviceUuid: printerId,
            jobId: jobId,
            fetchStatusCode: StatusCode.Undefined,
            fetchStatusMessage: "Badge release demo - job acknowledged");

        var response = await SendIppRequestAsync(printerToken, ippRequest);
        return response.StatusCode;
    }

    /// <summary>
    /// Sends Fetch-Document IPP request to download the print document.
    /// Returns the document payload bytes.
    /// </summary>
    public async Task<byte[]?> FetchDocumentAsync(
        string printerToken, string printerId, int jobId, string requestingUserUri)
    {
        var ippHost = new Uri(ippServiceBaseUrl).Host;
        var factory = IppFactoryHelper.CreateIppRequestFactory(
            ippHost, printerId, string.Empty, requestingUserUri);

        var ippRequest = await factory.CreateFetchDocumentRequestAsync(
            requestId: 4,
            outputDeviceUuid: printerId,
            jobId: jobId,
            documentNumber: 1);

        var response = await SendIppRequestAsync(printerToken, ippRequest);

        if (response.StatusCode != StatusCode.SuccessfulOk)
        {
            ConsoleHelper.WriteError($"Fetch-Document failed: {response.StatusCode}");
            return null;
        }

        if (response.Data == null)
        {
            ConsoleHelper.WriteError("Fetch-Document response contained no document data.");
            return null;
        }

        using var ms = new MemoryStream();
        response.Data.Seek(0, SeekOrigin.Begin);
        await response.Data.CopyToAsync(ms);
        return ms.ToArray();
    }

    /// <summary>
    /// Sends Update-Job-Status to mark the job as completed.
    /// </summary>
    public async Task<StatusCode> UpdateJobStatusAsync(
        string printerToken, string printerId, int jobId)
    {
        var ippHost = new Uri(ippServiceBaseUrl).Host;
        var factory = IppFactoryHelper.CreateIppRequestFactory(
            ippHost, printerId, string.Empty, string.Empty);

        var jobAttributeGroup = new IppAttributeGroup(Tag.JobAttributes);
        jobAttributeGroup.AddAttribute(
            new IppAttribute(JobAttributes.OutputDeviceJobState,
                IppValue.CreateEnumValue((int)JobState.Completed)));
        jobAttributeGroup.AddAttribute(
            new IppAttribute(JobAttributes.JobId,
                IppValue.CreateIntegerValue(jobId)));

        var ippRequest = await factory.CreateUpdateJobStatusRequestAsync(
            requestId: 5,
            outputDeviceUuid: printerId,
            optionalJobAttributes: jobAttributeGroup);

        var response = await SendIppRequestAsync(printerToken, ippRequest);
        return response.StatusCode;
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
    /// Serializes and sends an IPP request over HTTP, returns the parsed IPP response.
    /// </summary>
    private async Task<IppResponse> SendIppRequestAsync(string accessToken, IppRequest ippRequest)
    {
        var printerEndpoint = $"{ippServiceBaseUrl}{ippServicePrinterPath}";

        var serializedData = ippRequest.Serialize();
        serializedData.Seek(0, SeekOrigin.Begin);
        var dataBuffer = new byte[serializedData.Length];
        await serializedData.ReadAsync(dataBuffer, 0, (int)serializedData.Length);

        using var request = new HttpRequestMessage(HttpMethod.Post, printerEndpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Headers.Add("User-Agent", "BadgeReleaseDemo/1.0");
        request.Content = new ByteArrayContent(dataBuffer);
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

        // Copy to MemoryStream so it's seekable (required for IppResponse.CreateAsync to populate Data)
        var networkStream = await response.Content.ReadAsStreamAsync();
        var stream = new MemoryStream();
        await networkStream.CopyToAsync(stream);
        stream.Seek(0, SeekOrigin.Begin);
        var cts = new CancellationTokenSource();
        var ippResponse = await IppResponse.CreateAsync(stream, true, cts.Token);

        if (ippResponse.StatusCode != StatusCode.SuccessfulOk)
        {
            ConsoleHelper.WriteWarning($"IPP response status: {ippResponse.StatusCode}");
            LogResponseHeaders(response);
        }

        return ippResponse;
    }

    private static void LogResponseHeaders(HttpResponseMessage response)
    {
        foreach (var header in response.Headers)
        {
            ConsoleHelper.WriteKeyValue(header.Key, string.Join(", ", header.Value));
        }
    }
}
