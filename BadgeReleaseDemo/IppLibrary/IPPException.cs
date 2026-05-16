//-----------------------------------------------------------------------
// <copyright file="IPPException.cs" company="Microsoft">
// Copyright (c) Microsoft. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

namespace BadgeReleaseDemo.IppLibrary
{
    using System;

    /// <summary>
    /// IPPException is expected to be thrown in any case where an error has occurred
    /// that is meant to be surfaced to the calling client via an error response.
    /// It encapsulates the IPP status code pertinent to the error as well as an associated
    /// 'friendly' message (as well as an optional "detailed" status).
    /// </summary>
    public class IPPException : Exception
    {
        public IPPException(StatusCode statusCode, string message, IppAttributeGroup unsupportedAttributes = null)
            : base(message)
        {
            this.StatusCode = statusCode;
            this.DetailedStatusMessage = message;
            this.UnsupportedAttributes = unsupportedAttributes;
        }

        public StatusCode StatusCode { get; }

        public string DetailedStatusMessage { get; }

        /// <summary>
        /// Gets or sets the IPP major version.
        /// </summary>
        public sbyte IPPRequestMajorVersion { get; set; }

        /// <summary>
        /// Gets or sets the requested IPP minor version.
        /// </summary>
        public sbyte IPPRequestMinorVersion { get; set; }

        /// <summary>
        /// Gets or sets the request id in IPP header.
        /// </summary>
        public int IPPRequestId { get; set; }

        /// <summary>
        /// Gets or sets a value indicating whether the request was from printer.
        /// </summary>
        public bool IsRequestFromPrinter { get; set; }

        public string DetailedInternalInfo { get; set; }

        /// <summary>
        /// Unsupported attributes group, to be sent in response in case of exception
        /// https://datatracker.ietf.org/doc/html/rfc8011#section-4.1.7
        /// </summary>
        public IppAttributeGroup UnsupportedAttributes { get; set; }
    }
}