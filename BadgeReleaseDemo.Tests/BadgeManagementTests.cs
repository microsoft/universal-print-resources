using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using BadgeReleaseDemo.GraphApi;

namespace BadgeReleaseDemo.Tests;

public class BadgeManagementTests
{
    [Theory]
    [InlineData(false, "badgeCollections", "upn")]
    [InlineData(true, "badgeGroups", "userPrincipalName")]
    public async Task BadgeCrud_UsesSelectedContract(bool useV3, string resource, string upnProperty)
    {
        const string userId = "826e5942-3f12-47af-bb77-ad77c33fc465";
        var badgeJson = $$"""{"id":"badge/1","{{upnProperty}}":"user@example.com","userId":"{{userId}}","physicalBadgeId":null,"createdDateTime":null,"user":null}""";
        var handler = new RecordingHttpMessageHandler((_, call) => call switch
        {
            0 => RecordingHttpMessageHandler.JsonResponse(HttpStatusCode.Created, badgeJson),
            1 or 2 => RecordingHttpMessageHandler.JsonResponse(HttpStatusCode.OK, badgeJson),
            3 => RecordingHttpMessageHandler.JsonResponse(HttpStatusCode.OK, $$"""{"value":[{{badgeJson}}]}"""),
            4 or 5 => new HttpResponseMessage(HttpStatusCode.NoContent),
            _ => throw new InvalidOperationException("Unexpected request.")
        });
        using var client = new BadgeManagement("https://graph.example/beta", handler, useV3);

        var created = await client.AddBadgeAsync("token", "group/1", "badge/1", "user@example.com", userId);
        var updated = await client.UpdateBadgeAsync("token", "group/1", "badge/1", "user@example.com", userId);
        var retrieved = await client.GetBadgeAsync("token", "group/1", "badge/1");
        var listed = await client.ListBadgesAsync("token", "group/1");
        Assert.True(await client.DeleteBadgeAsync("token", "group/1", "badge/1"));
        Assert.True(await client.DeleteBadgeGroupAsync("token", "group/1"));

        Assert.Equal(created, updated);
        Assert.Equal(created, retrieved);
        Assert.True(listed.IsSupported);
        Assert.Equal(created, Assert.Single(listed.Badges));
        Assert.Equal("badge/1", created.Id);
        Assert.Equal("user@example.com", created.Upn);
        Assert.Equal(userId, created.UserId);
        Assert.Null(created.PhysicalBadgeId);
        Assert.Null(created.CreatedDateTime);
        var resourceUrl = $"https://graph.example/beta/print/{resource}/group%2F1";
        Assert.Equal(
            [HttpMethod.Post, HttpMethod.Patch, HttpMethod.Get, HttpMethod.Get, HttpMethod.Delete, HttpMethod.Delete],
            handler.Requests.Select(request => request.Method));
        Assert.Equal(
            [$"{resourceUrl}/badges", $"{resourceUrl}/badges/badge%2F1", $"{resourceUrl}/badges/badge%2F1",
             $"{resourceUrl}/badges", $"{resourceUrl}/badges/badge%2F1", resourceUrl],
            handler.Requests.Select(request => request.Uri));
        Assert.All(handler.Requests, request => Assert.Equal("token", request.BearerToken));
        foreach (var request in handler.Requests.Take(2))
        {
            using var body = JsonDocument.Parse(request.Body!);
            Assert.Equal("user@example.com", body.RootElement.GetProperty(upnProperty).GetString());
            Assert.Equal(userId, body.RootElement.GetProperty("userId").GetString());
            Assert.False(body.RootElement.TryGetProperty(useV3 ? "upn" : "userPrincipalName", out _));
            Assert.False(body.RootElement.TryGetProperty("physicalBadgeId", out _));
            Assert.False(body.RootElement.TryGetProperty("createdDateTime", out _));
            Assert.False(body.RootElement.TryGetProperty("user", out _));
        }
    }

    [Fact]
    public async Task V3Creation_UsesGroupNavigationAndOpaqueOperationToken()
    {
        var handler = new RecordingHttpMessageHandler((_, call) => call switch
        {
            0 => RecordingHttpMessageHandler.JsonResponse(HttpStatusCode.Accepted,
                """{"@odata.type":"#microsoft.graph.printBadgeGroupCreateOperation","id":"opaque+/=%token","printBadgeGroup":{"id":"group-1"},"collectionId":"wrong-legacy-id"}"""),
            1 => RecordingHttpMessageHandler.JsonResponse(HttpStatusCode.OK,
                """{"status":{"state":"succeeded"}}"""),
            _ => throw new InvalidOperationException("Unexpected request.")
        });
        using var client = new BadgeManagement("https://graph.example/beta", handler, useV3GraphBadgeApi: true);

        var result = await client.CreateBadgeGroupAsync("token");

        Assert.True(result.Created);
        Assert.Equal("group-1", result.Id);
        Assert.Equal("https://graph.example/beta/print/badgeGroups", handler.Requests[0].Uri);
        Assert.Equal("{}", handler.Requests[0].Body);
        Assert.Equal("https://graph.example/beta/print/operations/opaque%2B%2F%3D%25token", handler.Requests[1].Uri);
    }

