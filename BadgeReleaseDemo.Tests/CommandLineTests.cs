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

    [Theory]
    [InlineData("--use-v3-badge-api demo")]
    [InlineData("demo --use-v3-badge-api")]
    [InlineData("demo --use-v3-badge-api --use-v1-badge-api")]
    [InlineData("badges --use-v3-badge-api groups list")]
    [InlineData("badges groups create --use-v3-badge-api")]
    [InlineData("badges mappings get --use-v3-badge-api --group-id group-1 --badge-id badge-1")]
    [InlineData("badges mappings create --use-v3-badge-api --group-id group-1 --badge-id badge-1 --upn user@example.com")]
    public void V3Option_IsRecursiveAndIndependentOfIppLookup(string arguments)
    {
        var root = Program.CreateRootCommand();

        var result = root.Parse(arguments.Split(' '));

        Assert.Empty(result.Errors);
        var option = Assert.Single(root.Options, item => item.Name == "--use-v3-badge-api");
        Assert.True(result.GetValue((System.CommandLine.Option<bool>)option));
    }

    [Fact]
    public void V3Option_IsOptIn()
    {
        var root = Program.CreateRootCommand();
        var option = Assert.Single(root.Options, item => item.Name == "--use-v3-badge-api");

        Assert.False(root.Parse(["demo"]).GetValue((System.CommandLine.Option<bool>)option));
        Assert.False(root.Parse(["badges", "collections", "list"]).GetValue((System.CommandLine.Option<bool>)option));
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
