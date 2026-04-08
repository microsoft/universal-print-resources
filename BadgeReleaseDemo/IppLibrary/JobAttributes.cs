//-----------------------------------------------------------------------
// <copyright file="JobAttributes.cs" company="Microsoft">
// Copyright (c) Microsoft. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

// ReSharper disable once CheckNamespace
namespace BadgeReleaseDemo.IppLibrary.Common
{
    /// <summary>
    /// A list of job attributes defined in the following IPP specs:
    /// https://tools.ietf.org/html/rfc8011
    /// http://ftp.pwg.org/pub/pwg/candidates/cs-ippinfra10-20150619-5100.18.pdf
    /// A list of job template attributes with "-actual" keyword suffix
    /// https://ftp.pwg.org/pub/pwg/candidates/cs-ippactuals10-20030313-5100.8.pdf
    /// </summary>
    public static class JobAttributes
    {
        public const string CompressionSupplied = "compression-supplied";
        public const string Copies = DocumentAttributes.Copies;

        /// <summary>
        /// Indicates the actual value of copies printed from the job's PT.
        /// </summary>
        public const string CopiesActual = DocumentAttributes.Copies + "-actual";

        public const string CoverType = "cover-type";
        public const string DateTimeAtCompleted = "date-time-at-completed";
        public const string DateTimeAtCreation = "date-time-at-creation";
        public const string DateTimeAtProcessing = "date-time-at-processing";
        public const string DetailedStatusMessage = "detailed-status-message";
        public const string DocumentAccessError = "document-access-error";
        public const string DocumentFormatSupplied = "document-format-supplied";
        public const string DocumentFormatVersionSupplied = "document-format-version-supplied";
        public const string DocumentNameSupplied = "document-name-supplied";
        public const string FeedOrientation = DocumentAttributes.FeedOrientation;
        public const string Finishings = DocumentAttributes.Finishings;
        public const string FinishingsCol = DocumentAttributes.FinishingsCol;
        public const string IppAttributeFidelity = OperationAttributes.IppAttributeFidelity;
        public const string JobHoldUntil = "job-hold-until";
        public const string JobAccountId = "job-account-id";
        public const string JobAccountingUserId = "job-accounting-user-id";
        public const string JobId = OperationAttributes.JobId;
        public const string JobImpressions = "job-impressions";
        public const string JobImpressionsCompleted = "job-impressions-completed";
        public const string JobKOctets = "job-k-octets";
        public const string JobKOctetsCompleted = "job-k-octets-completed";
        public const string JobKOctetsProcessed = "job-k-octets-processed";
        public const string JobMandatoryAttributes = "job-mandatory-attributes";
        public const string JobMediaSheets = "job-media-sheets";
        public const string JobMediaSheetsCompleted = "job-media-sheets-completed";
        public const string JobMessageFromOperator = "job-message-from-operator";
        public const string JobMoreInfo = "job-more-info";
        public const string JobName = "job-name";
        public const string JobOriginatingUserName = "job-originating-user-name";
        public const string JobOriginatingUserUri = "job-originating-user-uri";
        public const string JobPagesCompleted = "job-pages-completed";
        public const string JobPagesPerSet = "job-pages-per-set";
        public const string JobPriority = "job-priority";
        public const string JobPrinterUpTime = "job-printer-up-time";
        public const string JobPrinterUri = "job-printer-uri";
        public const string JobReleaseAction = "job-release-action";
        public const string JobReleaseActionId = "job-release-action-id";
        public const string JobReleaseActionActual = "job-release-action-actual";
        public const string JobSheets = "job-sheets";
        public const string JobState = "job-state";
        public const string JobStateMessage = "job-state-message";
        public const string JobStateReasons = "job-state-reasons";
        public const string JobUuid = "job-uuid";
        public const string JobUri = OperationAttributes.JobUri;
        public const string Media = DocumentAttributes.Media;
        public const string MediaBackCoating = DocumentAttributes.MediaBackCoating;
        public const string MediaBottomMargin = DocumentAttributes.MediaBottomMargin;
        public const string MediaCol = DocumentAttributes.MediaCol;
        public const string MediaColor = DocumentAttributes.MediaColor;
        public const string MediaGrain = DocumentAttributes.MediaGrain;
        public const string MediaFrontCoating = DocumentAttributes.MediaFrontCoating;
        public const string MediaHoleCount = DocumentAttributes.MediaHoleCount;
        public const string MediaInfo = DocumentAttributes.MediaInfo;
        public const string MediaKey = DocumentAttributes.MediaKey;
        public const string MediaLeftMargin = DocumentAttributes.MediaLeftMargin;
        public const string MediaOrderCount = DocumentAttributes.MediaOrderCount;
        public const string MediaPreprinted = DocumentAttributes.MediaPreprinted;
        public const string MediaRecycled = DocumentAttributes.MediaRecycled;
        public const string MediaRightMargin = DocumentAttributes.MediaRightMargin;
        public const string MediaSize = DocumentAttributes.MediaSize;
        public const string MediaSizeName = DocumentAttributes.MediaSizeName;
        public const string MediaSource = DocumentAttributes.MediaSource;
        public const string MediaThickness = DocumentAttributes.MediaThickness;
        public const string MediaTooth = DocumentAttributes.MediaTooth;
        public const string MediaTopMargin = DocumentAttributes.MediaTopMargin;
        public const string MediaType = DocumentAttributes.MediaType;
        public const string MediaWeightMetric = DocumentAttributes.MediaWeightMetric;

