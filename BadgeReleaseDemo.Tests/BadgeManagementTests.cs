using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using BadgeReleaseDemo.GraphApi;

namespace BadgeReleaseDemo.Tests;

public class BadgeManagementTests
{
    [Fact]
    public async Task CreateBadgeCollectionAsync_AcceptsCaseInsensitiveSucceededState()
    {
        var handler = new RecordingHttpMessageHandler((_, call) => call switch
        {
            0 => RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.Accepted,
                """{"id":"operation-1","collectionId":"collection-1"}"""),
            1 => RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.OK,
                """{"status":{"state":"SuCcEeDeD"}}"""),
            _ => throw new InvalidOperationException("Unexpected request.")
        });
        using var client = new BadgeManagement("https://graph.example/v1.0", handler);

        var result = await client.CreateBadgeCollectionAsync("access-token");

        Assert.Equal("collection-1", result.Id);
        Assert.True(result.Created);
        Assert.Equal(2, handler.Requests.Count);
        Assert.Equal(
            "https://graph.example/v1.0/print/operations/operation-1",
            handler.Requests[1].Uri);
    }

    [Fact]
    public async Task CreateBadgeCollectionAsync_ReportsExistingCollection()
    {
        var handler = new RecordingHttpMessageHandler((_, call) => call switch
        {
            0 => new HttpResponseMessage(HttpStatusCode.Conflict),
            1 => RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.OK,
                """{"value":[{"id":"existing-collection"}]}"""),
            _ => throw new InvalidOperationException("Unexpected request.")
        });
        using var client = new BadgeManagement("https://graph.example/v1.0", handler);

        var result = await client.CreateBadgeCollectionAsync("access-token");

        Assert.Equal("existing-collection", result.Id);
        Assert.False(result.Created);
    }

    [Fact]
    public async Task UpdateBadgeAsync_RejectsMissingUpnBeforeSendingRequest()
    {
        var handler = new RecordingHttpMessageHandler((_, _) =>
            throw new InvalidOperationException("No request should be sent."));
        using var client = new BadgeManagement("https://graph.example/v1.0", handler);

        var exception = await Assert.ThrowsAsync<ArgumentException>(() =>
            client.UpdateBadgeAsync(
                "access-token",
                "collection-1",
                "badge-1",
                null!,
                "user-1"));

        Assert.Equal("upn", exception.ParamName);
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task UpdateBadgeAsync_SendsUpnAndOptionalUserId()
    {
        var handler = new RecordingHttpMessageHandler((_, _) =>
            RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.OK,
                """{"id":"badge-1","upn":"user@contoso.com","userId":"user-1"}"""));
        using var client = new BadgeManagement("https://graph.example/v1.0", handler);

        await client.UpdateBadgeAsync(
            "access-token",
            "collection-1",
            "badge-1",
            "user@contoso.com",
            "user-1");

        var request = Assert.Single(handler.Requests);
        Assert.Equal(HttpMethod.Patch, request.Method);
        using var body = JsonDocument.Parse(request.Body!);
        Assert.Equal("user@contoso.com", body.RootElement.GetProperty("upn").GetString());
        Assert.Equal("user-1", body.RootElement.GetProperty("userId").GetString());
    }

    [Fact]
    public void GetRetryDelay_ClampsDeltaToRemainingTimeout()
    {
        var delay = BadgeManagement.GetRetryDelay(
            new RetryConditionHeaderValue(TimeSpan.FromMinutes(20)),
            TimeSpan.FromSeconds(5),
            TimeSpan.FromSeconds(2),
            DateTimeOffset.UtcNow);

        Assert.Equal(TimeSpan.FromSeconds(2), delay);
    }

    [Fact]
    public void GetRetryDelay_HandlesHttpDate()
    {
        var now = new DateTimeOffset(2026, 9, 22, 22, 0, 0, TimeSpan.Zero);

        var delay = BadgeManagement.GetRetryDelay(
            new RetryConditionHeaderValue(now.AddSeconds(30)),
            TimeSpan.FromSeconds(5),
            TimeSpan.FromMinutes(1),
            now);

        Assert.Equal(TimeSpan.FromSeconds(30), delay);
    }
}
