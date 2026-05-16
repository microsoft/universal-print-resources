//-----------------------------------------------------------------------
// <copyright file="IPPTemplates.cs" company="Microsoft">
// Copyright (c) Microsoft. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

namespace BadgeReleaseDemo.IppLibrary.Common
{
    using System.Collections.Generic;

    public static class IppTemplates
    {
        /// <summary>
        /// Gets a list of all supported template attributes applicable to a job
        /// (as returned by get-job-attributes or get-jobs in a request for 'all' attributes)
        /// https://tools.ietf.org/html/rfc8011#section-5.2 and
        /// http://ftp.pwg.org/pub/pwg/candidates/cs-ippinfra10-20150619-5100.18.pdf section 4.16.
        /// </summary>
        public static string[] JobTemplateAttributes { get; } =
        {
            JobAttributes.Copies,
            JobAttributes.Finishings,
            JobAttributes.JobAccountId,
            JobAttributes.JobAccountingUserId,
            JobAttributes.JobPriority,
            JobAttributes.JobHoldUntil,
            JobAttributes.JobSheets,
            JobAttributes.Media,
            JobAttributes.MultipleDocumentHandling,
            JobAttributes.NumberUp,
            JobAttributes.OrientationRequested,
            JobAttributes.PageRanges,
            JobAttributes.PresentationDirectionNumberUp,
            JobAttributes.PdfFitToPage,
            JobAttributes.PrintScaling,
            JobAttributes.PrinterResolution,
            JobAttributes.PrinterQuality,
            JobAttributes.Sides,

            // https://ftp.pwg.org/pub/pwg/candidates/cs-ippjobprinterext3v10-20120727-5100.13.pdf#page=30
            JobAttributes.JobOriginatingUserName,
            JobAttributes.JobOriginatingUserUri,

            // INFRA only
            JobAttributes.FeedOrientation,
            JobAttributes.FinishingsCol,
            JobAttributes.MediaCol,
            JobAttributes.MediaBottomMargin,
            JobAttributes.MediaLeftMargin,
            JobAttributes.MediaRightMargin,
            JobAttributes.MediaSize,
            JobAttributes.MediaSource,
            JobAttributes.MediaTopMargin,
            JobAttributes.MediaType,
            JobAttributes.OutputBin,
            JobAttributes.Overrides,
            JobAttributes.PrintColorMode,
            JobAttributes.PrintContentOptimize,
            JobAttributes.PrintRenderingIntent,
            JobAttributes.PrintQuality,
            JobAttributes.PrinterResolution
        };

        /// <summary>
        /// Gets a list of document attributes defined as document template attributes in IPP Infra spec.
        /// http://ftp.pwg.org/pub/pwg/candidates/cs-ippinfra10-20150619-5100.18.pdf section 4.12.
        /// </summary>
        public static string[] DocumentTemplateAttributes { get; } =
        {
            DocumentAttributes.Copies,
            DocumentAttributes.FeedOrientation,
            DocumentAttributes.Finishings,
            DocumentAttributes.FinishingsCol,
            DocumentAttributes.Media,
            DocumentAttributes.MediaCol,
            DocumentAttributes.MediaBottomMargin,
            DocumentAttributes.MediaLeftMargin,
            DocumentAttributes.MediaRightMargin,
            DocumentAttributes.MediaSize,
            DocumentAttributes.MediaSource,
            DocumentAttributes.MediaTopMargin,
            DocumentAttributes.MediaType,
            DocumentAttributes.OrientationRequested,
            DocumentAttributes.OutputBin,
            DocumentAttributes.Overrides,
            DocumentAttributes.PageRanges,
            DocumentAttributes.PrintColorMode,
            DocumentAttributes.PrintContentOptimize,
            DocumentAttributes.PrintRenderingIntent,
            DocumentAttributes.PrintQuality,
            DocumentAttributes.PrinterResolution,
            DocumentAttributes.Sides
        };

