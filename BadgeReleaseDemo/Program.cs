// <copyright file="Program.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

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
///   3. Share the printer
///   4. Create a badge collection and add a badge
///   5. Submit a PDF print job
///   6. Simulate badge scan → resolve badge → IPP fetch → open document → complete job
/// </summary>
public class Program
{
    public static async Task Main(string[] args)
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;

        ConsoleHelper.WriteHeader("🏷️  Universal Print — Badge Release Demo");

        // Load configuration
        var config = LoadConfiguration();
        var appId = config.GetProperty("AppId").GetString()!;
        var tenantId = config.TryGetProperty("Tenant", out var tid) ? tid.GetString() ?? string.Empty : string.Empty;
        var graphBaseUrl = config.GetProperty("GraphBaseUrl").GetString()!;
        var graphPrintBaseUrl = config.GetProperty("GraphPrintBaseUrl").GetString()!;
        var registrationBaseUrl = config.GetProperty("RegistrationBaseUrl").GetString()!;
        var ippServiceBaseUrl = config.GetProperty("IppServiceBaseUrl").GetString()!;
        var ippServicePrinterPath = config.GetProperty("IppServicePrinterPath").GetString()!;
        var badgesApiPath = config.GetProperty("BadgesApiPath").GetString()!;

        if (appId == "YOUR_APP_ID_HERE" || tenantId == "YOUR_TENANT_HERE")
        {
            ConsoleHelper.WriteError("Please set your App ID and Tenant in appsettings.json before running this demo.");
            return;
        }

        // Initialize services
        var auth = new AuthHelper(appId, tenantId, graphBaseUrl);
        var printerReg = new PrinterRegistration(registrationBaseUrl);
        var printerShare = new PrinterSharing(graphBaseUrl);
        var badgeMgmt = new BadgeManagement(graphPrintBaseUrl);
        var jobSubmission = new PrintJobSubmission(graphBaseUrl);
        var ippClient = new PrinterIppClient(ippServiceBaseUrl, ippServicePrinterPath, badgesApiPath);


        string printerId= string.Empty;
        string shareId = string.Empty;
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
            var collectionId = await badgeMgmt.CreateBadgeCollectionAsync(token);
            ConsoleHelper.WriteSuccess($"Badge collection ready (ID: {collectionId}).");

            // ═══════════════════════════════════════════════════════════
            // Step 5: Prompt for badge ID and create badge
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🏷️", "Badge registration");
            ConsoleHelper.WriteInfo($"The signed-in user is: {auth.UserUpn}");
            var badgeId = ConsoleHelper.Prompt("Enter a badge ID to associate with this user");

            if (string.IsNullOrWhiteSpace(badgeId))
            {
                ConsoleHelper.WriteError("Badge ID cannot be empty.");
                return;
            }

            // ═══════════════════════════════════════════════════════════
            // Step 6: Add badge
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🏷️", $"Adding badge '{badgeId}' → {auth.UserUpn}");
            token = await auth.GetUserTokenAsync();
            await badgeMgmt.AddBadgeAsync(token, badgeId, auth.UserUpn);
            createdBadgeId = badgeId;
            ConsoleHelper.WriteSuccess($"Badge '{badgeId}' mapped to {auth.UserUpn}.");

            // ═══════════════════════════════════════════════════════════
            // Step 7: Enable badge release on the printer via Graph
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🖨️", "Configuring printer for badge release...");
            graphToken = await auth.GetGraphTokenAsync();
            await printerShare.EnableBadgeReleaseAsync(graphToken, printerId);
            ConsoleHelper.WriteSuccess("Badge release enabled on printer.");

            // ═══════════════════════════════════════════════════════════
            // Step 8: Submit a PDF print job
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("📄", "Submitting print job...");

            var pdfPath = ConsoleHelper.Prompt("Enter the path to a PDF file to print");
            if (string.IsNullOrWhiteSpace(pdfPath))
            {
                ConsoleHelper.WriteError("PDF path cannot be empty.");
                return;
            }

            pdfPath = pdfPath.Trim('"'); // Remove quotes if user dragged file into console
            if (!File.Exists(pdfPath))
            {
                ConsoleHelper.WriteError($"File not found: {pdfPath}");
                return;
            }

