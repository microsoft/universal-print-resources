namespace BadgeReleaseDemo.Tests;

public class CommandLineTests
{
    [Fact]
    public void NoArguments_ShowRootHelp()
    {
        Assert.Equal(["--help"], Program.NormalizeArguments([]));
        Assert.Equal(["demo"], Program.NormalizeArguments(["demo"]));
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

    [Fact]
    public void MappingUpdate_RequiresUpnDuringParsing()
    {
        var parseResult = Program.CreateRootCommand().Parse(
            ["badges", "mappings", "update", "--badge-id", "badge-1"]);

        Assert.Contains(
            parseResult.Errors,
            error => error.Message.Contains("--upn", StringComparison.Ordinal));
    }

    [Fact]
    public void FindJobById_ReturnsOnlyTheRequestedJob()
    {
        var jobs = new[]
        {
            (JobId: 10, JobUri: "ipps://print.example/jobs/10"),
            (JobId: 20, JobUri: "ipps://print.example/jobs/20")
        };

        Assert.Null(Program.FindJobById(jobs, 30));
        Assert.Equal(jobs[1], Program.FindJobById(jobs, 20));
    }

    [Theory]
    [InlineData(85, 5)]
    [InlineData(88, 2)]
    public void GetNextPollingDelay_ReachesPollingBoundary(
        int elapsedSeconds,
        int expectedDelaySeconds)
    {
        var delay = Program.GetNextPollingDelay(
            TimeSpan.FromSeconds(elapsedSeconds),
            TimeSpan.FromSeconds(90),
            TimeSpan.FromSeconds(5));

        Assert.Equal(TimeSpan.FromSeconds(expectedDelaySeconds), delay);
    }

    [Fact]
    public void GetNextPollingDelay_StopsAfterBoundaryRequest()
    {
        var delay = Program.GetNextPollingDelay(
            TimeSpan.FromSeconds(90),
            TimeSpan.FromSeconds(90),
            TimeSpan.FromSeconds(5));

        Assert.Null(delay);
    }
}
