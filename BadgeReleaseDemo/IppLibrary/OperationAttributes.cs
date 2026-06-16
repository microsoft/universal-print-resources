//-----------------------------------------------------------------------
// <copyright file="OperationAttributes.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

// ReSharper disable once CheckNamespace
namespace BadgeReleaseDemo.IppLibrary.Common
{
    public static class OperationAttributes
    {
        public const string AttributesCharset = "attributes-charset";
        public const string AttributesNaturalLanguage = "attributes-natural-language";
        public const string Compression = "compression";
        public const string CompressionAccepted = "compression-accepted"; // IPP Infra
        public const string DetailedStatusMessage = "detailed-status-message";
        public const string DocumentAccess = "document-access";
        public const string DocumentFormat = "document-format";
        public const string DocumentFormatAccepted = "document-format-accepted";
        public const string DocumentFormatDetails = "document-format-details";
        public const string DocumentFormatName = "document-format-name";
        public const string DocumentName = "document-name";
        public const string DocumentNumber = "document-number";
        public const string DocumentPassword = "document-password";
        public const string DocumentPreprocessed = "document-preprocessed";
        public const string DocumentUri = "document-uri";
        public const string FetchStatusCode = "fetch-status-code";
        public const string FetchStatusMessage = "fetch-status-message";
        public const string FirstIndex = "first-index";
        public const string IdentifyActions = "identify-actions";
        public const string IppAttributeFidelity = "ipp-attribute-fidelity";
        public const string JobId = "job-id";
        public const string JobIds = "job-ids";
        public const string JobImpressions = "job-impressions";
        public const string JobMandatoryAttributes = "job-mandatory-attributes";
        public const string JobName = "job-name";
        public const string JobPassword = "job-password";
        public const string JobPasswordEncryption = "job-password-encryption";
        public const string JobUri = "job-uri";
        public const string LastDocument = "last-document";
        public const string Limit = "limit";
        public const string MyJobs = "my-jobs";
        public const string NotifyGetInterval = "notify-get-interval";
        public const string NotifySequenceNumbers = "notify-sequence-numbers";
        public const string NotifySubscriptionId = "notify-subscription-id";
        public const string NotifySubscriptionIds = "notify-subscription-ids";
        public const string NotifyWait = "notify-wait";
        public const string OutputDeviceJobState = JobAttributes.OutputDeviceJobState;
        public const string OutputDeviceJobStates = JobAttributes.OutputDeviceJobStates;
        public const string OutputDeviceUuid = "output-device-uuid";
        public const string PrinterUpTime = "printer-up-time";
        public const string PrinterUri = "printer-uri";
        public const string RequestedAttributes = "requested-attributes";
        public const string RequestingUserName = "requesting-user-name";
        public const string RequestingUserUri = "requesting-user-uri";
        public const string StatusMessage = "status-message";
        public const string WhichJobs = "which-jobs";
        public const string ContentRange = "content-range";
    }
}