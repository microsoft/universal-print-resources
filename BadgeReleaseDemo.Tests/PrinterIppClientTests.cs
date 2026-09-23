using System.Net;
using System.Text.Json;
using BadgeReleaseDemo.IppOperations;

namespace BadgeReleaseDemo.Tests;

public class PrinterIppClientTests
{
    [Fact]
    public async Task ResolveBadgeAsync_UsesV2PostWithOnlyBadgeIdByDefault()
    {
        var handler = new RecordingHttpMessageHandler((_, _) =>
            RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.OK,
                """{"badgeId":"badge/42","userURI":"mailto:user@contoso.com"}"""));
        using var client = CreateClient(useV1BadgeApi: false, handler);

        var result = await client.ResolveBadgeAsync("printer-token", "badge/42");

        Assert.NotNull(result);
        var request = Assert.Single(handler.Requests);
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("https://print.example/api/v2.0/badges/lookup", request.Uri);
        Assert.Equal("application/json", request.ContentType);

        using var body = JsonDocument.Parse(request.Body!);
        var property = Assert.Single(body.RootElement.EnumerateObject());
        Assert.Equal("badgeId", property.Name);
        Assert.Equal("badge/42", property.Value.GetString());
    }

    [Fact]
    public async Task ResolveBadgeAsync_UsesEscapedV1GetWhenRequested()
    {
        var handler = new RecordingHttpMessageHandler((_, _) =>
            RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.OK,
                """{"badgeId":"badge/42","userURI":"mailto:user@contoso.com"}"""));
        using var client = CreateClient(useV1BadgeApi: true, handler);

        await client.ResolveBadgeAsync("printer-token", "badge/42");

        var request = Assert.Single(handler.Requests);
        Assert.Equal(HttpMethod.Get, request.Method);
        Assert.Equal("https://print.example/api/v1.0/badges/badge%2F42", request.Uri);
        Assert.Null(request.Body);
    }

    [Fact]
    public async Task ResolveBadgeAsync_RefreshesExpiredPrinterTokenOnce()
    {
        var handler = new RecordingHttpMessageHandler((_, requestIndex) =>
            requestIndex == 0
                ? RecordingHttpMessageHandler.JsonResponse(
                    HttpStatusCode.Unauthorized,
                    """{"error":"expired token"}""")
                : RecordingHttpMessageHandler.JsonResponse(
                    HttpStatusCode.OK,
                    """{"badgeId":"badge-1","userURI":"mailto:user@contoso.com"}"""));
        var refreshCount = 0;
        using var client = CreateClient(
            useV1BadgeApi: false,
            handler,
            () =>
            {
                refreshCount++;
                return Task.FromResult("refreshed-token");
            });

        var result = await client.ResolveBadgeAsync("expired-token", "badge-1");

        Assert.NotNull(result);
        Assert.Equal(1, refreshCount);
        Assert.Collection(
            handler.Requests,
            request => Assert.Equal("expired-token", request.BearerToken),
            request => Assert.Equal("refreshed-token", request.BearerToken));
    }

    [Fact]
    public async Task GetJobsAsync_PreservesUnsuccessfulIppStatus()
    {
        var handler = new RecordingHttpMessageHandler((_, _) =>
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent(
                [
                    0x02, 0x00,             // IPP 2.0
                    0x05, 0x00,             // server-error-internal-error
                    0x00, 0x00, 0x00, 0x01, // request-id
                    0x03                    // end-of-attributes
                ])
            });
        using var client = CreateClient(useV1BadgeApi: false, handler);

        var result = await client.GetJobsAsync(
            "printer-token",
            "printer-1",
            string.Empty);

        Assert.Equal(0x0500, result.StatusCode);
        Assert.Empty(result.Jobs);
    }

    private static PrinterIppClient CreateClient(
        bool useV1BadgeApi,
        HttpMessageHandler handler,
        Func<Task<string>>? refreshPrinterToken = null) =>
        new(
            "https://print.example",
            "/printers",
            "/api/v1.0/badges",
            "/api/v2.0/badges/lookup",
            useV1BadgeApi,
            refreshPrinterToken,
            httpMessageHandler: handler);
}
