//-----------------------------------------------------------------------
// <copyright file="PrinterAttributes.cs" company="Microsoft">
// Copyright (c) Microsoft. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

// ReSharper disable once CheckNamespace
namespace BadgeReleaseDemo.IppLibrary.Common
{
    public static class PrinterAttributes
    {
        public const string CharsetConfigured = "charset-configured";
        public const string CharsetSupported = "charset-supported";
        public const string ColorSupported = "color-supported";
        public const string ColorModeSupported = "print-color-mode-supported";
        public const string ColorModeDefault = "print-color-mode-default";
        public const string CompressionSupported = "compression-supported";
        public const string CopiesDefault = "copies-default";
        public const string CopiesSupported = "copies-supported";
        public const string DocumentAccessSupported = "document-access-supported";
        public const string DocumentFormatDetailsSupported = "document-format-details-supported";
        public const string DocumentFormatDefault = "document-format-default";
        public const string DocumentFormatPreferred = "document-format-preferred";  // From Windows zero install impl (Mopria).
        public const string DocumentFormatSupported = "document-format-supported";
        public const string DocumentPasswordSupported = "document-password-supported";
        public const string FeedOrientationDefault = "feed-orientation-default";
        public const string FeedOrientationSupported = "feed-orientation-supported";
        public const string FinishingsColDatabase = "finishings-col-database";
        public const string FinishingsColDefault = "finishings-col-default";
        public const string FinishingsColReady = "finishings-col-ready";
        public const string FinishingsColSupported = "finishings-col-supported";
        public const string FinishingsDefault = "finishings-default";
        public const string FinishingsReady = "finishings-ready";
        public const string FinishingsSupported = "finishings-supported";
        public const string GeneratedNaturalLanguageSupported = "generated-natural-language-supported";
        public const string IdentifyActionsDefault = "identify-actions-default";
        public const string IdentifyActionsSupported = "identify-actions-supported";
        public const string IppFeaturesSupported = "ipp-features-supported";
        public const string IppVersionsSupported = "ipp-versions-supported";
        public const string IppgetEventLife = "ippget-event-life";
        public const string JobAccountIdDefault = "job-account-id-default";
        public const string JobAccountIdSupported = "job-account-id-supported";
        public const string JobAccountingUserIdDefault = "job-accounting-user-id-default";
        public const string JobAccountingUserIdSupported = "job-accounting-user-id-supported";
        public const string JobConstraintsSupported = "job-constraints-supported";
        public const string JobCreationAttributesSupported = "job-creation-attributes-supported";
        public const string JobIdsSupported = "job-ids-supported";
        public const string JobImpressionsSupported = "job-impressions-supported";
        public const string JobMandatoryAttributesSupported = "job-mandatory-attributes-supported";
        public const string JobMediaSheetsSupported = "job-media-sheets-supported";
        public const string JobPagesPerSetSupported = "job-pages-per-set-supported";
        public const string JobPasswordSupported = "job-password-supported";
        public const string JobPasswordEncryptionSupported = "job-password-encryption-supported";
        public const string JobPasswordLengthSupported = "job-password-length-supported";
        public const string JobReleaseActionDefault = "job-release-action-default";
        public const string JobReleaseActionSupported = "job-release-action-supported";
        public const string JobResolversSupported = "job-resolvers-supported";
        public const string JobSheetsDefault = "job-sheets-default";
        public const string JobSheetsSupported = "job-sheets-supported";
        public const string LandscapeOrientationRequestedPreferred = "landscape-orientation-requested-preferred";
        public const string MarginsPreAppliedDefault = "margins-pre-applied-default";
        public const string MarginsPreAppliedSupported = "margins-pre-applied-supported";
        public const string MediaBottomMarginSupported = "media-bottom-margin-supported";
        public const string MediaColDatabase = "media-col-database";
        public const string MediaColDefault = "media-col-default";
        public const string MediaColReady = "media-col-ready";
        public const string MediaColSupported = "media-col-supported";
        public const string MediaColorSupported = "media-color-supported";
        public const string MediaDefault = "media-default";
        public const string MediaLeftMarginSupported = "media-left-margin-supported";
        public const string MediaReady = "media-ready";
        public const string MediaRightMarginSupported = "media-right-margin-supported";
        public const string MediaSizeSupported = "media-size-supported";
        public const string MediaSourceDefault = "media-source-default";
        public const string MediaSourceFeedDirection = "media-source-feed-direction";
        public const string MediaSourceFeedOrientation = "media-source-feed-orientation";
        public const string MediaSourceProperties = "media-source-properties";
        public const string MediaSourceSupported = "media-source-supported";
        public const string MediaSupported = "media-supported";
        public const string MediaTopMargin = "media-top-margin";
        public const string MediaTopMarginSupported = "media-top-margin-supported";
        public const string MediaTypeSupported = "media-type-supported";
        public const string MopriaCertified = "mopria-certified";
        public const string MultipleDocumentHandlingDefault = "multiple-document-handling-default";
        public const string MultipleDocumentHandlingSupported = "multiple-document-handling-supported";
        public const string MultipleDocumentJobsSupported = "multiple-document-jobs-supported";
        public const string MultipleOperationTimeout = "multiple-operation-time-out";
        public const string MultipleOperationTimeoutAction = "multiple-operation-time-out-action";
        public const string NaturalLanguageConfigured = "natural-language-configured";
        public const string NumberUpDefault = "number-up-default";
        public const string NotifyPullMethodSupported = "notify-pull-method-supported";
        public const string NumberUpSupported = "number-up-supported";
        public const string OauthAuthorizationServerUri = "oauth-authorization-server-uri";
        public const string OperationsSupported = "operations-supported";
        public const string OrientationRequestedDefault = "orientation-requested-default";
        public const string OrientationRequestedSupported = "orientation-requested-supported";
        public const string OutputBinDefault = "output-bin-default";
        public const string OutputBinSupported = "output-bin-supported";
        public const string OverridesSupported = "overrides-supported";
        public const string PageRangesSupported = "page-ranges-supported";
        public const string PageColorModeDefault = "page-color-mode-default";
        public const string PageColorModeSupported = "page-color-mode-supported";
        public const string PageOrderReceivedSupported = "page-order-received-supported";
        public const string PageOrderReceivedDefault = "page-order-received-default";
        public const string PagesPerMinute = "pages-per-minute";
        public const string PagesPerMinuteColor = "pages-per-minute-color";
        public const string PclmRasterBackSide = "pclm-raster-back-side";
        public const string PclmSourceResolutionSupported = "pclm-source-resolution-supported";
        public const string PclmStripHeightPreferred = "pclm-strip-height-preferred";
        public const string PclmStripHeightSupported = "pclm-strip-height-supported";
        public const string PdlOverrideSupported = "pdl-override-supported";
        public const string PdfFitToPageDefault = "pdf-fit-to-page-default";        // from Windows zero install impl (Mopria).
        public const string PdfFitToPageSupported = "pdf-fit-to-page-supported";    // from Windows zero install impl (Mopria).
        public const string PdfKOctetsSupported = "pdf-k-octets-supported";
        public const string PdfSizeConstraints = "pdf-size-constraints";
        public const string PdfVersionsSupported = "pdf-versions-supported";
        public const string PresentationDirectionNumberUpDefault = "presentation-direction-number-up-default";
        public const string PresentationDirectionNumberUpSupported = "presentation-direction-number-up-supported";
        public const string PrinterConfigChangeTime = "printer-config-change-time";
        public const string PrinterConfigChangeDateTime = "printer-config-change-date-time";
        public const string PrintColorModeDefault = "print-color-mode-default";
        public const string PrintColorModeSupported = "print-color-mode-supported";
        public const string PrintContentOptimizeDefault = "print-content-optimize-default";
        public const string PrintContentOptimizeSupported = "print-content-optimize-supported";
        public const string PrintRenderingIntentDefault = "print-rendering-intent-default";
        public const string PrintRenderingIntentSupported = "print-rendering-intent-supported";
        public const string PrintQualityDefault = "print-quality-default";
        public const string PrintQualitySupported = "print-quality-supported";
        public const string PrintScalingDefault = "print-scaling-default";
        public const string PrintScalingSupported = "print-scaling-supported";
        public const string PrinterAlert = "printer-alert";
        public const string PrinterAlertDescription = "printer-alert-description";
        public const string PrinterCurrentTime = "printer-current-time";
        public const string PrinterDeviceId = "printer-device-id";
        public const string PrinterFirmwareName = "printer-firmware-name";
        public const string PrinterFirmwarePatches = "printer-firmware-patches";
        public const string PrinterFirmwareStringVersion = "printer-firmware-string-version";
        public const string PrinterFirmwareVersion = "printer-firmware-version";
        public const string PrinterGeoLocation = "printer-geo-location";
        public const string PrinterGetAttributesSupported = "printer-get-attributes-supported";
        public const string PrinterIccProfiles = "printer-icc-profiles";
        public const string PrinterIcons = "printer-icons";
        public const string PrinterInfo = "printer-info";
        public const string PrinterInputTray = "printer-input-tray";
        public const string PrinterIsAcceptingJobs = "printer-is-accepting-jobs";
        public const string PrinterKind = "printer-kind";
        public const string PrinterLocation = "printer-location";
        public const string PrinterMakeAndModel = "printer-make-and-model";
        public const string PrinterMoreInfo = "printer-more-info";
        public const string PrinterMoreInfoManufacturer = "printer-more-info-manufacturer";
        public const string PrinterName = "printer-name";
        public const string PrinterOrganization = "printer-organization";
        public const string PrinterOrganizationalUnit = "printer-organizational-unit";
        public const string PrinterOutputTray = "printer-output-tray";
        public const string PrinterResolutionDefault = "printer-resolution-default";
        public const string PrinterResolutionSupported = "printer-resolution-supported";
        public const string PrinterState = "printer-state";
        public const string PrinterStateChangeDateTime = "printer-state-change-date-time";
        public const string PrinterStateChangeTime = "printer-state-change-time";
        public const string PrinterStateChangeMessage = "printer-state-change-message";
        public const string PrinterStateMessage = "printer-state-message";
        public const string PrinterStateReasons = "printer-state-reasons";
        public const string PrinterStaticResourceDirectoryUri = "printer-static-resource-directory-uri";
        public const string PrinterStaticResourceKOctetsFree = "printer-static-resource-k-octets-free";
        public const string PrinterStaticResourceKOctetsSupported = "printer-static-resource-k-octets-supported";
        public const string PrinterSupply = "printer-supply";
        public const string PrinterSupplyDescription = "printer-supply-description";
        public const string PrinterSupplyInfoUri = "printer-supply-info-uri";
        public const string PrinterUpTime = "printer-up-time";
        public const string PrinterUriSupported = "printer-uri-supported";
        public const string PrinterUuid = "printer-uuid";
        public const string PwgRasterDocumentResolutionSupported = "pwg-raster-document-resolution-supported";
        public const string PwgRasterDocumentSheetBack = "pwg-raster-document-sheet-back";
        public const string PwgRasterDocumentTypeSupported = "pwg-raster-document-type-supported";
        public const string QueuedJobCount = "queued-job-count";
        public const string SidesDefault = "sides-default";
        public const string SidesSupported = "sides-supported";
        public const string UrfSupported = "urf-supported";
        public const string UriSecuritySupported = "uri-security-supported";
        public const string UriAuthenticationSupported = "uri-authentication-supported";
        public const string WhichJobsSupported = "which-jobs-supported";
        public const string PreferredChunkSizeKOctets = "preferred-chunk-size-k-octets";

