namespace BadgeReleaseDemo.Tests;

public class CommandLineTests
{
    [Fact]
    public void NormalizeArguments_DefaultsToDemo()
    {
        Assert.Equal(["demo"], Program.NormalizeArguments([]));
        Assert.Equal(
            ["demo", "--use-v1-badge-api"],
            Program.NormalizeArguments(["--use-v1-badge-api"]));
    }

    [Fact]
    public void V1Option_IsAcceptedOnlyByDemo()
    {
        var root = Program.CreateRootCommand();

        Assert.Empty(root.Parse(["demo", "--use-v1-badge-api"]).Errors);
        Assert.NotEmpty(root.Parse(["badges", "--use-v1-badge-api"]).Errors);
        Assert.NotEmpty(root.Parse(["--use-v1-badge-api", "badges"]).Errors);
    }

    [Fact]
    public async Task InvalidV1OptionScope_ReturnsFailureExitCode()
    {
        var parseResult = Program.CreateRootCommand().Parse(["badges", "--use-v1-badge-api"]);

        Assert.Equal(1, await parseResult.InvokeAsync());
    }
}
