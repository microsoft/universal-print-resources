// <copyright file="PrintJobSubmission.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using BadgeReleaseDemo.Helpers;

namespace BadgeReleaseDemo.GraphApi;

/// <summary>
/// Handles print job creation, document upload, and job start via MS Graph API.
/// </summary>
public class PrintJobSubmission
{
    private readonly string graphBaseUrl;
    private readonly HttpClient httpClient;

    public PrintJobSubmission(string graphBaseUrl)
    {
        this.graphBaseUrl = graphBaseUrl;
        httpClient = new HttpClient();
    }

    /// <summary>
    /// Creates a print job on a printer share.
    /// Matches the functional test pattern: configuration only, no documents in initial creation.
    /// Returns (jobId, documentId).
    /// </summary>
    public async Task<(string JobId, string DocumentId)> CreateJobAsync(
        string accessToken, string shareId, string displayName)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post,
            $"{graphBaseUrl}/print/shares/{shareId}/jobs");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        // Match functional test pattern: configuration with copies + dpi, no documents
        var requestBody = new Dictionary<string, object>
        {
            ["configuration"] = new Dictionary<string, object>
            {
                ["copies"] = 1,
                ["dpi"] = 600,
            },
        };

        var json = JsonSerializer.Serialize(requestBody, new JsonSerializerOptions
        {
            DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
        });
        request.Content = new StringContent(json, Encoding.UTF8, "application/json");

        ConsoleHelper.WriteInfo($"POST {graphBaseUrl}/print/shares/{shareId}/jobs");
        ConsoleHelper.WriteInfo($"Body: {json}");

        var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Failed to create print job: {response.StatusCode} - {responseBody}");
        }

        var jobDoc = JsonSerializer.Deserialize<JsonElement>(responseBody);
        var jobId = jobDoc.GetProperty("id").GetString()!;

        // Extract document ID from the first document in the response
        var documents = jobDoc.GetProperty("documents");
        var documentId = documents[0].GetProperty("id").GetString()!;

        return (jobId, documentId);
    }

    /// <summary>
    /// Creates an upload session for a document.
    /// Returns the upload URL.
    /// </summary>
    public async Task<string> CreateUploadSessionAsync(
        string accessToken, string shareId, string jobId, string documentId, long documentSize)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post,
            $"{graphBaseUrl}/print/shares/{shareId}/jobs/{jobId}/documents/{documentId}/createUploadSession");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        var requestBody = new Dictionary<string, object>
        {
            ["properties"] = new Dictionary<string, object>
            {
                ["documentName"] = "SampleDocument.pdf",
                ["contentType"] = "application/pdf",
                ["size"] = documentSize,
            },
        };

        var json = JsonSerializer.Serialize(requestBody);
        request.Content = new StringContent(json, Encoding.UTF8, "application/json");

        var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Failed to create upload session: {response.StatusCode} - {responseBody}");
        }

        var sessionDoc = JsonSerializer.Deserialize<JsonElement>(responseBody);
        return sessionDoc.GetProperty("uploadUrl").GetString()
            ?? throw new InvalidOperationException("No uploadUrl in response.");
    }

    /// <summary>
    /// Uploads a PDF document to the upload session.
    /// </summary>
    public async Task UploadDocumentAsync(string accessToken, string uploadUrl, byte[] pdfData)
    {
        using var request = new HttpRequestMessage(HttpMethod.Put, uploadUrl);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        request.Content = new ByteArrayContent(pdfData);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/pdf");
        request.Content.Headers.ContentLength = pdfData.Length;
        request.Content.Headers.Add("Content-Range", $"bytes 0-{pdfData.Length - 1}/{pdfData.Length}");

        var response = await httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Failed to upload document: {response.StatusCode} - {responseBody}");
        }

        ConsoleHelper.WriteInfo($"Uploaded {pdfData.Length} bytes.");
    }

    /// <summary>
    /// Starts the print job after document upload.
    /// </summary>
    public async Task StartJobAsync(string accessToken, string shareId, string jobId)
    {
        httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        var content = new StringContent("{}", Encoding.UTF8, "application/json");

        var response = await httpClient.PostAsync(
            $"{graphBaseUrl}/print/shares/{shareId}/jobs/{jobId}/start", content);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Failed to start print job: {response.StatusCode} - {responseBody}");
        }

        ConsoleHelper.WriteInfo("Print job started.");
    }
}