            graphToken = await auth.GetGraphTokenAsync();
            var (jobId, documentId) = await jobSubmission.CreateJobAsync(
                graphToken, shareId, "Badge Release Demo Job");
            ConsoleHelper.WriteKeyValue("Job ID", jobId);
            ConsoleHelper.WriteKeyValue("Document ID", documentId);

            // Upload the PDF
            ConsoleHelper.WriteProgress("Uploading document...");
            var pdfData = await File.ReadAllBytesAsync(pdfPath);
            var uploadUrl = await jobSubmission.CreateUploadSessionAsync(graphToken, shareId, jobId, documentId, pdfData.Length);
            await jobSubmission.UploadDocumentAsync(graphToken, uploadUrl, pdfData);

            // Start the job
            await jobSubmission.StartJobAsync(graphToken, shareId, jobId);
            ConsoleHelper.WriteSuccess("Print job submitted and started.");

            // ═══════════════════════════════════════════════════════════
            // Step 9: Acquire printer device token + simulate badge scan
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🏷️", "Simulating badge scan at the printer...");
            ConsoleHelper.WriteInfo("Imagine you are walking up to the printer and scanning your badge.");
            ConsoleHelper.WriteProgress("Acquiring printer device token...");
            var printerToken = await auth.GetPrinterTokenAsync();
            ConsoleHelper.WriteSuccess("Printer authenticated.");

            // Badge scan retry loop
            string? resolvedUserUri = null;
            int resolvedJobId = 0;

