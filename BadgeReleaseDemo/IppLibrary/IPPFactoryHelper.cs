// <copyright file="IPPFactoryHelper.cs" company="Microsoft">
// Copyright (c) Microsoft. All rights reserved.
// </copyright>

namespace BadgeReleaseDemo.IppLibrary
{
    using System;

    /// <summary>
    /// Factory helper
    /// </summary>
    public static class IppFactoryHelper
    {
        /// <summary>
        /// Create an instance of IIppRequestFactory class.
        /// </summary>
        /// <param name="host">The host of the cloud printer service. e.g., printer.microsoft.com.</param>
        /// <param name="printerId">The cloud device UUID.</param>
        /// <param name="requestingUserName">For requesting-user-name attribute.</param>
        /// <param name="requestingUserUri">For requesting-user-uri attribute.</param>
        /// <returns>an instance of the factory</returns>
        public static IIppRequestFactory CreateIppRequestFactory(string host, string printerId, string requestingUserName, string requestingUserUri)
        {
            // Below is text from RFC 8011. Essentially, the printer URI must be a URL.
            // https://tools.ietf.org/html/rfc8011#section-4.1.5 regarding printer URI:
            //    In all cases, the target URIs contained within the body of IPP
            //    operation requests and responses MUST be in absolute format rather
            //    than relative format(a relative URL identifies a resource with the
            //    scope of the HTTP server, but does not include scheme, host,
            //    or port).
            var printerUri = "ipps://" + host + "/printers/" + printerId;
            return new IppRequestFactory()
            {
                PrinterUri = new Uri(printerUri),
                RequestingUserName = requestingUserName,
                RequestingUserUri = requestingUserUri
            };
        }
    }
}