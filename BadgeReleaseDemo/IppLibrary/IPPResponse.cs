//-----------------------------------------------------------------------
// <copyright file="IPPResponse.cs" company="Microsoft">
// Copyright (c) Microsoft. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

namespace BadgeReleaseDemo.IppLibrary
{
    using System;
    using System.Collections.Generic;
    using System.Globalization;
    using System.IO;
    using System.Linq;
    using System.Text;
    using System.Threading;
    using System.Threading.Tasks;
    using BadgeReleaseDemo.IppLibrary.Common;

    /// <summary>
    /// Represents a raw IPP response and provides serialization to a
    /// stream representations.  Automatically fills in the required OperationAttributes (and
    /// as such creates the OperationAttributes attribute-group as well.
    /// </summary>
    public class IppResponse : RawIppEncodingBase
    {
        /// <summary>
        /// The input stream for an incoming IPP response.
        /// </summary>
        private Stream input;

        public IppResponse(sbyte majorVersion, sbyte minorVersion, int responseId, StatusCode statusCode, string naturalLanguage = null)
        {
            // According to spec, any request with major version > 0 can be accepted. Ref: https://tools.ietf.org/html/rfc8010#section-9
            // "IPP objects should respond with a response containing the same "version-number" value used by the Client in the request (if the Client - supplied "version-number" is supported) or
            // the highest "version-number" supported by the Printer(if the Client - supplied "version-number" is not supported)."
            this.StatusCode = statusCode;
            this.ResponseId = responseId;
            this.MajorVersionNumber = (majorVersion != 0) ? majorVersion : (sbyte)IppMajorVersion.Version2;
            this.MinorVersionNumber = (majorVersion == 0 && minorVersion == 0) ? (sbyte)IppMajorVersion.Version1 : minorVersion;
            this.BaseAttributeGroups = new List<IppAttributeGroup>();

            // Add the REQUIRED operation attributes (3.1.4.2) to the response.
            this.AddRequiredAttributes(naturalLanguage);
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="IppResponse"/> class.
        /// </summary>
        /// <param name="majorVersion">The IPP major version."</param>
        /// <param name="minorVersion">The IPP minor version."</param>
        /// <param name="responseId">The response ID of the the IPP response."</param>
        /// <param name="statusCode">The status code of the response.</param>
        /// <param name="detailedStatusMessage">The detailed status message for the response.</param>
        /// <param name="naturalLanguage">The natural language of the response.</param>
        public IppResponse(sbyte majorVersion, sbyte minorVersion, int responseId, StatusCode statusCode, string detailedStatusMessage, string naturalLanguage)
            : this(majorVersion, minorVersion, responseId, statusCode, naturalLanguage)
        {
            var operationAttributes = this.LookupAttributeGroup(Tag.OperationAttributes)[0];
            operationAttributes.AddAttribute(
                new IppAttribute(OperationAttributes.DetailedStatusMessage, IppValue.CreateTextWithoutLanguageValue(detailedStatusMessage, Constants.MaxTextLength)));
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="IppResponse"/> class.
        /// </summary>
        private IppResponse()
        {
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="IppResponse"/> class.
        /// </summary>
        private IppResponse(Stream input)
        {
            this.input = input ?? throw new InvalidOperationException("IPPRequest requires input stream.");
        }

        /// <summary>
        /// Gets or sets the status code of the response.
        /// </summary>
        public StatusCode StatusCode { get; set; }

        /// <summary>
        /// Gets the response id.
        /// </summary>
        public int ResponseId { get; set; }

        /// <summary>
        /// Gets the list of attribute groups in the response.
        /// </summary>
        public List<IppAttributeGroup> AttributeGroups => this.BaseAttributeGroups;

        /// <summary>
        /// Gets or sets the payload of the response.
        /// </summary>
        public new Stream Data
        {
            get => base.Data;
            set => base.Data = value;
        }

        /// <summary>
        /// Search for attribute group matching provided tag type.
        /// </summary>
        /// <param name="type">The type of the attribute group.</param>
        /// <returns>A list of attribute groups with matching type.</returns>
        public List<IppAttributeGroup> LookupAttributeGroup(Tag type)
        {
            var matchedAttributes = new List<IppAttributeGroup>();
            foreach (IppAttributeGroup attribute in this.BaseAttributeGroups)
            {
                if (attribute.Type == type)
                {
                    matchedAttributes.Add(attribute);
                }
            }

            return matchedAttributes;
        }

        /// <summary>
        /// Serialize the response to string.
        /// </summary>
        /// <returns>String form of the response.</returns>
        public override string ToString()
        {
            var sb = new StringBuilder();
            sb.AppendFormat(CultureInfo.InvariantCulture, "Status code {0}", this.StatusCode);
            sb.AppendFormat(CultureInfo.InvariantCulture, "Response ID {0}", this.ResponseId);
            sb.Append(base.ToString());
            return sb.ToString();
        }

        /// <summary>
        /// Add required attributes for the response.
        /// </summary>
        /// <param name="naturalLanguage">Natural language of the response.</param>
        private void AddRequiredAttributes(string naturalLanguage = null)
        {
            var operationAttributes = new IppAttributeGroup(Tag.OperationAttributes);

            operationAttributes.AddAttribute(
                new IppAttribute(IppTemplates.RequiredAttributes.AttributesCharset, IppValue.CreateCharsetValue(Constants.CharSet)));

            if (naturalLanguage == null)
            {
                naturalLanguage = Helpers.GetNaturalLanguage();
            }

            operationAttributes.AddAttribute(
                new IppAttribute(IppTemplates.RequiredAttributes.AttributesNaturalLanguage, IppValue.CreateNaturalLanguageValue(naturalLanguage)));

            this.BaseAttributeGroups.Add(operationAttributes);
        }

        /// <summary>
        /// Create IppResponse object with message.
        /// </summary>
        public static Task<IppResponse> CreateAsync(IppRequest ippRequest, StatusCode statusCode, string detailedStatusMessage, string naturalLanguage)
        {
            var response = new IppResponse()
            {
                StatusCode = statusCode,
                ResponseId = ippRequest?.RequestId ?? 0,
                MajorVersionNumber = ippRequest?.MajorVersionNumber ?? (sbyte)IppMajorVersion.Version2,
                MinorVersionNumber = ippRequest?.MinorVersionNumber ?? (sbyte)IppMajorVersion.Version1
            };

            // Add the REQUIRED operation attributes (3.1.4.2) to the response.
            response.AddRequiredAttributes(naturalLanguage);

            var operationAttributes = response.LookupAttributeGroup(Tag.OperationAttributes)[0];
            operationAttributes.AddAttribute(
                new IppAttribute(OperationAttributes.DetailedStatusMessage, IppValue.CreateTextWithoutLanguageValue(detailedStatusMessage, Constants.MaxTextLength)));

            return Task.FromResult(response);
        }

        /// <summary>
        /// Create IppResponse object without message.
        /// </summary>
        public static Task<IppResponse> CreateAsync(IppRequest ippRequest, StatusCode statusCode, string naturalLanguage = null)
        {
            var response = new IppResponse()
            {
                StatusCode = statusCode,
                ResponseId = ippRequest.RequestId,
                MajorVersionNumber = ippRequest.MajorVersionNumber,
                MinorVersionNumber = ippRequest.MinorVersionNumber,
            };

            // Add the REQUIRED operation attributes (3.1.4.2) to the response.
            response.AddRequiredAttributes(naturalLanguage);

            return Task.FromResult(response);
        }

        /// <summary>
        /// Create the IPPResponse object from input stream.
        /// </summary>
        /// <param name="input"></param>
        /// <param name="stuffRemainingBytesInData"></param>
        /// <param name="cancellationToken"></param>
        /// <returns></returns>
        public static async Task<IppResponse> CreateAsync(Stream input, bool stuffRemainingBytesInData, CancellationToken cancellationToken)
        {
            var response = new IppResponse(input);
            await response.DeserializeAsync(stuffRemainingBytesInData, cancellationToken);
            return response;
        }

        /// <summary>
        /// TBD: handle member attribute.
        /// </summary>
        /// <param name="cancellationToken"></param>
        /// <returns></returns>
        public async Task DeserializeAsync(bool stuffRemainingBytesInData, CancellationToken cancellationToken)
        {
            var input = this.input;
            var ippStream = new IPPInputStream(input);

            // Parse the header blob
            try
            {
                this.MajorVersionNumber = await ippStream.ReadSbyteAsync(cancellationToken);
            }
            catch (InvalidDataException)
            {
                // Callers (e.g., the Connector) use this exception for indication that the Stream was disconnected.
                throw new ZeroByteReadException("Initial read returned 0 bytes");
            }

            this.MinorVersionNumber = await ippStream.ReadSbyteAsync(cancellationToken);
            this.StatusCode = (StatusCode)await ippStream.ReadNetworkShortAsync(cancellationToken);
            this.ResponseId = await ippStream.ReadNetworkIntegerAsync(cancellationToken);

            // Read zero or more attributes from the request
            var tag = await ippStream.ReadTagAsync(cancellationToken);

            while (tag != Tag.EndOfAttributes)
            {
                // This should be a "begin-attribute-group" tag specifying the type.
                if (!Helpers.IsBeginAttributeGroupTag(tag))
                {
                    throw new IPPException(StatusCode.ClientErrorBadRequest, "Expected a begin-attribute-group tag here.");
                }

                // Form a new attribute group.
                var newGroup = new IppAttributeGroup(tag);

                var groupProps = await IppEncodingUtil.DeserializeAttributeGroupAsync(this.input, newGroup, cancellationToken);
                var rfcCompliant = groupProps.Item2;
                tag = groupProps.Item1;

                this.BaseAttributeGroups.Add(newGroup);
            }

            // copy the remaining stream part to a new one,
            // if that is requested by caller
            if (input.CanSeek)
            {
                if (input.Position < input.Length && stuffRemainingBytesInData)
                {
                    Stream restOfDataStream = new System.IO.MemoryStream();
                    // Forward the 'CancellationToken' parameter to methods
                    // Disabled here because the CopyToAsync overload in .net462 (MinimumIppLibraryFramework) that accepts a cancel token also requires a buffer size
                    // We want the library to use its internal buffer size calculator instead.
#pragma warning disable CA2016
                    await input.CopyToAsync(restOfDataStream);
#pragma warning restore CA2016 // Forward the 'CancellationToken' parameter to methods
                    this.Data = restOfDataStream;
                }
            }
        }

        /// <summary>
        /// Serialize the response.
        /// </summary>
        public Stream Serialize()
        {
            var output = new MemoryStream();
            this.Serialize(output);
            return output;
        }

        /// <summary>
        /// Serialize the response.
        /// </summary>
        /// <param name="output">The output stream.</param>
        public void Serialize(Stream output)
        {
            // Write out the header blob
            output.WriteByte((byte)this.MajorVersionNumber);
            output.WriteByte((byte)this.MinorVersionNumber);
            Helpers.WriteNetworkShort(output, (short)this.StatusCode);
            Helpers.WriteNetworkInteger(output, this.ResponseId);

            // Response requirement: https://tools.ietf.org/html/rfc8011#section-4.1.3
            //      Later in this section, each operation is formally defined by
            //      identifying the allowed and expected groups of attributes for each
            //      request and response.The model identifies a specific order for each
            //      group in each request or response, but the attributes within each
            //      group can be in any order, unless specified otherwise.
            //
            // In general: operation attribute group first, unsupported attribute next, the rest of the attribute groups followed.
            foreach (var atrributeGroup in this.BaseAttributeGroups)
            {
                if (atrributeGroup.Type != Tag.OperationAttributes)
                {
                    continue;
                }

                atrributeGroup.Serialize(output);
                break;
            }

            foreach (var atrributeGroup in this.BaseAttributeGroups)
            {
                if (atrributeGroup.Type != Tag.UnsupportedAttributes)
                {
                    continue;
                }

                atrributeGroup.Serialize(output);
                break;
            }

            // Begin writing out attributes if there are any
            foreach (IppAttributeGroup atrributeGroup in this.BaseAttributeGroups)
            {
                if (atrributeGroup.Type != Tag.OperationAttributes && atrributeGroup.Type != Tag.UnsupportedAttributes)
                {
                    atrributeGroup.Serialize(output);
                }
            }

            // End of attributes
            output.WriteByte((byte)Tag.EndOfAttributes);

            // Write out any data if there is any.
            base.Data?.CopyTo(output);

            // And we're done.
            output.Seek(0, SeekOrigin.Begin);
        }

        /// <summary>
        /// Compare two attributes.
        /// </summary>
        public override bool Equals(object obj)
        {
            if (obj is IppResponse other)
            {
                if (this.ResponseId != other.ResponseId)
                {
                    return false;
                }

                if (this.StatusCode != other.StatusCode)
                {
                    return false;
                }

                if (!this.AttributeGroups.SequenceEqual(other.AttributeGroups))
                {
                    return false;
                }

                // just compare size of the payload.
                if (this.Data != null)
                {
                    var otherDataLength = other.Data.Length - other.Data.Position;
                    if (this.Data.Length != otherDataLength)
                    {
                        return false;
                    }
                }
            }
            else
            {
                return false;
            }

            return true;
        }

        /// <summary>
        /// Avoid warning, need to override when overriding Object.Equals(). Nothing special here, rely on Equals.
        /// Attribute comparison is used by test code.
        /// </summary>
        public override int GetHashCode()
        {
            return base.GetHashCode();
        }
    }
}