        /// <summary>
        /// Gets a list of job description attributes defined in:
        /// IPP INFRA: http://ftp.pwg.org/pub/pwg/candidates/cs-ippinfra10-20150619-5100.18.pdf section 4.14.
        /// IPP: https://tools.ietf.org/html/rfc8011#section-5.3.
        /// </summary>
        public static string[] JobDescriptionAttributes { get; } =
        {
            JobAttributes.JobImpressions,
            JobAttributes.JobImpressionsCompleted,
            JobAttributes.JobKOctets,
            JobAttributes.JobMediaSheets,
            JobAttributes.JobName,
            JobAttributes.JobStateReasons,
            JobAttributes.JobState,
            JobAttributes.JobName,
            JobAttributes.JobOriginatingUserName
        };

        /// <summary>
        /// Gets a list of job status attributes defined in
        /// IPP INFRA: http://ftp.pwg.org/pub/pwg/candidates/cs-ippinfra10-20150619-5100.18.pdf section 4.15. and
        /// IPP: https://tools.ietf.org/html/rfc8011#section-5.3.
        /// </summary>
        public static string[] JobStatusAttributes { get; } =
        {
            JobAttributes.CompressionSupplied,
            JobAttributes.DateTimeAtCompleted,
            JobAttributes.DateTimeAtCreation,
            JobAttributes.DateTimeAtProcessing,
            JobAttributes.DocumentFormatSupplied,
            JobAttributes.DocumentFormatVersionSupplied,
            JobAttributes.DocumentNameSupplied,
            JobAttributes.JobId,
            JobAttributes.JobImpressionsCompleted,
            JobAttributes.JobOriginatingUserName,
            JobAttributes.JobPrinterUpTime,
            JobAttributes.JobPrinterUri,
            JobAttributes.JobReleaseAction,
            JobAttributes.JobReleaseActionActual,
            JobAttributes.JobReleaseActionId,
            JobAttributes.JobState,
            JobAttributes.JobStateMessage,
            JobAttributes.JobStateReasons,
            OperationAttributes.JobUri,
            JobAttributes.JobUuid,
            JobAttributes.TimeAtCompleted,
            JobAttributes.TimeAtCreation,

            // IPP only.
            JobAttributes.DateTimeAtProcessing,
            JobAttributes.DateTimeAtCompleted,
            JobAttributes.DateTimeAtCreation,
            JobAttributes.DetailedStatusMessage,
            JobAttributes.DocumentAccessError,
            JobAttributes.JobKOctetsProcessed,
            JobAttributes.JobMediaSheetsCompleted,
            JobAttributes.JobMessageFromOperator,
            JobAttributes.JobMoreInfo,
            JobAttributes.NumberOfDocuments,
            JobAttributes.NumberOfInterveningJobs,
            JobAttributes.OutputDeviceAssigned,
            JobAttributes.TimeAtCreation
        };

        /// <summary>
        /// Gets a list of document status attributes defined in:
        /// http://ftp.pwg.org/pub/pwg/candidates/cs-ippinfra10-20150619-5100.18.pdf section 4.11.
        /// </summary>
        public static string[] DocumentStatusAttributes { get; } =
        {
            OperationAttributes.AttributesCharset,
            OperationAttributes.AttributesNaturalLanguage,
            OperationAttributes.Compression,
            DocumentAttributes.DateTimeAtCompleted,
            JobAttributes.DateTimeAtCreation,
            JobAttributes.DateTimeAtProcessing,
            OperationAttributes.DocumentFormat,
            DocumentAttributes.DocumentJobId,
            OperationAttributes.DocumentNumber,
            DocumentAttributes.DocumentPrinterUri,
            DocumentAttributes.DocumentState,
            DocumentAttributes.DocumentStateMessage,
            DocumentAttributes.DocumentStateReasons,
            OperationAttributes.DocumentUri,
            DocumentAttributes.DocumentUuid,
            DocumentAttributes.ImpressionsCompleted,
            DocumentAttributes.LastDocument,
            OperationAttributes.PrinterUpTime,
            JobAttributes.TimeAtCompleted,
            JobAttributes.TimeAtCreation,
            JobAttributes.TimeAtProcessing
        };

