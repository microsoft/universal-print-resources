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

    private static PrinterIppClient CreateClient(
        bool useV1BadgeApi,
        HttpMessageHandler handler) =>
        new(
            "https://print.example",
            "/printers",
            "/api/v1.0/badges",
            "/api/v2.0/badges/lookup",
            useV1BadgeApi,
            httpMessageHandler: handler);
}