            while (true)
            {
                var scannedBadgeId = ConsoleHelper.Prompt("Scan badge (enter badge ID)");
                if (string.IsNullOrWhiteSpace(scannedBadgeId))
                {
                    ConsoleHelper.WriteError("Badge ID cannot be empty. Try again.");
                    continue;
                }

                // ═══════════════════════════════════════════════════════
                // Step 9: Resolve badge via IPPService BadgesController
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
                    ConsoleHelper.WriteKeyValue("User ID", badgeResult.Value.UserId);
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
            // Step 10: Get-Jobs as printer with requesting-user-uri
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🖨️", "Printer: Getting fetchable jobs...");
            var jobs = await ippClient.GetJobsAsync(printerToken, printerId, resolvedUserUri!);

            if (jobs.Count == 0)
            {
                ConsoleHelper.WriteWarning("No fetchable jobs found for this user.");
                ConsoleHelper.WriteInfo("The job may not be ready yet. In production, the printer would poll.");
                return;
            }

            resolvedJobId = jobs[0].JobId;
            ConsoleHelper.WriteSuccess($"Found {jobs.Count} fetchable job(s).");
            ConsoleHelper.WriteKeyValue("Fetching Job ID", resolvedJobId.ToString());

            // ═══════════════════════════════════════════════════════════
            // Step 11: Fetch-Job (get job metadata)
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🖨️", "Printer: Fetching job metadata...");
            var fetchJobResponse = await ippClient.FetchJobAsync(
                printerToken, printerId, resolvedJobId, resolvedUserUri!);

            if (fetchJobResponse.StatusCode != BadgeReleaseDemo.IppLibrary.StatusCode.SuccessfulOk)
            {
                ConsoleHelper.WriteError($"Fetch-Job failed: {fetchJobResponse.StatusCode}");
                return;
            }

            ConsoleHelper.WriteSuccess("Job metadata received.");

            // ═══════════════════════════════════════════════════════════
            // Step 12: Acknowledge-Job
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("🖨️", "Printer: Acknowledging job...");
            var ackStatus = await ippClient.AcknowledgeJobAsync(
                printerToken, printerId, resolvedJobId, resolvedUserUri!);

            if (ackStatus != BadgeReleaseDemo.IppLibrary.StatusCode.SuccessfulOk)
            {
                ConsoleHelper.WriteError($"Acknowledge-Job failed: {ackStatus}");
                return;
            }

            ConsoleHelper.WriteSuccess("Job acknowledged.");

            // ═══════════════════════════════════════════════════════════
            // Step 13: Fetch-Document (download PDF)
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("📄", "Printer: Downloading document...");
            var documentData = await ippClient.FetchDocumentAsync(
                printerToken, printerId, resolvedJobId, resolvedUserUri!);

            if (documentData == null || documentData.Length == 0)
            {
                ConsoleHelper.WriteError("Failed to download document.");
                return;
            }

            ConsoleHelper.WriteSuccess($"Document downloaded ({documentData.Length} bytes).");

            // Save and open the document
            savedDocumentPath = PrinterIppClient.SaveAndOpenDocument(documentData);

            // ═══════════════════════════════════════════════════════════
            // Step 14: Update-Job-Status → Completed
            // ═══════════════════════════════════════════════════════════
            ConsoleHelper.WriteStep("✅", "Printer: Marking job as completed...");
            var completeStatus = await ippClient.UpdateJobStatusAsync(
                printerToken, printerId, resolvedJobId);

            if (completeStatus != BadgeReleaseDemo.IppLibrary.StatusCode.SuccessfulOk)
            {
                ConsoleHelper.WriteError($"Update-Job-Status failed: {completeStatus}");
                return;
            }

            ConsoleHelper.WriteSuccess("Job marked as completed! 🎉");

            ConsoleHelper.WriteHeader("🎉 Demo Complete!");
            ConsoleHelper.WriteInfo("The Badge Release flow completed successfully.");
            ConsoleHelper.WriteInfo("Press any key to exit.");
            Console.ReadKey();
        }
        catch (Exception ex)
        {
            ConsoleHelper.WriteError($"Demo failed: {ex.Message}");
            ConsoleHelper.WriteInfo(ex.StackTrace ?? string.Empty);
        }
        finally
        {
            // Auto-cleanup: delete badge, share, printer, and downloaded document
            if (!string.IsNullOrEmpty(shareId) || !string.IsNullOrEmpty(printerId)
                || !string.IsNullOrEmpty(createdBadgeId) || savedDocumentPath != null)
            {
                ConsoleHelper.WriteHeader("🧹 Cleaning up demo resources...");

                try
                {
                    if (savedDocumentPath != null && File.Exists(savedDocumentPath))
                    {
                        try
                        {
                            ConsoleHelper.WriteProgress("Deleting downloaded document...");
                            File.Delete(savedDocumentPath);
                            ConsoleHelper.WriteSuccess("Document deleted.");
                        }
                        catch (IOException)
                        {
                            ConsoleHelper.WriteWarning($"Could not delete document (may be open in another app): {savedDocumentPath}");
                        }
                    }

                    if (!string.IsNullOrEmpty(createdBadgeId))
                    {
                        ConsoleHelper.WriteProgress($"Deleting badge '{createdBadgeId}'...");
                        var printToken = await auth.GetUserTokenAsync();
                        await badgeMgmt.DeleteBadgeAsync(printToken, createdBadgeId);
                        ConsoleHelper.WriteSuccess("Badge deleted.");
                    }

                    var graphToken = await auth.GetGraphTokenAsync();

                    if (!string.IsNullOrEmpty(shareId))
                    {
                        ConsoleHelper.WriteProgress($"Deleting share {shareId}...");
                        await printerShare.DeleteShareAsync(graphToken, shareId);
                        ConsoleHelper.WriteSuccess("Share deleted.");
                    }

                    if (!string.IsNullOrEmpty(printerId))
                    {
                        ConsoleHelper.WriteProgress($"Deleting printer {printerId}...");
                        await printerShare.DeletePrinterAsync(graphToken, printerId);
                        ConsoleHelper.WriteSuccess("Printer deleted.");
                    }
                }
                catch (Exception cleanupEx)
                {
                    ConsoleHelper.WriteWarning($"Cleanup failed: {cleanupEx.Message}");
                    ConsoleHelper.WriteInfo("You may need to clean up manually in the Azure portal.");
                    ConsoleHelper.WriteKeyValue("Printer ID", printerId);
                    ConsoleHelper.WriteKeyValue("Share ID", shareId);
                }
            }
        }
    }

    private static JsonElement LoadConfiguration()
    {
        var configPath = Path.Combine(AppContext.BaseDirectory, "appsettings.json");

        if (!File.Exists(configPath))
        {
            throw new FileNotFoundException("appsettings.json not found. Make sure it's in the output directory.", configPath);
        }

        var json = File.ReadAllText(configPath);
        return JsonSerializer.Deserialize<JsonElement>(json);
    }
}
