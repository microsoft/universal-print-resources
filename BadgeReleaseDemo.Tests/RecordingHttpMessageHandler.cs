using System.Net;

namespace BadgeReleaseDemo.Tests;

internal sealed class RecordingHttpMessageHandler(
    Func<RequestSnapshot, int, HttpResponseMessage> responseFactory) : HttpMessageHandler
{
    public List<RequestSnapshot> Requests { get; } = [];

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var snapshot = new RequestSnapshot(
            request.Method,
            request.RequestUri!.OriginalString,
            request.Content == null
                ? null
                : await request.Content.ReadAsStringAsync(cancellationToken),
            request.Content?.Headers.ContentType?.MediaType);
        Requests.Add(snapshot);
        return responseFactory(snapshot, Requests.Count - 1);
    }

    public static HttpResponseMessage JsonResponse(
        HttpStatusCode statusCode,
        string json) =>
        new(statusCode)
        {
            Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json")
        };
}

internal sealed record RequestSnapshot(
    HttpMethod Method,
    string Uri,
    string? Body,
    string? ContentType);