        /// <summary>
        /// Gets a list of printer description attributes.
        /// RFC 8011: Printer attributes are divided into 2 groups.
        /// "job-template" and "printer-description" attributes.
        /// Here's the list for the printer-description attributes.
        /// </summary>
        public static string[] PrinterDescriptionAttributes { get; } =
        {
            PrinterAttributes.CharsetConfigured,
            PrinterAttributes.CharsetSupported,
            PrinterAttributes.ColorSupported,
            PrinterAttributes.ColorModeSupported,
            PrinterAttributes.ColorModeDefault,
            PrinterAttributes.CompressionSupported,
            PrinterAttributes.CopiesDefault,
            PrinterAttributes.CopiesSupported,
            PrinterAttributes.DocumentAccessSupported,
            PrinterAttributes.DocumentFormatDefault,
            PrinterAttributes.DocumentFormatDetailsSupported,
            PrinterAttributes.DocumentFormatSupported,
            PrinterAttributes.DocumentPasswordSupported,
            PrinterAttributes.FeedOrientationDefault,
            PrinterAttributes.FeedOrientationSupported,
            PrinterAttributes.FinishingsColDatabase,
            PrinterAttributes.FinishingsColDefault,
            PrinterAttributes.FinishingsColReady,
            PrinterAttributes.FinishingsColSupported,
            PrinterAttributes.FinishingsDefault,
            PrinterAttributes.FinishingsReady,
            PrinterAttributes.FinishingsSupported,
            PrinterAttributes.GeneratedNaturalLanguageSupported,
            PrinterAttributes.IdentifyActionsDefault,
            PrinterAttributes.IdentifyActionsSupported,
            PrinterAttributes.IppFeaturesSupported,
            PrinterAttributes.IppVersionsSupported,
            PrinterAttributes.IppgetEventLife,
            PrinterAttributes.JobAccountIdDefault,
            PrinterAttributes.JobAccountIdSupported,
            PrinterAttributes.JobAccountingUserIdDefault,
            PrinterAttributes.JobAccountingUserIdSupported,
            PrinterAttributes.JobConstraintsSupported,
            PrinterAttributes.JobCreationAttributesSupported,
            PrinterAttributes.JobIdsSupported,
            PrinterAttributes.JobImpressionsSupported,
            PrinterAttributes.JobMandatoryAttributesSupported,
            PrinterAttributes.JobMediaSheetsSupported,
            PrinterAttributes.JobPagesPerSetSupported,
            PrinterAttributes.JobPasswordEncryptionSupported,
            PrinterAttributes.JobPasswordSupported,
            PrinterAttributes.JobPasswordLengthSupported,
            PrinterAttributes.JobReleaseActionDefault,
            PrinterAttributes.JobReleaseActionSupported,
            PrinterAttributes.JobResolversSupported,
            PrinterAttributes.MarginsPreAppliedDefault,
            PrinterAttributes.MarginsPreAppliedSupported,
            PrinterAttributes.MediaBottomMarginSupported,
            PrinterAttributes.MediaColDatabase,
            PrinterAttributes.MediaColDefault,
            PrinterAttributes.MediaColReady,
            PrinterAttributes.MediaColSupported,
            PrinterAttributes.MediaDefault,
            PrinterAttributes.MediaLeftMarginSupported,
            PrinterAttributes.MediaReady,
            PrinterAttributes.MediaRightMarginSupported,
            PrinterAttributes.MediaSizeSupported,
            PrinterAttributes.MediaSourceProperties,
            PrinterAttributes.MediaSourceSupported,
            PrinterAttributes.MediaSupported,
            PrinterAttributes.MediaTopMarginSupported,
            PrinterAttributes.MediaTypeSupported,
            PrinterAttributes.MediaColorSupported,
            PrinterAttributes.MicrosoftPageOrderDefault,
            PrinterAttributes.MicrosoftPageOrderSupported,
            PrinterAttributes.MicrosoftUniversalPrintConnectorAppVersion,
            PrinterAttributes.MicrosoftUniversalPrintConnectorOperatingSystem,
            PrinterAttributes.MicrosoftUniversalPrintConnectorId,
            PrinterAttributes.MicrosoftUniversalPrinterDriverName,
            PrinterAttributes.MicrosoftUniversalPrinterDriverVersion,
            PrinterAttributes.MicrosoftUniversalPrintDocumentFormatSupportedViaConversion,
            PrinterAttributes.MopriaCertified,
            PrinterAttributes.MultipleDocumentHandlingDefault,
            PrinterAttributes.MultipleDocumentHandlingSupported,
            PrinterAttributes.MultipleDocumentJobsSupported,
            PrinterAttributes.MultipleOperationTimeout,
            PrinterAttributes.MultipleOperationTimeoutAction,
            PrinterAttributes.NaturalLanguageConfigured,
            PrinterAttributes.NotifyPullMethodSupported,
            PrinterAttributes.NumberUpDefault,
            PrinterAttributes.NumberUpSupported,
            PrinterAttributes.OauthAuthorizationServerUri,
            PrinterAttributes.OperationsSupported,
            PrinterAttributes.OrientationRequestedDefault,
            PrinterAttributes.OrientationRequestedSupported,
            PrinterAttributes.OutputBinDefault,
            PrinterAttributes.OutputBinSupported,
            PrinterAttributes.OverridesSupported,
            PrinterAttributes.PageRangesSupported,
            PrinterAttributes.PageColorModeDefault,
            PrinterAttributes.PageColorModeSupported,
            PrinterAttributes.PclmRasterBackSide,
            PrinterAttributes.PclmSourceResolutionSupported,
            PrinterAttributes.PclmStripHeightPreferred,
            PrinterAttributes.PclmStripHeightSupported,
            PrinterAttributes.PdfFitToPageDefault,
            PrinterAttributes.PdfFitToPageSupported,
            PrinterAttributes.PdfKOctetsSupported,
            PrinterAttributes.PdfSizeConstraints,
            PrinterAttributes.PdfVersionsSupported,
            PrinterAttributes.PdlOverrideSupported,
            PrinterAttributes.PresentationDirectionNumberUpDefault,
            PrinterAttributes.PresentationDirectionNumberUpSupported,
            PrinterAttributes.PrintContentOptimizeDefault,
            PrinterAttributes.PrintContentOptimizeSupported,
            PrinterAttributes.PrintRenderingIntentDefault,
            PrinterAttributes.PrintRenderingIntentSupported,
            PrinterAttributes.PrintQualityDefault,
            PrinterAttributes.PrintQualitySupported,
            PrinterAttributes.PrintScalingDefault,
            PrinterAttributes.PrintScalingSupported,
            PrinterAttributes.PrintWFDS,
            PrinterAttributes.PrinterDeviceId,
            PrinterAttributes.PrinterGeoLocation,
            PrinterAttributes.PrinterGetAttributesSupported,
            PrinterAttributes.PrinterIccProfiles,
            PrinterAttributes.PrinterIcons,
            PrinterAttributes.PrinterInfo,
            PrinterAttributes.PrinterKind,
            PrinterAttributes.PrinterLocation,
            PrinterAttributes.PrinterMakeAndModel,
            PrinterAttributes.PrinterMoreInfoManufacturer,
            PrinterAttributes.PrinterName,
            PrinterAttributes.PrinterOrganization,
            PrinterAttributes.PrinterOrganizationalUnit,
            PrinterAttributes.PrinterOutputTray,
            PrinterAttributes.PrinterResolutionDefault,
            PrinterAttributes.PrinterResolutionSupported,
            PrinterAttributes.PrinterStaticResourceDirectoryUri,
            PrinterAttributes.PrinterStaticResourceKOctetsSupported,
            PrinterAttributes.PrinterSupplyInfoUri,
            PrinterAttributes.PrinterUriSupported,
            PrinterAttributes.PwgRasterDocumentResolutionSupported,
            PrinterAttributes.PwgRasterDocumentSheetBack,
            PrinterAttributes.PwgRasterDocumentTypeSupported,
            PrinterAttributes.SidesDefault,
            PrinterAttributes.SidesSupported,
            PrinterAttributes.WhichJobsSupported,
        };