        // Attribute extensions
        // See reference: https://tools.ietf.org/html/rfc8011#section-7.2

        /// <summary>
        /// Only used by the first party Connector.
        /// Indicates the time (in seconds) it took the Connector to fetch the print job.
        /// Excludes the time that the job spent waiting to be fetched,
        /// i.e. it is only the total time taken by Connector to perform the Acknowledge/Fetch-Job/Document operations.
        /// </summary>
        public const string MicrosoftJobFetchedTimeInSeconds = "microsoft-job-fetched-time-seconds";

        /// <summary>
        /// Only used by the first party Connector.
        /// Indicates the time (in seconds) it took for the print job to be processed by the Connector before the job was sent to the spooler.
        /// Excludes the time that was spent on fetching the job, i.e. timing starts after the Connector finished fetching the job.
        /// </summary>
        public const string MicrosoftJobProcessedTimeInSeconds = "microsoft-job-processed-time-seconds";

        /// <summary>
        /// Only used by the first party Connector before 2.2.
        /// Indicates the time (in seconds) that the job spent in the Windows spooler before being sent to the printer.
        /// Replaced by MicrosoftJobSpoolerTimeInSeconds to reduce confusion.
        /// </summary>
        public const string MicrosoftJobPrintedTimeInSeconds = "microsoft-job-printed-time-seconds";

        /// <summary>
        /// Only used by the first party Connector 2.2 and newer.
        /// Indicates the time (in seconds) that the job spent in the Windows spooler before being sent to the printer.
        /// </summary>
        public const string MicrosoftJobSpoolerTimeInSeconds = "microsoft-job-spooler-time-in-seconds";

        /// <summary>
        /// Only used by the first party Connector 2.2 and newer.
        /// Indicates the time (in seconds) that the job spent in the printer after being processed in the Windows spooler.
        /// </summary>
        public const string MicrosoftJobPrinterTimeInSeconds = "microsoft-job-printer-time-in-seconds";

        /// <summary>
        /// Indicates the time (in milliseconds) it took for converting a PDF format print job to XPS format by the printer.
        /// </summary>
        public const string MicrosoftPdfToXpsJobConversionTimeInMilliseconds = "microsoft-pdf-to-xps-job-conversion-time-milliseconds";