        // Attribute extensions
        // See reference: https://tools.ietf.org/html/rfc8011#section-7.2
        public const string MicrosoftPageOrderDefault = "microsoft-page-order-default";
        public const string MicrosoftPageOrderSupported = "microsoft-page-order-supported";
        public const string MicrosoftUniversalPrintConnectorAppVersion = "microsoft-universal-print-connector-app-version";
        public const string MicrosoftUniversalPrintConnectorOperatingSystem = "microsoft-universal-print-connector-operating-system";
        public const string MicrosoftUniversalPrintConnectorId = "microsoft-universal-print-connector-id";
        public const string MicrosoftUniversalPrinterDriverName = "microsoft-universal-printer-driver-name";
        public const string MicrosoftUniversalPrinterDriverVersion = "microsoft-universal-printer-driver-version";
        public const string MicrosoftUniversalPrintDocumentFormatSupportedViaConversion = "microsoft-universal-print-document-format-supported-via-conversion";

        // smi attributes
        public const string PullPrintEnabledWithOEMJobRelease = "smi311-universal-print-anywhere-enabled";

        // Custom Windows extensions
        public const string PrintDeviceCapabilities = "print-device-capabilites"; // Universal Print connector sends printer's PDC.
        public const string PrintDeviceResources = "print-device-resources";

        // CUPS Printer Attributes. (Optional for Mopria 2.0 support)
        // Ref: Mopria 2.0 spec Section 4.14
        // https://microsoft.sharepoint.com/:b:/t/STACKTeam-CoreNetworkingMobileConnectivityPeripheralsStackSe/EYP81I7FD95JiQdMtD14FlEBMHbF1pbe_1aYO9kPVN-w-w?e=rJxA7L
        // CUPS spec: https://www.cups.org/doc/spec-ipp.html
        public const string MarkerColors = "marker-colors";
        public const string MarkerHighLevels = "marker-high-levels";
        public const string MarkerLevels = "marker-levels";
        public const string MarkerLowLevels = "marker-low-levels";
        public const string MarkerNames = "marker-names";
        public const string MarkerTypes = "marker-types";

        // Ref: Mopria 2.0 Section 4.5.1
        // https://microsoft.sharepoint.com/:b:/t/STACKTeam-CoreNetworkingMobileConnectivityPeripheralsStackSe/EYP81I7FD95JiQdMtD14FlEBMHbF1pbe_1aYO9kPVN-w-w?e=rJxA7L
        public const string PrintWFDS = "print_wfds";
    }
}