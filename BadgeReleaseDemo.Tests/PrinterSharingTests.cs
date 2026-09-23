using System.Net;
using System.Text.Json;
using BadgeReleaseDemo.GraphApi;

namespace BadgeReleaseDemo.Tests;

public class PrinterSharingTests
{
    [Fact]
    public async Task CreateShareAsync_UsesPortalCompatibleSecureReleaseFlow()
    {
        var handler = new RecordingHttpMessageHandler((_, call) => call switch
        {
            0 => RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.Created,
                """{"id":"share/1"}"""),
            1 => new HttpResponseMessage(HttpStatusCode.NoContent),
            2 => RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.OK,
                """{"id":"share/1","holdJobsForSecureRelease":true}"""),
            _ => throw new InvalidOperationException("Unexpected request.")
        });
        using var client = new PrinterSharing("https://graph.example/v1.0", handler);

        var shareId = await client.CreateShareAsync("access-token", "printer-1", "Demo printer");

        Assert.Equal("share/1", shareId);
        Assert.Collection(
            handler.Requests,
            create =>
            {
                Assert.Equal(HttpMethod.Post, create.Method);
                Assert.Equal("https://graph.example/v1.0/print/shares", create.Uri);
                using var body = JsonDocument.Parse(create.Body!);
                Assert.False(body.RootElement.TryGetProperty("holdJobsForSecureRelease", out _));
            },
            enable =>
            {
                Assert.Equal(HttpMethod.Patch, enable.Method);
                Assert.Equal("https://graph.example/beta/print/shares/share%2F1", enable.Uri);
                Assert.Equal(
                    JsonValueKind.True,
                    JsonDocument.Parse(enable.Body!).RootElement
                        .GetProperty("holdJobsForSecureRelease").ValueKind);
            },
            validate =>
            {
                Assert.Equal(HttpMethod.Get, validate.Method);
                Assert.Equal("https://graph.example/beta/print/shares/share%2F1", validate.Uri);
            });
    }

    [Theory]
    [InlineData(HttpStatusCode.BadRequest, true)]
    [InlineData(HttpStatusCode.NoContent, false)]
    public async Task CreateShareAsync_DeletesShareWhenEnablementIsNotConfirmed(
        HttpStatusCode patchStatus,
        bool patchFails)
    {
        var handler = new RecordingHttpMessageHandler((_, call) => call switch
        {
            0 => RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.Created,
                """{"id":"share/1"}"""),
            1 => new HttpResponseMessage(patchStatus)
            {
                Content = new StringContent(patchFails ? "invalid patch" : string.Empty)
            },
            2 when !patchFails => RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.OK,
                """{"id":"share/1","holdJobsForSecureRelease":false}"""),
            2 when patchFails => new HttpResponseMessage(HttpStatusCode.NoContent),
            3 => new HttpResponseMessage(HttpStatusCode.NoContent),
            _ => throw new InvalidOperationException("Unexpected request.")
        });
        using var client = new PrinterSharing("https://graph.example/v1.0", handler);

        await Assert.ThrowsAnyAsync<Exception>(() =>
            client.CreateShareAsync("access-token", "printer-1", "Demo printer"));

        var delete = handler.Requests[^1];
        Assert.Equal(HttpMethod.Delete, delete.Method);
        Assert.Equal("https://graph.example/v1.0/print/shares/share%2F1", delete.Uri);
    }

    [Fact]
    public async Task CreateShareAsync_PreservesSetupFailureWhenRollbackThrows()
    {
        var handler = new RecordingHttpMessageHandler((_, call) => call switch
        {
            0 => RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.Created,
                """{"id":"share-1"}"""),
            1 => new HttpResponseMessage(HttpStatusCode.BadRequest)
            {
                Content = new StringContent("invalid patch")
            },
            2 => throw new HttpRequestException("rollback transport failure"),
            _ => throw new InvalidOperationException("Unexpected request.")
        });
        using var client = new PrinterSharing("https://graph.example/v1.0", handler);

        var exception = await Assert.ThrowsAsync<HttpRequestException>(() =>
            client.CreateShareAsync("access-token", "printer-1", "Demo printer"));

        Assert.Contains("Failed to enable secure release", exception.Message);
        Assert.DoesNotContain("rollback transport failure", exception.Message);
        Assert.Equal(HttpMethod.Delete, handler.Requests[^1].Method);
    }
}