        /// <summary>
        /// Gets the list of printer status attributes.
        /// </summary>
        public static string[] PrinterStatusAttributes { get; } =
        {
            PrinterAttributes.LandscapeOrientationRequestedPreferred,
            PrinterAttributes.PagesPerMinute,
            PrinterAttributes.PagesPerMinuteColor,
            PrinterAttributes.PrinterAlert,
            PrinterAttributes.PrinterAlertDescription,
            PrinterAttributes.PrinterConfigChangeDateTime,
            PrinterAttributes.PrinterConfigChangeTime,
            PrinterAttributes.PrinterCurrentTime,
            PrinterAttributes.PrinterFirmwareName,
            PrinterAttributes.PrinterFirmwarePatches,
            PrinterAttributes.PrinterFirmwareStringVersion,
            PrinterAttributes.PrinterFirmwareVersion,
            PrinterAttributes.PrinterIsAcceptingJobs,
            PrinterAttributes.PrinterMoreInfo,
            PrinterAttributes.PrinterState,
            PrinterAttributes.PrinterStateMessage,
            PrinterAttributes.PrinterStateReasons,
            PrinterAttributes.PrinterStateChangeDateTime,
            PrinterAttributes.PrinterStateChangeTime,
            PrinterAttributes.PrinterStateChangeMessage,
            PrinterAttributes.PrinterStaticResourceKOctetsFree,
            PrinterAttributes.PrinterSupply,
            PrinterAttributes.PrinterSupplyDescription,
            PrinterAttributes.PrinterSupplyInfoUri,
            PrinterAttributes.PrinterUpTime,
            PrinterAttributes.PrinterUriSupported,
            PrinterAttributes.PrinterUuid,
            PrinterAttributes.UrfSupported,
            PrinterAttributes.UriSecuritySupported,
            PrinterAttributes.UriAuthenticationSupported,

            // CUPS IPP Printer Status Attributes (Optional for Mopria 2.0 support)
            PrinterAttributes.MarkerColors,
            PrinterAttributes.MarkerHighLevels,
            PrinterAttributes.MarkerLevels,
            PrinterAttributes.MarkerLowLevels,
            PrinterAttributes.MarkerNames,
            PrinterAttributes.MarkerTypes,
        };

