//-----------------------------------------------------------------------
// <copyright file="RawIppEncodingBase.cs" company="Microsoft">
// Copyright (c) Microsoft. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

namespace BadgeReleaseDemo.IppLibrary
{
    using System;
    using System.Collections.Generic;
    using System.Globalization;
    using System.IO;
    using System.Text;

    /// <summary>
    /// The raw handling of IPP encoding.
    /// </summary>
    public abstract class RawIppEncodingBase : IDisposable
    {
        /// <summary>
        /// Gets or sets the major version number.
        /// </summary>
        public sbyte MajorVersionNumber { get; set; }

        /// <summary>
        /// Gets or sets the minor version number.
        /// </summary>
        public sbyte MinorVersionNumber { get; set; }

        /// <summary>
        /// Gets or sets the attribute group list.
        /// </summary>
        public List<IppAttributeGroup> BaseAttributeGroups { get; set; } = new List<IppAttributeGroup>();

        /// <summary>
        /// Gets or sets the print data payload.
        /// </summary>
        public Stream Data { get; set; }

        /// <summary>
        /// Serialize to string.
        /// </summary>
        /// <returns>Serialized string.</returns>
        public override string ToString()
        {
            var sb = new StringBuilder();

            sb.AppendFormat(CultureInfo.InvariantCulture, "Version: {0}.{1}\n", this.MajorVersionNumber, this.MinorVersionNumber);
            sb.Append("Attributes:\n");

            foreach (IppAttributeGroup group in this.BaseAttributeGroups)
            {
                sb.AppendFormat(CultureInfo.InvariantCulture, "{0}\n", group);
            }

            // Note that the stream length will be equal to the stream position for chunked requests, not the total length of the stream
            if (this.Data != null && this.Data.CanSeek)
            {
                sb.AppendFormat(CultureInfo.InvariantCulture, "Data: {0} bytes", this.Data.Length);
            }

            return sb.ToString();
        }

        /// <summary>
        /// Dispose.
        /// </summary>
        public virtual void Dispose() => this.Data?.Dispose();

        /// <summary>
        /// Suport IPP version 1.2.
        /// </summary>
        public void CheckVersion()
        {
            if (this.MinorVersionNumber != (sbyte)IppMajorVersion.Version1 && this.MajorVersionNumber != (sbyte)IppMajorVersion.Version2)
            {
                throw new IPPException(BadgeReleaseDemo.IppLibrary.StatusCode.ServerErrorVersionNotSupported, FormattableString.Invariant($"IPP version {this.MajorVersionNumber}.{this.MinorVersionNumber} not supported."));
            }
        }
    }
}