    [Fact]
    public async Task V3Creation_RejectsMissingGroupIdentityRatherThanUsingLegacyIdOrListing()
    {
        var handler = new RecordingHttpMessageHandler((_, _) =>
            RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.Accepted,
                """{"id":"operation-1","collectionId":"legacy-id","printBadgeGroup":null}"""));
        using var client = new BadgeManagement("https://graph.example/beta", handler, useV3GraphBadgeApi: true);

        var error = await Assert.ThrowsAsync<InvalidOperationException>(() => client.CreateBadgeGroupAsync("token"));

        Assert.Contains("printBadgeGroup.id", error.Message);
        Assert.Single(handler.Requests);
    }

    [Theory]
    [InlineData("succeeded", true)]
    [InlineData("failed", false)]
    public async Task V3Creation_PollsNonterminalStateAndPropagatesFailure(string finalState, bool succeeds)
    {
        var handler = new RecordingHttpMessageHandler((_, call) =>
        {
            var response = RecordingHttpMessageHandler.JsonResponse(
                call == 0 ? HttpStatusCode.Accepted : HttpStatusCode.OK,
                call switch
                {
                    0 => """{"id":"operation-1","printBadgeGroup":{"id":"group-1"}}""",
                    1 => """{"status":{"state":"running"}}""",
                    _ => $$$"""{"status":{"state":"{{{finalState}}}","description":"Provisioning result"}}"""
                });
            response.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.Zero);
            return response;
        });
        using var client = new BadgeManagement("https://graph.example/beta", handler, useV3GraphBadgeApi: true);

        if (succeeds)
        {
            Assert.Equal("group-1", (await client.CreateBadgeGroupAsync("token")).Id);
        }
        else
        {
            var error = await Assert.ThrowsAsync<InvalidOperationException>(() => client.CreateBadgeGroupAsync("token"));
            Assert.Contains("Provisioning result", error.Message);
        }

        Assert.Equal(3, handler.Requests.Count);
        Assert.All(handler.Requests.Skip(1), request =>
            Assert.Equal("https://graph.example/beta/print/operations/operation-1", request.Uri));
    }

    [Fact]
    public async Task V3Reads_AllowUnavailableFieldsWithoutInventingIdentity()
    {
        var handler = new RecordingHttpMessageHandler((_, call) =>
            RecordingHttpMessageHandler.JsonResponse(HttpStatusCode.OK, call == 0
                ? """{"value":[{"@odata.type":"#microsoft.graph.printBadgeGroup","id":"group-1","displayName":null,"createdDateTime":null}]}"""
                : """{"@odata.type":"#microsoft.graph.printBadge","id":"badge-1","userPrincipalName":"user@example.com","userId":null,"physicalBadgeId":null,"createdDateTime":null,"user":null}"""));
        using var client = new BadgeManagement("https://graph.example/beta", handler, useV3GraphBadgeApi: true);

        var group = Assert.Single(await client.ListBadgeGroupsAsync("token"));
        var badge = await client.GetBadgeAsync("token", group.Id, "badge-1");

        Assert.Equal("group-1", group.Id);
        Assert.Null(group.DisplayName);
        Assert.Null(group.CreatedDateTime);
        Assert.NotNull(badge);
        Assert.Equal("badge-1", badge.Id);
        Assert.Equal("user@example.com", badge.Upn);
        Assert.Null(badge.UserId);
        Assert.Null(badge.PhysicalBadgeId);
        Assert.Null(badge.CreatedDateTime);
    }

    [Theory]
    [InlineData(HttpStatusCode.NotImplemented)]
    [InlineData(HttpStatusCode.BadRequest)]
    [InlineData(HttpStatusCode.InternalServerError)]
    public async Task V3List_ReportsServiceErrorsWithoutLegacyFallback(HttpStatusCode status)
    {
        var handler = new RecordingHttpMessageHandler((_, _) =>
            RecordingHttpMessageHandler.JsonResponse(status, """{"error":{"message":"Service limitation"}}"""));
        using var client = new BadgeManagement("https://graph.example/beta", handler, useV3GraphBadgeApi: true);

        var error = await Assert.ThrowsAsync<HttpRequestException>(() => client.ListBadgesAsync("token", "group-1"));

        Assert.Equal(status, error.StatusCode);
        Assert.Contains("Service limitation", error.Message);
        Assert.Contains("/print/badgeGroups/group-1/badges", Assert.Single(handler.Requests).Uri);
    }

    [Fact]
    public async Task LegacyList_PreservesUnsupportedResult()
    {
        var handler = new RecordingHttpMessageHandler((_, _) => new HttpResponseMessage(HttpStatusCode.NotImplemented));
        using var client = new BadgeManagement("https://graph.example/v1.0", handler);

        Assert.False((await client.ListBadgesAsync("token", "group-1")).IsSupported);
    }

    [Theory]
    [InlineData(false, null)]
    [InlineData(false, "")]
    [InlineData(false, " ")]
    [InlineData(true, null)]
    [InlineData(true, "")]
    [InlineData(true, " ")]
    public async Task BadgeWrites_RejectEmptyUserPrincipalName(bool useV3, string? upn)
    {
        var handler = new RecordingHttpMessageHandler((_, _) => throw new InvalidOperationException("Unexpected request."));
        using var client = new BadgeManagement("https://graph.example/beta", handler, useV3);

        await Assert.ThrowsAsync<ArgumentException>(() => client.AddBadgeAsync("token", "group-1", "badge-1", upn!));
        await Assert.ThrowsAsync<ArgumentException>(() => client.UpdateBadgeAsync("token", "group-1", "badge-1", upn!, null));

        Assert.Empty(handler.Requests);
    }

    [Theory]
    [InlineData(false, null, null)]
    [InlineData(false, "upn", null)]
    [InlineData(false, "upn", "")]
    [InlineData(false, "upn", " ")]
    [InlineData(true, null, null)]
    [InlineData(true, "userPrincipalName", null)]
    [InlineData(true, "userPrincipalName", "")]
    [InlineData(true, "userPrincipalName", " ")]
    public async Task BadgeReads_RejectMissingOrEmptyUserPrincipalName(bool useV3, string? propertyName, string? upn)
    {
        var badge = new Dictionary<string, string?> { ["id"] = "badge-1" };
        if (propertyName != null)
        {
            badge[propertyName] = upn;
        }

        var handler = new RecordingHttpMessageHandler((_, _) =>
            RecordingHttpMessageHandler.JsonResponse(HttpStatusCode.OK,
                JsonSerializer.Serialize(badge)));
        using var client = new BadgeManagement("https://graph.example/beta", handler, useV3);

        var error = await Assert.ThrowsAsync<InvalidOperationException>(() =>
            client.GetBadgeAsync("token", "group-1", "badge-1"));

        Assert.Contains("user principal name", error.Message);
    }

    [Fact]
    public async Task CreateBadgeGroupAsync_AcceptsCaseInsensitiveSucceededState()
    {
        var handler = new RecordingHttpMessageHandler((_, call) => call switch
        {
            0 => RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.Accepted,
                """{"id":"operation-1","collectionId":"group-1"}"""),
            1 => RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.OK,
                """{"status":{"state":"SuCcEeDeD"}}"""),
            _ => throw new InvalidOperationException("Unexpected request.")
        });
        using var client = new BadgeManagement("https://graph.example/v1.0", handler);

        var result = await client.CreateBadgeGroupAsync("access-token");

        Assert.Equal("group-1", result.Id);
        Assert.True(result.Created);
        Assert.Equal(2, handler.Requests.Count);
        Assert.Equal(
            "https://graph.example/v1.0/print/operations/operation-1",
            handler.Requests[1].Uri);
    }

    [Theory]
    [InlineData(false, "badgeCollections")]
    [InlineData(true, "badgeGroups")]
    public async Task CreateBadgeGroupAsync_ReportsExistingBadgeGroup(bool useV3, string resource)
    {
        var handler = new RecordingHttpMessageHandler((_, call) => call switch
        {
            0 => new HttpResponseMessage(HttpStatusCode.Conflict),
            1 => RecordingHttpMessageHandler.JsonResponse(
                HttpStatusCode.OK,
                """{"value":[{"id":"existing-group"}]}"""),
            _ => throw new InvalidOperationException("Unexpected request.")
        });
        using var client = new BadgeManagement("https://graph.example/v1.0", handler, useV3);

        var result = await client.CreateBadgeGroupAsync("access-token");

        Assert.Equal("existing-group", result.Id);
        Assert.False(result.Created);
        Assert.All(handler.Requests, request =>
            Assert.Equal($"https://graph.example/v1.0/print/{resource}", request.Uri));
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
                "group-1",
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
            "group-1",
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