        public static HashSet<string> PrinterDescriptionAttributesAutoPopulatedByService { get; } = new HashSet<string>()
        {
            PrinterAttributes.IppFeaturesSupported,
            PrinterAttributes.IppVersionsSupported,
            PrinterAttributes.JobCreationAttributesSupported,
            PrinterAttributes.JobImpressionsSupported,
            PrinterAttributes.JobMediaSheetsSupported,
            PrinterAttributes.JobPagesPerSetSupported,
            PrinterAttributes.MultipleDocumentJobsSupported,
            PrinterAttributes.MultipleOperationTimeout,
            PrinterAttributes.MultipleOperationTimeoutAction,
            PrinterAttributes.OperationsSupported,
            PrinterAttributes.PrinterDeviceId,
            PrinterAttributes.PrinterGeoLocation,
            PrinterAttributes.PrinterIcons,
            PrinterAttributes.PrinterLocation,
            PrinterAttributes.PrinterMoreInfo,
            PrinterAttributes.PrinterName,
            PrinterAttributes.PrinterOrganization,
            PrinterAttributes.PrinterOrganizationalUnit,
            PrinterAttributes.PrinterSupplyInfoUri,
            PrinterAttributes.PrinterUriSupported,
            PrinterAttributes.PrinterUuid,
            PrinterAttributes.UriAuthenticationSupported,
            PrinterAttributes.UriSecuritySupported
        };

