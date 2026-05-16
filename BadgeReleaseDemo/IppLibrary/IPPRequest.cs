//-----------------------------------------------------------------------
// <copyright file="IPPRequest.cs" company="Microsoft">
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
    /// Represents a raw IPP request and provides deserialization from
    /// stream representations.
    /// No semantic validation is done here, merely conformance to RFC 2910.
    /// (See section 3 here: https://tools.ietf.org/html/rfc2910)
    /// </summary>
    public class IppRequest : RawIppEncodingBase
    {
        /// <summary>
        /// The input stream for an incoming IPP request.
        /// </summary>
        private readonly IPPInputStream input;

        /// <summary>
        /// Initializes a new instance of the <see cref="IppRequest"/> class.
        /// </summary>
        private IppRequest()
        {
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="IppRequest"/> class.
        /// Private constructor. An IPPRequest object is created by CreateIppRequestFromStreamAsync().
        /// </summary>
        private IppRequest(Stream input)
        {
            this.input = new IPPInputStream(input) ?? throw new InvalidOperationException("IPPRequest requires input stream.");
            this.BaseAttributeGroups = new List<IppAttributeGroup>();
        }

        /// <summary>
        /// Gets the number of bytes read from the request stream
        /// </summary>
        public long BytesRead { get => this.input.BytesRead; }

        /// <summary>
        /// Create a new IppRequest object with print payload.
        /// </summary>
        /// <param name="operationId">The operation id of the request.</param>
        /// <param name="requestId">The request id of the request.</param>
        /// <param name="printPayload">The print payload.</param>
        /// <returns></returns>
        public static Task<IppRequest> CreateAsync(Operation operationId, int requestId, Stream printPayload)
        {
            var request = new IppRequest()
            {
                OperationId = operationId,
                RequestId = requestId,
                MajorVersionNumber = (sbyte)IppEncoding.IppVersionMajor,
                MinorVersionNumber = (sbyte)IppEncoding.IppVersionMinor,
                Data = printPayload
            };

            return Task.FromResult(request);
        }

        /// <summary>
        /// Create a new IppRequest object without print payload.
        /// </summary>
        /// <param name="operationId">The operation id of the request.</param>
        /// <param name="requestId">The request id of the request.</param>
        /// <returns></returns>
        public static Task<IppRequest> CreateAsync(Operation operationId, int requestId)
        {
            var request = new IppRequest()
            {
                OperationId = operationId,
                RequestId = requestId,
                MajorVersionNumber = (sbyte)IppEncoding.IppVersionMajor,
                MinorVersionNumber = (sbyte)IppEncoding.IppVersionMinor,
            };

            return Task.FromResult(request);
        }

        /// <summary>
        /// Create a new IPP request from incoming stream.
        /// </summary>
        public static async Task<IppRequest> CreateIppRequestFromStreamAsync(Stream requestStream, CancellationToken cancellationToken, Func<Operation, Task> throttlingControl = null)
        {
            var newIppRequest = new IppRequest(requestStream);
            await newIppRequest.DeserializeAsync(cancellationToken, throttlingControl);
            return newIppRequest;
        }

        /// <summary>
        /// Create a new IPP request from incoming stream.
        /// </summary>
        public static async Task<IppRequest> CreateAsync(Stream requestStream)
        {
            return await CreateIppRequestFromStreamAsync(requestStream, new CancellationTokenSource().Token);
        }

        /// <summary>
        /// Gets or sets a value indicating whether the deserialized Operation attribute group is compliant with RFC.
        /// Specifically: RFC 2911 requires first and second attributes of Operation groups to be
        /// attributes-charset and attributes-natural-language respectively.
        /// </summary>
        public bool IsOperationGroupAttributesRfcCompliant { get; set; } = true;

        /// <summary>
        /// Gets the requested operation.
        /// </summary>
        public Operation OperationId { get; set; }

        /// <summary>
        /// Gets the request id.
        /// </summary>
        public int RequestId { get; set; }

        /// <summary>
        /// Gets the attribute groups in the request.
        /// </summary>
        public List<IppAttributeGroup> AttributeGroups => this.BaseAttributeGroups;

        public override void Dispose()
        {
            this.input?.Dispose();
            base.Dispose();
        }

        public List<IppAttributeGroup> LookupAttributeGroup(Tag type)
        {
            var matchedAttributes = new List<IppAttributeGroup>();
            foreach (var attribute in this.BaseAttributeGroups)
            {
                if (attribute.Type == type)
                {
                    matchedAttributes.Add(attribute);
                }
            }

            return matchedAttributes;
        }

        /// <summary>
        /// Returns a string that represents the IPPRequest object.
        /// </summary>
        /// <returns></returns>
        public override string ToString()
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendFormat(CultureInfo.InvariantCulture, "Operation ID: {0}\n", this.OperationId);
            sb.AppendFormat(CultureInfo.InvariantCulture, "Request ID: {0}\n", this.RequestId);
            sb.Append(base.ToString());
            return sb.ToString();
        }

        /// <summary>
        /// Must have required attributes.
        /// </summary>
        public void CheckOperationAttributes()
        {
            if (this.RequestId <= 0)
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, "Request id must be a positive integer.");
            }

            List<IppAttributeGroup> operationAttributesList = this.LookupAttributeGroup(Tag.OperationAttributes);
            if (operationAttributesList.Count == 0)
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, "No operation-attributes group.");
            }

            IppAttributeGroup operationAttributes = operationAttributesList[0];
            if (!operationAttributes.Attributes.ContainsKey(RequiredAttributes.AttributesCharset))
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, "No attributes-charset operation attribute.");
            }

            if (!operationAttributes.Attributes.ContainsKey(RequiredAttributes.AttributesNaturalLanguage))
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, "No attributes-natural-language operation attribute.");
            }

            if (!this.IsOperationGroupAttributesRfcCompliant)
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, "Incorrect order of attributes-charset and attributes-natural-language");
            }
        }

        /// <summary>
        /// Deserialize IPPRequest from stream.
        /// </summary>
        /// <returns>A task.</returns>
        public async Task DeserializeAsync(CancellationToken cancellationToken, Func<Operation, Task> throttlingControl = null)
        {
            // Parse the header blob
            this.MajorVersionNumber = await this.input.ReadSbyteAsync(cancellationToken);
            this.MinorVersionNumber = await this.input.ReadSbyteAsync(cancellationToken);
            this.OperationId = (Operation)await this.input.ReadNetworkShortAsync(cancellationToken);
            this.RequestId = await this.input.ReadNetworkIntegerAsync(cancellationToken);

            if (throttlingControl != null)
            {
                await throttlingControl.Invoke(this.OperationId);
            }

            // Read zero or more attributes from the request
            var tag = await this.input.ReadTagAsync(cancellationToken);

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

                if (!rfcCompliant)
                {
                    this.IsOperationGroupAttributesRfcCompliant = false;
                }

                // Duplicate attribute groups are not expressly prohibited. If this is a duplicate group,
                // merge the attributes from the new group into the existing group. See Bug #39498460
                var existingGroups = this.LookupAttributeGroup(newGroup.Type);
                if (existingGroups.Count == 0)
                {
                    this.BaseAttributeGroups.Add(newGroup);
                }
                else if (existingGroups.Count == 1)
                {
                    foreach (var attribute in newGroup.Attributes)
                    {
                        existingGroups[0].AddAttribute(attribute.Value);
                    }
                }
                else // unreachable
                {
                    throw new Exception("Serialization failed to merge duplicate attribute groups.");
                }
            }

            // We have read in all attribute-groups at this point.  If there is anything left, it is the "data" field.
            this.Data = this.input.Stream;

            // Done.
        }

        /// <summary>
        /// Serialize IPPRequest per RFC 8010 (https://tools.ietf.org/html/rfc8010).
        /// </summary>
        public Stream Serialize()
        {
            Stream memoryStream = new MemoryStream();

            // IPP requestHeader
            memoryStream.WriteByte((byte)this.MajorVersionNumber);
            memoryStream.WriteByte((byte)this.MinorVersionNumber);
            Helpers.WriteNetworkShort(memoryStream, (short)this.OperationId);
            Helpers.WriteNetworkInteger(memoryStream, this.RequestId);

            foreach (var attributeGroup in this.AttributeGroups)
            {
                attributeGroup.Serialize(memoryStream);
            }

            // End of attributes.
            memoryStream.WriteByte((byte)Tag.EndOfAttributes);

            // Copy the print payload if any.
            if (this.Data != null)
            {
                this.Data.Seek(0, SeekOrigin.Begin);
                this.Data.CopyTo(memoryStream);
            }

            memoryStream.Seek(0, SeekOrigin.Begin);
            return memoryStream;
        }

        /// <summary>
        /// Compare two attributes.
        /// </summary>
        public override bool Equals(object obj)
        {
            if (obj is IppRequest other)
            {
                if (this.OperationId != other.OperationId)
                {
                    return false;
                }

                if (this.RequestId != other.RequestId)
                {
                    return false;
                }

                if (this.MajorVersionNumber != other.MajorVersionNumber || this.MinorVersionNumber != other.MinorVersionNumber)
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