        /// <summary>
        /// Only used by the first party Connector.
        /// Indicates the time (in milliseconds) it took for the Connector to generate the print ticket that was sent to the spooler
        /// (i.e. time taken to transform and merge-and-validate the print ticket).
        /// </summary>
        public const string MicrosoftPrintTicketGenerationTimeInMilliseconds = "microsoft-print-ticket-generation-time-milliseconds";

        /// <summary>
        /// Indicates the extended (error code, message, etc) job state message from the printer.
        /// </summary>
        public const string MicrosoftOutputDeviceJobStateMessage = "microsoft-output-device-job-state-message";

        /// <summary>
        /// Only used by the first party Connector.
        /// Indicates the print ticket mappings generated from the printer's original PDC/PC.
        /// </summary>
        public const string MicrosoftPrintTicketGenerationMappings = "microsoft-print-ticket-generation-mappings";

        public const string MultipleDocumentHandling = "multiple-document-handling";
        public const string NumberOfDocuments = "number-of-documents";
        public const string NumberOfInterveningJobs = "number-of-intervening-jobs";
        public const string NumberUp = "number-up";
        public const string OrientationRequested = DocumentAttributes.OrientationRequested;
        public const string OutputBin = DocumentAttributes.OutputBin;
        public const string OutputDeviceAssigned = "output-device-assigned";
        public const string OutputDeviceJobState = "output-device-job-state";
        public const string OutputDeviceJobStateMessage = "output-device-job-state-message";
        public const string OutputDeviceJobStateReasons = "output-device-job-state-reasons";
        public const string OutputDeviceJobStates = "output-device-job-states";
        public const string Overrides = DocumentAttributes.Overrides;
        public const string PageRanges = DocumentAttributes.PageRanges;
        public const string PdfFitToPage = "pdf-fit-to-page";
        public const string PageOrderReceived = "page-order-received";
        public const string PresentationDirectionNumberUp = "presentation-direction-number-up";
        public const string PrintColorMode = DocumentAttributes.PrintColorMode;

        /// <summary>
        /// Indicates the actual value of print-color-mode from the job's PT.
        /// </summary>
        public const string PrintColorModeActual = DocumentAttributes.PrintColorMode + "-actual";

        public const string PrintScaling = "print-scaling";
        public const string PrintContentOptimize = DocumentAttributes.PrintContentOptimize;
        public const string PrintRenderingIntent = DocumentAttributes.PrintRenderingIntent;
        public const string PrinterQuality = "printer-quality";
        public const string PrinterResolution = DocumentAttributes.PrinterResolution;
        public const string PrintQuality = DocumentAttributes.PrintQuality;
        public const string Sides = DocumentAttributes.Sides;

        /// <summary>
        /// Indicates the actual value of sides printed from the job's PT.
        /// </summary>
        public const string SidesActual = DocumentAttributes.Sides + "-actual";

        public const string TimeAtCompleted = "time-at-completed";
        public const string TimeAtCreation = "time-at-creation";
        public const string TimeAtProcessing = "time-at-processing";
        public const string XDimension = DocumentAttributes.XDimension;
        public const string YDimension = DocumentAttributes.YDimension;

        /// <summary>
        /// The document numbers that the values passed in the "overrides"
        /// job attribute applies to. UP doesn't have multiple documents per job,
        /// but we still need to have this in "overrides-supported" to be conformant
        /// to AirPrint and IPP specs.
        /// Naming is non-standard because this is only permitted as an attribute
        /// inside the "overrides" collections.
        /// </summary>
        public const string OverridesDocumentNumbers = "document-numbers";

        /// <summary>
        /// The pages that the values passed in the "overrides" job attribute applies to.
        /// Naming is non-standard because this is only permitted as an attribute
        /// inside the "overrides" collections and because "pages" is a ubiquitous term.
        /// </summary>
        public const string OverridesPages = "pages";
    }
}