        /// <summary>
        /// Must have attributes.
        /// </summary>
        public static class RequiredAttributes
        {
            public const string AttributesCharset = OperationAttributes.AttributesCharset;
            public const string AttributesNaturalLanguage = OperationAttributes.AttributesNaturalLanguage;
        }

        /// <summary>
        /// Special set of requested attributes.
        /// </summary>
        public static class RequestedAttributes
        {
            public const string All = "all";
            public const string JobTemplate = "job-template";
            public const string JobDescription = "job-description";
            public const string PrinterDescription = "printer-description";
        }

        public static HashSet<string> GetMopriaRequiredPrinterDescriptionAttributes(IppAttribute documentFormatSupportedAttribute)
        {
            var printerDescriptionAttributesRequiredByMopria = new HashSet<string>
            {
                PrinterAttributes.CharsetConfigured,
                PrinterAttributes.CharsetSupported,
                PrinterAttributes.CopiesDefault,
                PrinterAttributes.CopiesSupported,
                PrinterAttributes.DocumentFormatDefault,
                PrinterAttributes.DocumentFormatSupported,
                PrinterAttributes.FinishingsDefault,
                PrinterAttributes.FinishingsSupported,
                PrinterAttributes.GeneratedNaturalLanguageSupported,
                PrinterAttributes.IppFeaturesSupported,
                PrinterAttributes.IppVersionsSupported,
                PrinterAttributes.MediaColDatabase,
                PrinterAttributes.MediaColDefault,
                PrinterAttributes.MediaColSupported,
                PrinterAttributes.MediaSupported,
                PrinterAttributes.MediaTypeSupported,
                PrinterAttributes.NaturalLanguageConfigured,
                PrinterAttributes.OperationsSupported,
                PrinterAttributes.OrientationRequestedDefault,
                PrinterAttributes.OrientationRequestedSupported,
                PrinterAttributes.OutputBinDefault,
                PrinterAttributes.OutputBinSupported,
                PrinterAttributes.PrintColorModeDefault,
                PrinterAttributes.PrintColorModeSupported,
                PrinterAttributes.PrintQualityDefault,
                PrinterAttributes.PrintQualitySupported,
                PrinterAttributes.PrinterIsAcceptingJobs,
                PrinterAttributes.PrinterLocation,
                PrinterAttributes.PrinterMakeAndModel,
                PrinterAttributes.PrinterMoreInfo,
                PrinterAttributes.PrinterResolutionDefault,
                PrinterAttributes.PrinterResolutionSupported,
                PrinterAttributes.PrinterState,
                PrinterAttributes.PrinterStateReasons,
                PrinterAttributes.PrinterUriSupported,
                PrinterAttributes.SidesDefault,
                PrinterAttributes.SidesSupported,
                PrinterAttributes.UriSecuritySupported
            };

            if (documentFormatSupportedAttribute != null && documentFormatSupportedAttribute.Values != null)
            {
                foreach (var value in documentFormatSupportedAttribute.Values)
                {
                    switch (value.GetNativeValue<string>())
                    {
                        case Constants.DocumentFormatPdf:
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.PdfKOctetsSupported);
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.PdfVersionsSupported);
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.PrintScalingDefault);
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.PrintScalingSupported);
                            break;

                        case Constants.DocumentFormatPclm:
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.PageRangesSupported);
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.PclmRasterBackSide);
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.PclmSourceResolutionSupported);
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.PclmStripHeightPreferred);
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.PclmStripHeightSupported);
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.MarginsPreAppliedDefault);
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.MarginsPreAppliedSupported);
                            break;

                        case Constants.DocumentFormatPwgRaster:
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.PwgRasterDocumentResolutionSupported);
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.PwgRasterDocumentSheetBack);
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.PwgRasterDocumentTypeSupported);
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.PrintScalingDefault);
                            printerDescriptionAttributesRequiredByMopria.Add(PrinterAttributes.PrintScalingSupported);
                            break;

                        default:
                            break;
                    }
                }
            }

            return printerDescriptionAttributesRequiredByMopria;
        }
    }
}
