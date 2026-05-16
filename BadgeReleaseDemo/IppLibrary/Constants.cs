//-----------------------------------------------------------------------
// <copyright file="Constants.cs" company="Microsoft">
// Copyright (c) Microsoft. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

// ReSharper disable once CheckNamespace
namespace BadgeReleaseDemo.IppLibrary.Common
{
    public static class Constants
    {
        public const string IppV10 = "1.0";
        public const string IppV11 = "1.1";
        public const string IppV20 = "2.0";
        public const string MopriaDiscoveryV10 = "1.0";
        public const string ConfigurationRegistryKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\CloudPrint\EnterpriseCloudPrintService";
        public const string LocalSpoolerLayer = "localspl";
        public const string CharSet = "utf-8";
        public const string DocumentFormatPdf = "application/pdf";
        public const string DocumentFormatPwgRaster = "image/pwg-raster";
        public const string DocumentFormatPclm = "application/PCLm";
        public const string DocumentFormatOxps = "application/oxps";
        public const string DocumentFormatUrf = "image/urf";
        public const string DocumentFormatOctetStream = "application/octet-stream";
        public const string UnsupportedAttribute = "unsupported";
        public const string CompressionNone = "none";
        public const string JobsCompleted = "completed";            // Value for WhichJobs attribute.
        public const string JobsNotCompleted = "not-completed";     // Value for WhichJobs attribute.
        public const string JobFetchable = "fetchable";             // Value for WhichJobs attribute (IPP-INFRA).
        public const string Attempted = "attempted";
        public const string NotAttempted = "not-attempted";
        public const int ShortStringLength = 127;               // 127 octets maximum for text (127), name (127) attributes (RFC 2911 4.1.1)
        public const int MaxTextLength = 1023;                  // 1023 octets maximum for text (MAX) attributes (RFC 2911 4.1.1)
        public const int MaxNameLength = 255;                   // 255 octets maximum for name (MAX) attributes (RFC 2911 4.1.2)
        public const int MaxUriLength = 1023;                   // 1023 octets maximum for uri attributes (RFC 2911 4.1.5)
        public const int MaxKeywordLength = 255;                // 255 characters max for keywords (RFC 2911 4.1.3)
        public const int MaxMimeTypeLength = 255;               // 255 characters max for mime types (RFC 2911 4.1.9)
        public const int PrintSchemaVersion = 1;                // PrintSchema version
    }
}