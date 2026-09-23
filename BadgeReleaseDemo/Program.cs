// <copyright file="Program.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

using System.CommandLine;
using System.Diagnostics;
using System.Text.Json;
using BadgeReleaseDemo.Auth;
using BadgeReleaseDemo.GraphApi;
using BadgeReleaseDemo.Helpers;
using BadgeReleaseDemo.IppOperations;

namespace BadgeReleaseDemo;

/// <summary>
/// Badge Release Demo — demonstrates the Universal Print Badge Release API lifecycle.
///
/// Flow:
///   1. Sign in as Printer Admin
///   2. Register a virtual printer
///   3. Share the printer (with jobs held for secure release)
///   4. Create a badge collection and add a badge
///   5. Advertise badge release support
///   6. Submit a PDF print job and verify it remains held
///   7. Resolve the badge, verify the job becomes fetchable, fetch it, and complete it
/// </summary>
public class Program
{
    public static async Task<int> Main(string[] args)
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;

        var rootCommand = CreateRootCommand();
        return await rootCommand.Parse(NormalizeArguments(args)).InvokeAsync();
    }

    internal static RootCommand CreateRootCommand()
    {
        var rootCommand = new RootCommand(
            "Universal Print Badge Release demo and badge management utility.");

        var demoUseV1Option = CreateUseV1BadgeApiOption();
        var demoCommand = new Command("demo", "Run the full interactive badge release workflow");
        demoCommand.Options.Add(demoUseV1Option);
        demoCommand.SetAction(async parseResult =>
        {
            return await RunDemoAsync(parseResult.GetValue(demoUseV1Option));
        });

        rootCommand.Subcommands.Add(demoCommand);
        rootCommand.Subcommands.Add(BadgeManagementCommands.Create());
        return rootCommand;
    }

    internal static string[] NormalizeArguments(string[] args) =>
        args.Length == 0 ? ["--help"] : args;

    private static Option<bool> CreateUseV1BadgeApiOption() =>
        new("--use-v1-badge-api")
        {
            Description = "Use the legacy V1 badge lookup API during the demo"
        };

    private static async Task<int> RunDemoAsync(bool useV1BadgeApi)
    {
        ConsoleHelper.WriteHeader("🏷️  Universal Print — Badge Release Demo");

        // Load configuration
        var config = LoadConfiguration("appsettings.json");
        var badgeApiConfig = LoadConfiguration("badgeapisettings.json");
        var appId = config.GetProperty("AppId").GetString()!;
        var tenantId = config.TryGetProperty("Tenant", out var tid) ? tid.GetString() ?? string.Empty : string.Empty;
        var graphBaseUrl = config.GetProperty("GraphBaseUrl").GetString()!;
        var graphPrintBaseUrl = config.GetProperty("GraphPrintBaseUrl").GetString()!;
        var registrationBaseUrl = config.GetProperty("RegistrationBaseUrl").GetString()!;
        var ippServiceBaseUrl = config.GetProperty("IppServiceBaseUrl").GetString()!;
        var ippServicePrinterPath = config.GetProperty("IppServicePrinterPath").GetString()!;
        var badgesV1ApiPath = badgeApiConfig.GetProperty("BadgesV1ApiPath").GetString()!;
        var badgesV2ApiPath = badgeApiConfig.GetProperty("BadgesV2ApiPath").GetString()!;
        if (appId == "YOUR_APP_ID_HERE" || tenantId == "YOUR_TENANT_HERE")
        {
            ConsoleHelper.WriteError("Please set your App ID and Tenant in appsettings.json before running this demo.");
            return 1;
        }

        // Initialize services
        var auth = new AuthHelper(appId, tenantId);
        string printerToken = string.Empty;

        async Task<string> RefreshAndStorePrinterTokenAsync()
        {
            printerToken = await auth.RefreshPrinterTokenAsync();
            return printerToken;
        }

        using var printerReg = new PrinterRegistration(registrationBaseUrl);
        using var printerShare = new PrinterSharing(graphBaseUrl);
        using var badgeMgmt = new BadgeManagement(graphPrintBaseUrl);
        using var jobSubmission = new PrintJobSubmission(graphBaseUrl);
        using var ippClient = new PrinterIppClient(
            ippServiceBaseUrl,
            ippServicePrinterPath,
            badgesV1ApiPath,
            badgesV2ApiPath,
            useV1BadgeApi,
            RefreshAndStorePrinterTokenAsync);


        string printerId = string.Empty;
        string shareId = string.Empty;
        string badgeCollectionId = string.Empty;
        string createdBadgeId = string.Empty;
        string? savedDocumentPath = null;

        try
        {
            // ═══════════════════════════════════════════════════════════
            // Step 1: Sign in as Printer Admin
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🔑", "Signing in as Printer Administrator...");
            var upn = await auth.SignInUserAsync();
            ConsoleHelper.WriteSuccess($"Signed in as: {upn}");

            // ═══════════════════════════════════════════════════════════
            // Step 2: Register a virtual printer
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🖨️", "Registering a virtual printer...");
            var keyPair = CryptoHelper.GenerateKeyPair();
            var csr = CryptoHelper.GenerateCsr(keyPair);
            var transportKey = CryptoHelper.GetTransportKey(keyPair);

            var token = await auth.GetUserTokenAsync();
            var printerName = $"BadgeReleaseDemo-{DateTime.UtcNow:yyyyMMdd-HHmmss}";
            var regResult = await printerReg.RegisterPrinterAsync(
                token, printerName, csr, transportKey);

            printerId = regResult.PrinterId;
            ConsoleHelper.WriteSuccess($"Printer registered: {printerName}");
            ConsoleHelper.WriteKeyValue("Printer ID", printerId);

            // Store printer credentials in memory
            auth.SetPrinterCredentials(regResult, keyPair);

            // ═══════════════════════════════════════════════════════════
            // Step 3: Share the printer
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🖨️", "Creating printer share...");
            var graphToken = await auth.GetGraphTokenAsync();
            shareId = await printerShare.CreateShareAsync(graphToken, printerId, printerName);
            ConsoleHelper.WriteSuccess("Printer shared with all users.");
            ConsoleHelper.WriteKeyValue("Share ID", shareId);

            // ═══════════════════════════════════════════════════════════
            // Step 4: Create badge collection (if needed)
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🏷️", "Creating badge collection...");
            token = await auth.GetUserTokenAsync();
            var collectionResult = await badgeMgmt.CreateBadgeCollectionAsync(token);
            badgeCollectionId = collectionResult.Id;
            if (collectionResult.Created)
            {
                ConsoleHelper.WriteSuccess($"Badge collection provisioning completed (ID: {badgeCollectionId}).");
                ConsoleHelper.WriteWarning(BadgeManagement.CollectionSettlingNote);
            }
            else
            {
                ConsoleHelper.WriteSuccess($"Using existing badge collection (ID: {badgeCollectionId}).");
            }

            // ═══════════════════════════════════════════════════════════
            // Step 5: Prompt for badge ID and create badge
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🏷️", "Badge registration");
            ConsoleHelper.WriteInfo($"The signed-in user is: {auth.UserUpn}");
            var badgeId = ConsoleHelper.Prompt("Enter a badge ID to associate with this user");

            if (string.IsNullOrWhiteSpace(badgeId))
            {
                ConsoleHelper.WriteError("Badge ID cannot be empty.");
                return 1;
            }

            // ═══════════════════════════════════════════════════════════
            // Step 6: Add badge
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🏷️", $"Adding badge '{badgeId}' → {auth.UserUpn}");
            token = await auth.GetUserTokenAsync();
            await badgeMgmt.AddBadgeAsync(token, badgeCollectionId, badgeId, auth.UserUpn);
            createdBadgeId = badgeId;
            ConsoleHelper.WriteSuccess($"Badge '{badgeId}' mapped to {auth.UserUpn}.");

            // ═══════════════════════════════════════════════════════════
            // Step 7: Advertise badge release support
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🔐", "Configuring printer badge release capability...");
            ConsoleHelper.WriteProgress("Acquiring printer device token...");
            printerToken = await auth.GetPrinterTokenAsync();
            ConsoleHelper.WriteSuccess("Printer authenticated.");

            ConsoleHelper.WriteProgress("Advertising badge release capability...");
            var capabilityStatus = await ippClient.AdvertiseBadgeReleaseCapabilityAsync(
                printerToken,
                printerId);
            if (capabilityStatus != 0x0000)
            {
                ConsoleHelper.WriteError(
                    $"Update-Output-Device-Attributes failed: {capabilityStatus:X4}");
                return 1;
            }

            ConsoleHelper.WriteSuccess(
                "Printer advertised job-release-action-supported=owner-authorized-badge.");

            // ═══════════════════════════════════════════════════════════
            // Step 8: Submit a PDF print job
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("📄", "Submitting print job...");

            var bundledPdfPath = Path.Combine(AppContext.BaseDirectory, "Resources", "SampleDocument.pdf");
            var pdfPrompt = File.Exists(bundledPdfPath)
                ? "Enter the path to a PDF file to print (leave blank to use the bundled sample)"
                : "Enter the path to a PDF file to print";
            var pdfPath = ConsoleHelper.Prompt(pdfPrompt);

            if (string.IsNullOrWhiteSpace(pdfPath))
            {
                if (!File.Exists(bundledPdfPath))
                {
                    ConsoleHelper.WriteError("PDF path cannot be empty.");
                    return 1;
                }

                pdfPath = bundledPdfPath;
                ConsoleHelper.WriteInfo($"Using bundled sample document: {pdfPath}");
            }

            pdfPath = pdfPath.Trim('"'); // Remove quotes if user dragged file into console
            if (!File.Exists(pdfPath))
            {
                ConsoleHelper.WriteError($"File not found: {pdfPath}");
                return 1;
            }

            graphToken = await auth.GetGraphTokenAsync();
            var (jobId, documentId) = await jobSubmission.CreateJobAsync(
                graphToken, shareId, "Badge Release Demo Job");
            ConsoleHelper.WriteKeyValue("Job ID", jobId);
            ConsoleHelper.WriteKeyValue("Document ID", documentId);

            // Upload the PDF
            ConsoleHelper.WriteProgress("Uploading document...");
            var pdfData = await File.ReadAllBytesAsync(pdfPath);
            var uploadUrl = await jobSubmission.CreateUploadSessionAsync(graphToken, shareId, jobId, documentId, Path.GetFileName(pdfPath), pdfData.Length);
            await jobSubmission.UploadDocumentAsync(uploadUrl, pdfData);

            // Start the job
            await jobSubmission.StartJobAsync(graphToken, shareId, jobId);
            ConsoleHelper.WriteSuccess("Print job submitted and started.");

            // ═══════════════════════════════════════════════════════════
            // Step 9: Verify secure-release holding before badge scan
            // ═══════════════════════════════════════════════════════════
            if (!int.TryParse(jobId, out var submittedJobId))
            {
                ConsoleHelper.WriteError(
                    $"Graph job ID '{jobId}' cannot be validated as an IPP job ID.");
                return 1;
            }

            ConsoleHelper.WriteStep("🔒", "Verifying the job is held before badge authentication...");
            var preReleaseObservationDuration = TimeSpan.FromSeconds(90);
            var preReleaseObservationEndsAt = DateTime.UtcNow.Add(preReleaseObservationDuration);
            ConsoleHelper.WriteProgress(
                $"Observing job visibility for {preReleaseObservationDuration.TotalSeconds:0} seconds...");
            while (true)
            {
                var preReleaseResult = await ippClient.GetJobsAsync(
                    printerToken,
                    printerId,
                    string.Empty);
                if (preReleaseResult.StatusCode != 0x0000)
                {
                    ConsoleHelper.WriteError(
                        $"Could not verify secure-release holding because Get-Jobs failed: " +
                        $"{preReleaseResult.StatusCode:X4}.");
                    return 1;
                }

                if (FindJobById(preReleaseResult.Jobs, submittedJobId) != null)
                {
                    ConsoleHelper.WriteError(
                        $"Submitted job {submittedJobId} was fetchable before badge authentication. " +
                        "Secure-release holding is not working.");
                    return 1;
                }

                var remainingObservationTime = preReleaseObservationEndsAt - DateTime.UtcNow;
                if (remainingObservationTime <= TimeSpan.Zero)
                {
                    break;
                }

                var delay = TimeSpan.FromSeconds(
                    Math.Min(5, remainingObservationTime.TotalSeconds));
                ConsoleHelper.WriteInfo(
                    $"Submitted job {submittedJobId} remains unavailable before badge authentication. " +
                    $"Checking again in {delay.TotalSeconds:0.#} seconds...");
                await Task.Delay(delay);
            }

            ConsoleHelper.WriteSuccess(
                $"Confirmed submitted job {submittedJobId} remained unavailable for " +
                $"{preReleaseObservationDuration.TotalSeconds:0} seconds " +
                "before badge authentication.");

            // ═══════════════════════════════════════════════════════════
            // Step 10: Simulate badge scan
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🏷️", "Simulating badge scan at the printer...");
            ConsoleHelper.WriteInfo("Imagine you are walking up to the printer and scanning your badge.");

            // Badge scan retry loop
            string? resolvedUserUri = null;
            int resolvedJobId;
            string resolvedJobUri;

            while (true)
            {
                var scannedBadgeId = ConsoleHelper.Prompt("Scan badge (enter badge ID)");
                if (string.IsNullOrWhiteSpace(scannedBadgeId))
                {
                    ConsoleHelper.WriteError("Badge ID cannot be empty. Try again.");
                    continue;
                }

                // ═══════════════════════════════════════════════════════
                // Step 11: Resolve badge via IPPService BadgesController
                // ═══════════════════════════════════════════════════════
                ConsoleHelper.WriteStep("🔍", $"Resolving badge '{scannedBadgeId}'...");
                try
                {
                    var badgeResult = await ippClient.ResolveBadgeAsync(printerToken, scannedBadgeId);

                    if (badgeResult == null)
                    {
                        ConsoleHelper.WriteError($"Badge '{scannedBadgeId}' not found. Try again.");
                        continue;
                    }

                    resolvedUserUri = badgeResult.Value.UserUri;
                    ConsoleHelper.WriteSuccess($"Badge resolved!");
                    ConsoleHelper.WriteKeyValue("Badge ID", badgeResult.Value.BadgeId);
                    ConsoleHelper.WriteKeyValue("User URI", resolvedUserUri);
                    ConsoleHelper.WriteKeyValue("User ID field present", badgeResult.Value.UserIdPresent ? "yes" : "no");
                    ConsoleHelper.WriteKeyValue("User ID", badgeResult.Value.UserId ?? "(null)");
                    break;
                }
                catch (Exception ex)
                {
                    ConsoleHelper.WriteError($"Badge resolution failed: {ex.Message}");
                    ConsoleHelper.WriteInfo("Try scanning again.");
                    continue;
                }
            }

            // ═══════════════════════════════════════════════════════════
            // Step 12: Verify the job is fetchable after badge authentication
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🖨️", "Verifying the badge-authenticated job is fetchable...");
            var postAuthenticationPollingDuration = TimeSpan.FromSeconds(90);
            var pollingInterval = TimeSpan.FromSeconds(5);
            var postAuthenticationStopwatch = Stopwatch.StartNew();
            (int JobId, string JobUri)? selectedJob = null;
            List<(int JobId, string JobUri)> jobs = [];
            while (selectedJob == null)
            {
                var getJobsResult = await ippClient.GetJobsAsync(
                    printerToken,
                    printerId,
                    resolvedUserUri!);
                if (getJobsResult.StatusCode != 0x0000)
                {
                    ConsoleHelper.WriteError(
                        $"Could not verify badge-authenticated job visibility because Get-Jobs failed: " +
                        $"{getJobsResult.StatusCode:X4}.");
                    return 1;
                }

                jobs = getJobsResult.Jobs;
                if (jobs.Count == 0)
                {
                    ConsoleHelper.WriteInfo("Get-Jobs returned no fetchable jobs.");
                }
                else
                {
                    ConsoleHelper.WriteInfo(
                        $"Get-Jobs returned IPP job ID(s): {string.Join(", ", jobs.Select(job => job.JobId))}");
                }

                selectedJob = FindJobById(jobs, submittedJobId);
                if (selectedJob != null)
                {
                    break;
                }

                var delay = GetNextPollingDelay(
                    postAuthenticationStopwatch.Elapsed,
                    postAuthenticationPollingDuration,
                    pollingInterval);
                if (delay == null)
                {
                    ConsoleHelper.WriteError(
                        $"Submitted job {submittedJobId} was not fetchable after badge authentication.");
                    return 1;
                }

                ConsoleHelper.WriteInfo(
                    $"Submitted job {submittedJobId} not fetchable yet. " +
                    $"Polling again in {delay.Value.TotalSeconds:0.#} seconds...");
                await Task.Delay(delay.Value);
            }

            resolvedJobId = selectedJob.Value.JobId;
            resolvedJobUri = selectedJob.Value.JobUri;
            ConsoleHelper.WriteSuccess(
                $"Confirmed submitted job {resolvedJobId} is fetchable after badge authentication.");
            ConsoleHelper.WriteInfo($"Found {jobs.Count} fetchable job(s) for the user.");
            ConsoleHelper.WriteKeyValue("Fetching Job ID", resolvedJobId.ToString());
            if (!string.IsNullOrEmpty(resolvedJobUri))
            {
                ConsoleHelper.WriteKeyValue("Fetching Job URI", resolvedJobUri);
            }

            // ═══════════════════════════════════════════════════════════
            // Step 13: Fetch-Job (get job metadata)
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🖨️", "Printer: Fetching job metadata...");
            var (fetchJobStatusCode, _, _) = await ippClient.FetchJobAsync(
                printerToken, printerId, resolvedJobId, resolvedUserUri!);

            if (fetchJobStatusCode != 0x0000) // 0x0000 = successful-ok
            {
                ConsoleHelper.WriteError($"Fetch-Job failed: {fetchJobStatusCode:X4}");
                return 1;
            }

            ConsoleHelper.WriteSuccess("Job metadata received.");

            // ═══════════════════════════════════════════════════════════
            // Step 14: Acknowledge-Job
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🖨️", "Printer: Acknowledging job...");
            var ackStatus = await ippClient.AcknowledgeJobAsync(
                printerToken, printerId, resolvedJobId, resolvedUserUri!);

            if (ackStatus != 0x0000) // 0x0000 = successful-ok
            {
                ConsoleHelper.WriteError($"Acknowledge-Job failed: {ackStatus:X4}");
                return 1;
            }

            ConsoleHelper.WriteSuccess("Job acknowledged.");

            // ═══════════════════════════════════════════════════════════
            // Step 15: Fetch-Document (download PDF)
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("📄", "Printer: Downloading document...");
            var documentData = await ippClient.FetchDocumentAsync(
                printerToken, printerId, resolvedJobId, resolvedUserUri!, resolvedJobUri);

            if (documentData == null || documentData.Length == 0)
            {
                ConsoleHelper.WriteError("Failed to download document.");
                return 1;
            }

            ConsoleHelper.WriteSuccess($"Document downloaded ({documentData.Length} bytes).");

            // Save and open the document
            savedDocumentPath = PrinterIppClient.SaveAndOpenDocument(documentData);

            // ═══════════════════════════════════════════════════════════
            // Step 16: Update-Job-Status → Completed
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("✅", "Printer: Marking job as completed...");
            var completeStatus = await ippClient.UpdateJobStatusAsync(
                printerToken, printerId, resolvedJobId, resolvedUserUri!);

            if (completeStatus != 0x0000) // 0x0000 = successful-ok
            {
                ConsoleHelper.WriteError($"Update-Job-Status failed: {completeStatus:X4}");
                return 1;
            }

            ConsoleHelper.WriteSuccess("Job marked as completed! 🎉");

            ConsoleHelper.WriteHeader("🎉 Demo Complete!");
            ConsoleHelper.WriteInfo("The Badge Release flow completed successfully.");
            ConsoleHelper.WriteInfo("Press any key to exit.");
            Console.ReadKey();
            return 0;
        }
        catch (Exception ex)
        {
            ConsoleHelper.WriteError($"Demo failed: {ex.Message}");
            ConsoleHelper.WriteInfo(ex.StackTrace ?? string.Empty);
            return 1;
        }
        finally
        {
            // Auto-cleanup: delete badge, share, printer, and downloaded document
            if (!string.IsNullOrEmpty(shareId) || !string.IsNullOrEmpty(printerId)
                || !string.IsNullOrEmpty(createdBadgeId) || savedDocumentPath != null)
            {
                ConsoleHelper.WriteHeader("🧹 Cleaning up demo resources...");

                if (!string.IsNullOrEmpty(createdBadgeId) && !string.IsNullOrEmpty(badgeCollectionId))
                {
                    try
                    {
                        ConsoleHelper.WriteProgress($"Deleting badge '{createdBadgeId}'...");
                        var printToken = await auth.GetUserTokenAsync();
                        await badgeMgmt.DeleteBadgeAsync(printToken, badgeCollectionId, createdBadgeId);
                        ConsoleHelper.WriteSuccess("Badge deleted.");
                    }
                    catch (Exception badgeCleanupEx)
                    {
                        ConsoleHelper.WriteWarning($"Failed to delete badge: {badgeCleanupEx.Message}");
                    }
                }

                if (!string.IsNullOrEmpty(shareId))
                {
                    try
                    {
                        var graphToken = await auth.GetGraphTokenAsync();
                        ConsoleHelper.WriteProgress($"Deleting share {shareId}...");
                        await printerShare.DeleteShareAsync(graphToken, shareId);
                        ConsoleHelper.WriteSuccess("Share deleted.");
                    }
                    catch (Exception shareCleanupEx)
                    {
                        ConsoleHelper.WriteWarning($"Failed to delete share: {shareCleanupEx.Message}");
                    }
                }

                if (!string.IsNullOrEmpty(printerId))
                {
                    try
                    {
                        var graphToken = await auth.GetGraphTokenAsync();
                        ConsoleHelper.WriteProgress($"Deleting printer {printerId}...");
                        await printerShare.DeletePrinterAsync(graphToken, printerId);
                        ConsoleHelper.WriteSuccess("Printer deleted.");
                    }
                    catch (Exception printerCleanupEx)
                    {
                        ConsoleHelper.WriteWarning($"Failed to delete printer: {printerCleanupEx.Message}");
                    }
                }

                // Delete the downloaded document last so a file lock can't abort resource cleanup above.
                if (savedDocumentPath != null && File.Exists(savedDocumentPath))
                {
                    try
                    {
                        ConsoleHelper.WriteProgress("Deleting downloaded document...");
                        File.Delete(savedDocumentPath);
                        ConsoleHelper.WriteSuccess("Document deleted.");
                    }
                    catch (Exception docCleanupEx)
                    {
                        ConsoleHelper.WriteWarning($"Could not delete document ({docCleanupEx.Message}): {savedDocumentPath}");
                    }
                }
            }
        }
    }

    internal static (int JobId, string JobUri)? FindJobById(
        IEnumerable<(int JobId, string JobUri)> jobs,
        int jobId)
    {
        foreach (var job in jobs)
        {
            if (job.JobId == jobId)
            {
                return job;
            }
        }

        return null;
    }

    internal static TimeSpan? GetNextPollingDelay(
        TimeSpan elapsed,
        TimeSpan pollingDuration,
        TimeSpan pollingInterval)
    {
        var remaining = pollingDuration - elapsed;
        if (remaining <= TimeSpan.Zero)
        {
            return null;
        }

        return remaining < pollingInterval ? remaining : pollingInterval;
    }

    private static JsonElement LoadConfiguration(string fileName)
    {
        var configPath = Path.Combine(AppContext.BaseDirectory, fileName);

        if (!File.Exists(configPath))
        {
            throw new FileNotFoundException(
                $"{fileName} not found. Make sure it's in the output directory.",
                configPath);
        }

        var json = File.ReadAllText(configPath);
        return JsonSerializer.Deserialize<JsonElement>(json);
    }
}
