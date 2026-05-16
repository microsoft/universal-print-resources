//-----------------------------------------------------------------------
// <copyright file="IPPAttribute.cs" company="Microsoft">
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
    /// Represents an IPP attribute (encoding documentation: https://tools.ietf.org/html/rfc8010#section-3.1.3).
    ///
    /// IppAttribute                    ::=     AttributeName, Value { Value }
    /// Value                           ::=     SimpleIppValue
    ///                                 |       CollectionIppAttributeValue
    /// SimpleIppValue                  ::=     Type, Value
    /// CollectionIppAttributeValues    ::=     MemberAttribute { MemberAttribute }
    /// MemberAttribute                 ::=     AttributeName, Value { Value }
    ///
    ///
    /// Each IppAttribute has the following members:
    ///     1. attribute name.
    ///     2. List of IppValues (One or more).
    ///
    /// An IppValue can be of two types: A simple IppAttribute Value, A CollectionIppAttributeValue.
    ///
    /// Simple IppAttribute value has the following members:
    ///     1. Type
    ///     2. Binary value.
    ///
    /// CollectionIppAtrrributeValue has the following members:
    ///     1. List of member attributes.
    ///
    /// If an IppAttribute has simple values, it is considered a simple IppAttribute
    /// If an IppAttribute has collectionIppAttributeValues, it is considered a Collection IppAttribute
    ///
    /// MemberAttribute: Each member attribute is similar to an IppAttribute. It can again be a simple IppAttribute or a CollectionIppAttribute.
    ///         Member attribute can have multiple values as well.
    ///
    /// Simple IPP attribute
    /// |
    /// + Attribute name
    /// + Values[]
    ///   |
    ///   + type1 - value
    ///   + type2 - value
    ///   .
    ///   .
    ///
    /// Collection IPP attribute
    /// |
    /// | Attribute name
    /// + Values[]
    ///    |
    ///    + -- Member attribute
    ///    |     + member attribute value 1
    ///    |     + member attribute value 2
    ///    | -- Member attribute
    ///    |
    ///    + -- Member attribute
    ///    |     + member attribute value 1
    ///    |     + member attribute value 2
    ///    | -- Member attribute
    ///    |
    ///    + -- Member attribute
    ///    |     + member attribute value 1
    ///    |     + member attribute value 2
    ///    | -- Member attribute
    ///
    /// </summary>
    public class IppAttribute
    {
        /// <summary>
        /// The values of the attribute.
        /// </summary>
        private readonly List<IppValue> values;

        /// <summary>
        /// Initializes a new instance of the <see cref="IppAttribute"/> class with no values.
        /// </summary>
        public IppAttribute(string attributeName)
        {
            this.ValueName = attributeName;
            this.values = new List<IppValue>();
            this.IsCollectionAttribute = false;
            this.IsPii = this.IsPiiAttribute();
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="IppAttribute"/> class with a value.
        /// </summary>
        public IppAttribute(string attributeName, IppValue value)
            : this(attributeName, new List<IppValue> { value })
        {
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="IppAttribute"/> class with a value.
        /// </summary>
        public IppAttribute(string attributeName, List<IppValue> values)
            : this(attributeName)
        {
            this.values = new List<IppValue>(values);

            // The values must be either all collection attributes or all regular values (thus a normal attribute).
            int collectionValueCount = 0;

            foreach (var value in values)
            {
                if (value.IsCollectionAttributeValue())
                {
                    collectionValueCount++;
                }
            }

            if (collectionValueCount != 0 && collectionValueCount != values.Count)
            {
                throw new IPPException(
                    StatusCode.ClientErrorBadRequest,
                    FormattableString.Invariant($"An IPP attribute values must be either all collection attributes or regular attributes."));
            }

            if (collectionValueCount != 0)
            {
                this.IsCollectionAttribute = true;
            }
        }

        /// <summary>
        /// Gets or sets a value indicating whether this is a collection attribute.
        /// </summary>
        public bool IsCollectionAttribute { get; set; } = false;

        /// <summary>
        /// Gets the name of the value, i.e., attribute name.
        /// </summary>
        public string ValueName { get; }

        /// <summary>
        /// Gets the the first value.
        /// </summary>
        public IppValue FirstValue => this.values.Count != 0 ? this.values[0] : null;

        /// <summary>
        /// Gets a value indicating whether there are additional values.
        /// </summary>
        public bool HasAdditionalValues => this.values.Count > 1;

        /// <summary>
        /// Gets the values of the attribute.
        /// </summary>
        public IReadOnlyList<IppValue> Values => this.values.AsReadOnly();

        /// <summary>
        /// Gets a value indicating whether this is an empty attribute with no values and no collection attribute.
        /// </summary>
        private bool IsEmptyAttribute => this.values.Count == 0;

        /// <summary>
        /// Gets a value indicating whether this attribute is considered a Pii attribute.
        /// </summary>
        private bool IsPii { get; }

        /// <summary>
        /// Deserialize an IppAttribute.
        /// </summary>
        public static async Task<IppAttribute> DeserializeIppAttributeAsync(IPPInputStream input, CancellationToken cancellationToken)
        {
            var returnedTuple = await IppAttribute.DeserializeIppAttributeAsync(input, cancellationToken, Tag.Reserved, string.Empty);
            return returnedTuple.Item1;
        }

        /// <summary>
        /// Deserialize an IppAttribute.
        /// Return one attribute and the next attribute tag and name.
        /// See: https://tools.ietf.org/html/rfc8010#section-3.1.6.
        /// </summary>
        public static async Task<Tuple<IppAttribute, Tag, string>> DeserializeIppAttributeAsync(
            IPPInputStream input,
            CancellationToken cancellationToken,
            Tag nextTag = Tag.Reserved,
            string nextAttributeName = null)
        {
            Tag tag = nextTag == Tag.Reserved ? await input.ReadTagAsync(cancellationToken) : nextTag;

            string attributeName;
            IppAttribute newAttribute = null;

            // Is there an attribute here?
            if (!Helpers.IsValueTag(tag))
            {
                // Next object is not an attribute.
                return new Tuple<IppAttribute, Tag, string>(null, Tag.Reserved, string.Empty);
            }

            // Parse the attribute name if nextAttributeName is not given.
            if (string.IsNullOrEmpty(nextAttributeName))
            {
                var attributeNameLength = await input.ReadNetworkShortAsync(cancellationToken);
                if (attributeNameLength <= 0)
                {
                    throw new IPPException(StatusCode.ClientErrorBadRequest, $"DeserializeIppAttributeAsync got name-length of {attributeNameLength} for first value of an attribute.");
                }

                attributeName = await input.ReadStringAsync(attributeNameLength, cancellationToken);
            }
            else
            {
                attributeName = nextAttributeName;
            }

            // Handle collection attribute.
            if (Helpers.IsBeginCollectionValueTag(tag))
            {
                while (Helpers.IsBeginCollectionValueTag(tag))
                {
                    if (newAttribute == null)
                    {
                        // 2 bytes for value length.
                        var valueLength = await input.ReadNetworkShortAsync(cancellationToken);

                        // The value-length of a collection attribute must be zero.
                        if (valueLength != 0)
                        {
                            throw new IPPException(
                                StatusCode.ClientErrorBadRequest,
                                FormattableString.Invariant($"The value-length of a collection attribute must be zero, instead of {valueLength}"));
                        }

                        var ippValue = await DeserializeCollectionAttributeValueAsync(input, attributeName, cancellationToken);
                        newAttribute = new IppAttribute(attributeName, ippValue);
                    }
                    else
                    {
                        // Expect either an additional value (the attribute name length is 0) or a new attribute (a new attribute name is parsed).
                        // If a new attribute name is parsed, quit the loop.  Otherwise add the new value.
                        var attributeNameLength = await input.ReadNetworkShortAsync(cancellationToken);

                        if (attributeNameLength != 0)
                        {
                            attributeName = await input.ReadStringAsync(attributeNameLength, cancellationToken);

                            // Quit the loop, one full attribute is parsed.
                            break;
                        }

                        // 2 bytes for value length.
                        var valueLength = await input.ReadNetworkShortAsync(cancellationToken);

                        // The value-length of a collection attribute must be zero.
                        if (valueLength != 0)
                        {
                            throw new IPPException(
                                StatusCode.ClientErrorBadRequest,
                                FormattableString.Invariant($"The value-length of a collection attribute must be zero, instead of {valueLength}"));
                        }

                        // This is the case for 1setof CollectionAttribute. (Multi-valued collection attribute)
                        var additionalCollectionAttributeValue = await DeserializeCollectionAttributeValueAsync(input, string.Empty, cancellationToken);
                        newAttribute.AddAdditionalValue(additionalCollectionAttributeValue);
                    }

                    attributeName = string.Empty;
                    tag = await input.ReadTagAsync(cancellationToken);
                }
            }
            else
            {
                // Loop until 1 complete IppAttribute object is parsed.
                while (Helpers.IsValueTag(tag))
                {
                    if (newAttribute == null)
                    {
                        // Parse attribute name.
                        if (string.IsNullOrEmpty(attributeName))
                        {
                            var attributeNameLength = await input.ReadNetworkShortAsync(cancellationToken);
                            if (attributeNameLength == 0)
                            {
                                throw new IPPException(StatusCode.ClientErrorBadRequest, "DeserializeIppAttributeAsync got name-length of 0 for first value of an attribute.");
                            }

                            attributeName = await input.ReadStringAsync(attributeNameLength, cancellationToken);
                        }

                        newAttribute = new IppAttribute(attributeName);
                        attributeName = string.Empty;
                    }
                    else
                    {
                        // Expect either an additional value (the attribute name length is 0) or a new attribute (a new attribute name is parsed).
                        // If a new attribute name is parsed, quit the loop.  Otherwise add the new value.
                        var attributeNameLength = await input.ReadNetworkShortAsync(cancellationToken);

                        if (attributeNameLength != 0)
                        {
                            attributeName = await input.ReadStringAsync(attributeNameLength, cancellationToken);

                            // Quit the loop, one full attribute is parsed.
                            break;
                        }
                    }

                    // 2 bytes for value length.
                    var valueLength = await input.ReadNetworkShortAsync(cancellationToken);

                    // Parse either attribute with one value or with additional value.
                    // https://tools.ietf.org/html/rfc8010#section-3.1.4.
                    var value = await input.ReadAsync(valueLength, cancellationToken);

                    if (tag == Tag.TypeExtension)
                    {
                        // For extended types, the first 4 bytes of the value indicate the extended type as a big-endian signed integer.
                        // Ensure we read at least 4 bytes into the value.
                        if (valueLength < 4)
                        {
                            throw new IPPException(
                                StatusCode.ClientErrorBadRequest,
                                FormattableString.Invariant($"Expected at least 4 bytes in value data for extended type instead of {valueLength}."));
                        }

                        var extendedType = Helpers.ByteArrayToInteger(value);
                        tag = (Tag)extendedType;
                    }

                    // An additional value for the attribue.
                    newAttribute.AddAdditionalValue(new IppValue(tag, value));

                    // Read the next delimiter.
                    tag = await input.ReadTagAsync(cancellationToken);
                }
            }

            // An attribute is formed.
            var returnValue = new Tuple<IppAttribute, Tag, string>(newAttribute, tag, attributeName);
            return returnValue;
        }

        /// <summary>
        /// Add additional value to the attribute.
        /// </summary>
        /// <param name="newValue">The value to add.</param>
        public void AddAdditionalValue(IppValue newValue)
        {
            // If first value, just add it.  And determine whether this is a collection attribute.
            if (this.IsEmptyAttribute)
            {
                this.values.Add(newValue);

                // If the value is a collection attribute value, then this is a collection attribute.
                this.IsCollectionAttribute = newValue.IsCollectionAttributeValue();
            }
            else
            {
                // Not first value.
                // If adding a collection attribute value, this attribute must be a collection attribute.
                // If adding a normal value, this attribute must not be a collection attribute.
                if (newValue.IsCollectionAttributeValue() && !this.IsCollectionAttribute)
                {
                    throw new IPPException(
                        StatusCode.ClientErrorBadRequest,
                        FormattableString.Invariant($"Collection attribute value cannot be added to a non collecton attribute {this.ValueName}."));
                }
                else if (!newValue.IsCollectionAttributeValue() && this.IsCollectionAttribute)
                {
                    throw new IPPException(
                        StatusCode.ClientErrorBadRequest,
                        FormattableString.Invariant($"Only collection attribute values can be added to a collecton attribute {this.ValueName}."));
                }

                this.values.Add(newValue);
            }
        }

        /// <summary>
        /// Serialize this attribute.
        /// </summary>
        /// <param name="output">The output stream.</param>
        public void Serialize(Stream output)
        {
            // We write a single "attribute-with-one-value" field
            // and then the "additional-value" fields if there are any
            for (var i = 0; i < this.values.Count; i++)
            {
                if (i == 0)
                {
                    this.values[i].Serialize(output, this.ValueName);
                }
                else
                {
                    this.values[i].Serialize(output);
                }
            }
        }

        /// <summary>
        /// Serialize the attribute to string, value is masked if it's a Pii attribute.
        /// </summary>
        /// <returns>String representation of the attribute.</returns>
        public override string ToString()
        {
            return this.ToString(false);
        }

        /// <summary>
        /// Non override version that allows Pii attributes to be included.
        /// See IsPiiAttribute() for a list of attributes that are considered Pii.
        /// </summary>
        public string ToString(bool includePiiAttributes)
        {
            const string PiiMask = "*** PII masked ***";
            if (this.IsPii && !includePiiAttributes)
            {
                // Mask the value of Pii attributes.
                return string.Format(CultureInfo.InvariantCulture, "Attribute {0}: {1}", this.ValueName, PiiMask);
            }

            if (this.HasAdditionalValues)
            {
                var sb = new StringBuilder();

                sb.AppendFormat(CultureInfo.InvariantCulture, "Attribute {0} - Multiple Values:\n", this.ValueName);

                foreach (var value in this.values)
                {
                    sb.Append(value.ToString());
                }

                return sb.ToString();
            }
            else
            {
                return string.Format(CultureInfo.InvariantCulture, "Attribute {0}: {1}", this.ValueName, this.FirstValue != null ? this.FirstValue.ToString() : string.Empty);
            }
        }

        /// <summary>
        /// Determines if this attribute is handled by UP. Will be false for custom attributes.
        /// </summary>
        public bool IsUPHandledUpdateOutputDeviceAttribute()
        {
            switch (this.ValueName)
            {
                case PrinterAttributes.CharsetConfigured:
                case PrinterAttributes.CharsetSupported:
                case PrinterAttributes.ColorModeDefault:
                case PrinterAttributes.ColorModeSupported:
                case PrinterAttributes.ColorSupported:
                case PrinterAttributes.CompressionSupported:
                case PrinterAttributes.CopiesDefault:
                case PrinterAttributes.CopiesSupported:
                case PrinterAttributes.DocumentAccessSupported:
                case PrinterAttributes.DocumentFormatDefault:
                case PrinterAttributes.DocumentFormatDetailsSupported:
                case PrinterAttributes.DocumentFormatPreferred:
                case PrinterAttributes.DocumentFormatSupported:
                case PrinterAttributes.DocumentPasswordSupported:
                case PrinterAttributes.FeedOrientationDefault:
                case PrinterAttributes.FeedOrientationSupported:
                case PrinterAttributes.FinishingsColDatabase:
                case PrinterAttributes.FinishingsColDefault:
                case PrinterAttributes.FinishingsColReady:
                case PrinterAttributes.FinishingsColSupported:
                case PrinterAttributes.FinishingsDefault:
                case PrinterAttributes.FinishingsSupported:
                case PrinterAttributes.GeneratedNaturalLanguageSupported:
                case PrinterAttributes.IppFeaturesSupported:
                case PrinterAttributes.IppVersionsSupported:
                case PrinterAttributes.JobConstraintsSupported:
                case PrinterAttributes.JobCreationAttributesSupported:
                case PrinterAttributes.JobIdsSupported:
                case PrinterAttributes.JobResolversSupported:
                case PrinterAttributes.JobAccountIdDefault:
                case PrinterAttributes.JobAccountIdSupported:
                case PrinterAttributes.JobAccountingUserIdDefault:
                case PrinterAttributes.JobAccountingUserIdSupported:
                case PrinterAttributes.JobMandatoryAttributesSupported:
                case PrinterAttributes.JobPasswordSupported:
                case PrinterAttributes.JobPasswordEncryptionSupported:
                case PrinterAttributes.JobPasswordLengthSupported:
                case PrinterAttributes.JobReleaseActionDefault:
                case PrinterAttributes.JobReleaseActionSupported:
                case PrinterAttributes.JobSheetsDefault:
                case PrinterAttributes.JobSheetsSupported:
                case PrinterAttributes.LandscapeOrientationRequestedPreferred:
                case PrinterAttributes.MarginsPreAppliedDefault:
                case PrinterAttributes.MarginsPreAppliedSupported:
                case PrinterAttributes.MediaBottomMarginSupported:
                case PrinterAttributes.MediaLeftMarginSupported:
                case PrinterAttributes.MediaRightMarginSupported:
                case PrinterAttributes.MediaTopMarginSupported:
                case PrinterAttributes.MediaColDatabase:
                case PrinterAttributes.MediaColDefault:
                case PrinterAttributes.MediaColReady:
                case PrinterAttributes.MediaColSupported:
                case PrinterAttributes.MediaDefault:
                case PrinterAttributes.MediaReady:
                case PrinterAttributes.MediaSizeSupported:
                case PrinterAttributes.MediaSourceSupported:
                case PrinterAttributes.MediaSupported:
                case PrinterAttributes.MediaTypeSupported:
                case PrinterAttributes.MediaColorSupported:
                case PrinterAttributes.MicrosoftPageOrderDefault:
                case PrinterAttributes.MicrosoftPageOrderSupported:
                case PrinterAttributes.MicrosoftUniversalPrintConnectorAppVersion:
                case PrinterAttributes.MicrosoftUniversalPrintConnectorOperatingSystem:
                case PrinterAttributes.MicrosoftUniversalPrintConnectorId:
                case PrinterAttributes.MicrosoftUniversalPrintDocumentFormatSupportedViaConversion:
                case PrinterAttributes.MicrosoftUniversalPrinterDriverName:
                case PrinterAttributes.MicrosoftUniversalPrinterDriverVersion:
                case PrinterAttributes.MopriaCertified:
                case PrinterAttributes.MultipleDocumentHandlingDefault:
                case PrinterAttributes.MultipleDocumentHandlingSupported:
                case PrinterAttributes.MultipleDocumentJobsSupported:
                case PrinterAttributes.MultipleOperationTimeout:
                case PrinterAttributes.MultipleOperationTimeoutAction:
                case PrinterAttributes.NaturalLanguageConfigured:
                case PrinterAttributes.NumberUpDefault:
                case PrinterAttributes.NumberUpSupported:
                case PrinterAttributes.OperationsSupported:
                case PrinterAttributes.OrientationRequestedDefault:
                case PrinterAttributes.OrientationRequestedSupported:
                case PrinterAttributes.OutputBinDefault:
                case PrinterAttributes.OutputBinSupported:
                case PrinterAttributes.OverridesSupported:
                case PrinterAttributes.PageRangesSupported:
                case PrinterAttributes.PagesPerMinute:
                case PrinterAttributes.PagesPerMinuteColor:
                case PrinterAttributes.PclmRasterBackSide:
                case PrinterAttributes.PclmSourceResolutionSupported:
                case PrinterAttributes.PclmStripHeightPreferred:
                case PrinterAttributes.PclmStripHeightSupported:
                case PrinterAttributes.PdlOverrideSupported:
                case PrinterAttributes.PdfFitToPageDefault:
                case PrinterAttributes.PdfFitToPageSupported:
                case PrinterAttributes.PdfSizeConstraints:
                case PrinterAttributes.PdfKOctetsSupported:
                case PrinterAttributes.PdfVersionsSupported:
                case PrinterAttributes.PrintContentOptimizeDefault:
                case PrinterAttributes.PrintContentOptimizeSupported:
                case PrinterAttributes.PresentationDirectionNumberUpDefault:
                case PrinterAttributes.PresentationDirectionNumberUpSupported:
                case PrinterAttributes.PrintDeviceCapabilities:
                case PrinterAttributes.PrintQualityDefault:
                case PrinterAttributes.PrintQualitySupported:
                case PrinterAttributes.PrintRenderingIntentDefault:
                case PrinterAttributes.PrintRenderingIntentSupported:
                case PrinterAttributes.PrintScalingDefault:
                case PrinterAttributes.PrintScalingSupported:
                case PrinterAttributes.PrintWFDS:
                case PrinterAttributes.PrinterAlert:
                case PrinterAttributes.PrinterAlertDescription:
                case PrinterAttributes.PrinterConfigChangeDateTime:
                case PrinterAttributes.PrinterConfigChangeTime:
                case PrinterAttributes.PrinterCurrentTime:
                case PrinterAttributes.PrinterDeviceId:
                case PrinterAttributes.PrinterFirmwareName:
                case PrinterAttributes.PrinterFirmwarePatches:
                case PrinterAttributes.PrinterFirmwareStringVersion:
                case PrinterAttributes.PrinterFirmwareVersion:
                case PrinterAttributes.PrinterGeoLocation:
                case PrinterAttributes.PrinterGetAttributesSupported:
                case PrinterAttributes.PrinterIccProfiles:
                case PrinterAttributes.PrinterIcons:
                case PrinterAttributes.PrinterInfo:
                case PrinterAttributes.PrinterInputTray:
                case PrinterAttributes.PrinterIsAcceptingJobs:
                case PrinterAttributes.PrinterKind:
                case PrinterAttributes.PrinterLocation:
                case PrinterAttributes.PrinterMakeAndModel:
                case PrinterAttributes.PrinterMoreInfo:
                case PrinterAttributes.PrinterMoreInfoManufacturer:
                case PrinterAttributes.PrinterName:
                case PrinterAttributes.PrinterOrganization:
                case PrinterAttributes.PrinterOrganizationalUnit:
                case PrinterAttributes.PrinterOutputTray:
                case PrinterAttributes.PrinterResolutionDefault:
                case PrinterAttributes.PrinterResolutionSupported:
                case PrinterAttributes.PrinterStaticResourceDirectoryUri:
                case PrinterAttributes.PrinterStaticResourceKOctetsFree:
                case PrinterAttributes.PrinterStaticResourceKOctetsSupported:
                case PrinterAttributes.PrinterState:
                case PrinterAttributes.PrinterStateMessage:
                case PrinterAttributes.PrinterStateReasons:
                case PrinterAttributes.PrinterStateChangeDateTime:
                case PrinterAttributes.PrinterStateChangeTime:
                case PrinterAttributes.PrinterSupply:
                case PrinterAttributes.PrinterSupplyDescription:
                case PrinterAttributes.PrinterSupplyInfoUri:
                case PrinterAttributes.PrinterUpTime:
                case PrinterAttributes.PrinterUriSupported:
                case PrinterAttributes.PrinterUuid:
                case PrinterAttributes.PwgRasterDocumentResolutionSupported:
                case PrinterAttributes.PwgRasterDocumentSheetBack:
                case PrinterAttributes.PwgRasterDocumentTypeSupported:
                case PrinterAttributes.QueuedJobCount:
                case PrinterAttributes.SidesDefault:
                case PrinterAttributes.SidesSupported:
                case PrinterAttributes.UrfSupported:
                case PrinterAttributes.UriAuthenticationSupported:
                case PrinterAttributes.UriSecuritySupported:
                case PrinterAttributes.WhichJobsSupported:
                case PrinterAttributes.PullPrintEnabledWithOEMJobRelease:
                    return true;

                // CUPS IPP Attributes (For Mopria 2.0)
                case PrinterAttributes.MarkerColors:
                case PrinterAttributes.MarkerHighLevels:
                case PrinterAttributes.MarkerLevels:
                case PrinterAttributes.MarkerLowLevels:
                case PrinterAttributes.MarkerNames:
                case PrinterAttributes.MarkerTypes:
                    return true;
                default:
                    return false;
            }
        }

        /// <summary>
        /// Validates the syntax of each attribute value, as discussed in RFC 3196 Section 3.1.2.1.5.
        /// </summary>
        /// <remarks>
        /// The length of each value is correct for the client-supplied syntax tag.
        /// The syntax tag of each value is correct for the attribute.
        /// The value is in the range specified for the attribute.
        /// Multiple values are present only if the attribute supports multiple values.
        /// </remarks>
        /// <returns>true if valid, false otherwise</returns>
        public bool IsValidAttribute()
        {
            IList<Tag> validTags = this.GetAttributeTags(this.ValueName);
            foreach (var value in this.Values)
            {
                if (!validTags.Contains(value.ValueType))
                {
                    return false;
                }
            }

            if (!this.SupportsMultipleValues() && this.HasAdditionalValues)
            {
                return false;
            }

            return true;
        }

        /// <summary>
        /// Filters this attribute's values to only those that the IPP Service supports.
        /// </summary>
        /// <remarks>
        /// For example, if the attribute name is 'printer-state-reasons' and the values are
        /// 'none-report' and 'UNSUPPORTED-REPORT', then only 'none-report' is returned.
        /// </remarks>
        /// <returns>supported values</returns>
        public List<IppValue> GetSupportedValues()
        {
            return this.Values.Where(v => this.SupportsValue(v)).ToList();
        }

        /// <summary>
        /// Filters this attribute's values to only those that the IPP Service does not support.
        /// </summary>
        /// <remarks>
        /// For example, if the attribute name is 'printer-state-reasons' and the values are
        /// 'none-report' and 'UNSUPPORTED-REPORT', then only 'UNSUPPORTED-REPORT' is returned.
        /// </remarks>
        /// <returns>unsupported values</returns>
        public List<IppValue> GetUnsupportedValues()
        {
            return this.Values.Where(v => !this.SupportsValue(v)).ToList();
        }

        /// <summary>
        /// Compare two attributes.
        /// </summary>
        public override bool Equals(object obj)
        {
            if (obj is IppAttribute other)
            {
                var isAttributeNameEqual = this.ValueName.Equals(other.ValueName, StringComparison.Ordinal);
                var areValuesEqual = this.values.SequenceEqual(other.values);
                return isAttributeNameEqual && areValuesEqual;
            }

            return false;
        }

        /// <summary>
        /// Avoid warning, need to override when overriding Object.Equals(). Nothing special here, rely on Equals.
        /// Attribute comparison is used by test code.
        /// </summary>
        public override int GetHashCode()
        {
            return base.GetHashCode();
        }

        /// <summary>
        /// Deserialize the input stream to a collection attribute.
        /// </summary>
        private static async Task<IppValue> DeserializeCollectionAttributeValueAsync(IPPInputStream input, string attributeName, CancellationToken cancellationToken, int collectionDepth = 0)
        {
            const int MaxCollectionDepthAllowed = 5;

            // Limit how many layers of collection of collection are allowed.
            if (collectionDepth++ > MaxCollectionDepthAllowed)
            {
                throw new IPPException(
                    StatusCode.ClientErrorBadRequest,
                    FormattableString.Invariant($"Max collection depth of {MaxCollectionDepthAllowed} reached."));
            }

            var ippValue = IppValue.CreateCollectionAttributeValue();

            IppMemberAttribute lastMemberAttribute = null;

            // Deserialize the member attributes for this collection attribute.
            var tag = await input.ReadTagAsync(cancellationToken);
            while (Helpers.IsMemberAttrNameTag(tag))
            {
                // Parse 1 or more member attributes. https://tools.ietf.org/html/rfc8010#section-3.1.7
                // 2 bytes for name-length and it must be zero to signify that this is a member attribute.
                var length = await input.ReadNetworkShortAsync(cancellationToken);
                if (length != 0)
                {
                    throw new IPPException(
                        StatusCode.ClientErrorBadRequest,
                        FormattableString.Invariant($"The name-length of the member attribute must be zero, instead of {length}"));
                }

                // 2 bytes for the value-length of the member-name.
                length = await input.ReadNetworkShortAsync(cancellationToken);
                var memberAttributeName = await input.ReadStringAsync(length, cancellationToken);

                // 1 byte for member-value tag.
                var memberValueTag = await input.ReadTagAsync(cancellationToken);

                // 2 bytes for second name-length, value must be zero to signify it is a "member-attribute" contained in the collection.
                length = await input.ReadNetworkShortAsync(cancellationToken);
                if (length != 0)
                {
                    throw new IPPException(
                        StatusCode.ClientErrorBadRequest,
                        FormattableString.Invariant($"The second name-length of the member attribute must be zero, instead of {length}"));
                }

                // 2 bytes for member-value-length, followed by the member-value.
                length = await input.ReadNetworkShortAsync(cancellationToken);
                IppValue memberIppValue = null;

                if (memberValueTag == Tag.BegCollection)
                {
                    // A collection attribute.
                    if (length != 0)
                    {
                        throw new IPPException(
                            StatusCode.ClientErrorBadRequest,
                            FormattableString.Invariant($"A member attribute that is a collection must have zero member-value-length instead of {length}."));
                    }

                    memberIppValue = await DeserializeCollectionAttributeValueAsync(input, memberAttributeName, cancellationToken, collectionDepth);
                }
                else
                {
                    // A member attribute.  Read the value and add it to the attribute.
                    var memberValue = await input.ReadAsync(length, cancellationToken);
                    memberIppValue = new IppValue(memberValueTag, memberValue);
                }

                // If there is no member attribute name, then it is an additional value for a member attribute.
                // This is the case for a member attribute with multiple values.
                if (string.IsNullOrEmpty(memberAttributeName))
                {
                    if (lastMemberAttribute == null)
                    {
                        throw new IPPException(StatusCode.ClientErrorBadRequest, "A member attribute value should have a name or should be an additional value.");
                    }

                    // Unnamed member attribute, hence adding this value to the last named member attribute.
                    lastMemberAttribute.AddAdditionalValue(memberIppValue);
                }
                else
                {
                    // Named attribute value. Hence a new member attribute is being created.
                    lastMemberAttribute = new IppMemberAttribute(memberAttributeName, memberIppValue);
                    ippValue.AddMemberAttribute(lastMemberAttribute);
                }

                // Read the next tag.
                tag = await input.ReadTagAsync(cancellationToken);
            }

            // Following the member attributes is the end collection tag.
            if (tag != Tag.EndCollection)
            {
                throw new IPPException(
                    StatusCode.ClientErrorBadRequest,
                    FormattableString.Invariant($"Expect end-value-tag of a collection attribute.  Received: {tag}"));
            }

            // Followed by end-name-length field (2 bytes) and must be zero.
            var endNameLength = await input.ReadNetworkShortAsync(cancellationToken);
            if (endNameLength != 0)
            {
                throw new IPPException(
                    StatusCode.ClientErrorBadRequest,
                    FormattableString.Invariant($"Invalid value: {endNameLength}. The end-name-length of a collection attribute must be zero."));
            }

            // Followed by end-value-length field (2 bytes) and must be zero.
            var endValueLength = await input.ReadNetworkShortAsync(cancellationToken);
            if (endValueLength != 0)
            {
                throw new IPPException(
                    StatusCode.ClientErrorBadRequest,
                    FormattableString.Invariant($"Invalid value: {endValueLength}. The end-value-length of a collection attribute must be zero."));
            }

            return ippValue;
        }

        /// <summary>
        /// Returns the supported attribute syntax tags for the given attribute.
        /// </summary>
        /// <param name="attributeName">The attribute</param>
        /// <returns>Returns supported atttribute syntax tags, or none if the attribute is unknown.</returns>
        private List<Tag> GetAttributeTags(string attributeName)
        {
            switch (attributeName)
            {
                // text
                case PrinterAttributes.MicrosoftUniversalPrintConnectorAppVersion:
                case PrinterAttributes.MicrosoftUniversalPrintConnectorOperatingSystem:
                case PrinterAttributes.MicrosoftUniversalPrintConnectorId:
                case PrinterAttributes.MicrosoftUniversalPrinterDriverName:
                case PrinterAttributes.MicrosoftUniversalPrinterDriverVersion:
                case PrinterAttributes.MopriaCertified:
                case PrinterAttributes.PrinterAlertDescription:
                case PrinterAttributes.PrinterInfo:
                case PrinterAttributes.PrinterLocation:
                case PrinterAttributes.PrinterMakeAndModel:
                case PrinterAttributes.PrinterDeviceId:
                case PrinterAttributes.PrinterStateMessage:
                case PrinterAttributes.PrintDeviceCapabilities:
                case PrinterAttributes.PrinterFirmwarePatches:
                case PrinterAttributes.PrinterFirmwareStringVersion:
                case PrinterAttributes.PrinterOrganization:
                case PrinterAttributes.PrinterOrganizationalUnit:
                case PrinterAttributes.PrinterSupplyDescription:
                case JobAttributes.DetailedStatusMessage:
                case JobAttributes.DocumentAccessError:
                case JobAttributes.DocumentFormatVersionSupplied:
                case JobAttributes.JobMessageFromOperator:
                case JobAttributes.JobReleaseActionId:
                case JobAttributes.JobStateMessage:
                case JobAttributes.MediaInfo:
                case JobAttributes.MicrosoftOutputDeviceJobStateMessage:
                case JobAttributes.MicrosoftPrintTicketGenerationMappings:
                case JobAttributes.OutputDeviceAssigned:
                case JobAttributes.OutputDeviceJobStateMessage:
                    return new List<Tag> { Tag.TextWithoutLanguage, Tag.TextWithLanguage };

                // text without language
                case PrinterAttributes.PrintWFDS:
                    return new List<Tag> { Tag.TextWithoutLanguage };

                // name
                case PrinterAttributes.MarkerColors:
                case PrinterAttributes.MarkerNames:
                case PrinterAttributes.JobAccountIdDefault:
                case PrinterAttributes.JobAccountingUserIdDefault:
                case PrinterAttributes.PrinterFirmwareName:
                case PrinterAttributes.PrinterName:
                case JobAttributes.DocumentNameSupplied:
                case JobAttributes.JobAccountId:
                case JobAttributes.JobAccountingUserId:
                case JobAttributes.JobName:
                case JobAttributes.JobOriginatingUserName:
                    return new List<Tag> { Tag.NameWithoutLanguage, Tag.NameWithLanguage };

                // keyword
                case PrinterAttributes.ColorModeDefault:
                case PrinterAttributes.ColorModeSupported:
                case PrinterAttributes.CompressionSupported:
                case PrinterAttributes.DocumentAccessSupported:
                case PrinterAttributes.DocumentFormatDetailsSupported:
                case PrinterAttributes.FeedOrientationDefault:
                case PrinterAttributes.FeedOrientationSupported:
                case PrinterAttributes.FinishingsColSupported:
                case PrinterAttributes.IppFeaturesSupported:
                case PrinterAttributes.IppVersionsSupported:
                case PrinterAttributes.JobCreationAttributesSupported:
                case PrinterAttributes.MarkerTypes:
                case PrinterAttributes.MediaColSupported:
                case PrinterAttributes.MicrosoftPageOrderDefault:
                case PrinterAttributes.MicrosoftPageOrderSupported:
                case PrinterAttributes.MultipleDocumentHandlingDefault:
                case PrinterAttributes.MultipleDocumentHandlingSupported:
                case PrinterAttributes.MultipleOperationTimeoutAction:
                case PrinterAttributes.OutputBinDefault:
                case PrinterAttributes.OutputBinSupported:
                case PrinterAttributes.OverridesSupported:
                case PrinterAttributes.PclmRasterBackSide:
                case PrinterAttributes.PdlOverrideSupported:
                case PrinterAttributes.PdfVersionsSupported:
                case PrinterAttributes.PresentationDirectionNumberUpDefault:
                case PrinterAttributes.PresentationDirectionNumberUpSupported:
                case PrinterAttributes.PrintScalingDefault:
                case PrinterAttributes.PrintScalingSupported:
                case PrinterAttributes.PrintContentOptimizeDefault:
                case PrinterAttributes.PrintContentOptimizeSupported:
                case PrinterAttributes.PrintRenderingIntentDefault:
                case PrinterAttributes.PrintRenderingIntentSupported:
                case PrinterAttributes.PrinterGetAttributesSupported:
                case PrinterAttributes.PrinterKind:
                case PrinterAttributes.PrinterStateReasons:
                case PrinterAttributes.PwgRasterDocumentSheetBack:
                case PrinterAttributes.PwgRasterDocumentTypeSupported:
                case PrinterAttributes.JobReleaseActionDefault:
                case PrinterAttributes.JobReleaseActionSupported:
                case PrinterAttributes.SidesSupported:
                case PrinterAttributes.SidesDefault:
                case PrinterAttributes.UrfSupported:
                case PrinterAttributes.UriSecuritySupported:
                case PrinterAttributes.UriAuthenticationSupported:
                case PrinterAttributes.WhichJobsSupported:
                case JobAttributes.CompressionSupplied:
                case JobAttributes.CoverType:
                case JobAttributes.FeedOrientation:
                case JobAttributes.JobMandatoryAttributes:
                case JobAttributes.JobReleaseAction:
                case JobAttributes.JobReleaseActionActual:
                case JobAttributes.JobStateReasons:
                case JobAttributes.MediaType:
                case JobAttributes.OrientationRequested:
                case JobAttributes.OutputBin:
                case JobAttributes.OutputDeviceJobStateReasons:
                case JobAttributes.PageOrderReceived:
                case JobAttributes.PresentationDirectionNumberUp:
                case JobAttributes.PrintColorMode:
                case JobAttributes.PrintColorModeActual:
                case JobAttributes.PrintScaling:
                case JobAttributes.PrintContentOptimize:
                case JobAttributes.PrintRenderingIntent:
                case JobAttributes.Sides:
                case JobAttributes.SidesActual:
                    return new List<Tag> { Tag.Keyword };

                // enum
                case PrinterAttributes.FinishingsDefault:
                case PrinterAttributes.FinishingsSupported:
                case PrinterAttributes.LandscapeOrientationRequestedPreferred:
                case PrinterAttributes.OperationsSupported:
                case PrinterAttributes.OrientationRequestedSupported:
                case PrinterAttributes.PrintQualityDefault:
                case PrinterAttributes.PrintQualitySupported:
                case PrinterAttributes.PrinterState:
                case JobAttributes.Finishings:
                case JobAttributes.JobState:
                case JobAttributes.OutputDeviceJobState:
                case JobAttributes.OutputDeviceJobStates:
                case JobAttributes.PrinterQuality:
                case JobAttributes.PrintQuality:
                    return new List<Tag> { Tag.Enum };

                // uri
                case PrinterAttributes.PrinterIcons:
                case PrinterAttributes.PrinterMoreInfo:
                case PrinterAttributes.PrinterMoreInfoManufacturer:
                case PrinterAttributes.PrinterStaticResourceDirectoryUri:
                case PrinterAttributes.PrinterSupplyInfoUri:
                case PrinterAttributes.PrinterUriSupported:
                case PrinterAttributes.PrinterUuid:
                case JobAttributes.JobMoreInfo:
                case JobAttributes.JobOriginatingUserUri:
                case JobAttributes.JobPrinterUri:
                case JobAttributes.JobUuid:
                case JobAttributes.JobUri:
                    return new List<Tag> { Tag.Uri };

                // charset
                case PrinterAttributes.CharsetConfigured:
                case PrinterAttributes.CharsetSupported:
                    return new List<Tag> { Tag.Charset };

                // naturalLanguage
                case PrinterAttributes.GeneratedNaturalLanguageSupported:
                case PrinterAttributes.NaturalLanguageConfigured:
                    return new List<Tag> { Tag.NaturalLanguage };

                // mimeMediaType
                case PrinterAttributes.DocumentFormatDefault:
                case PrinterAttributes.DocumentFormatSupported:
                case PrinterAttributes.DocumentFormatPreferred:
                case PrinterAttributes.MicrosoftUniversalPrintDocumentFormatSupportedViaConversion:
                case JobAttributes.DocumentFormatSupplied:
                    return new List<Tag> { Tag.MimeMediaType };

                // octetString
                case PrinterAttributes.PrinterAlert:
                case PrinterAttributes.PrinterFirmwareVersion:
                case PrinterAttributes.PrinterInputTray:
                case PrinterAttributes.PrinterOutputTray:
                case PrinterAttributes.PrinterSupply:
                    return new List<Tag> { Tag.OctetString };

                // boolean
                case PrinterAttributes.ColorSupported:
                case PrinterAttributes.JobIdsSupported:
                case PrinterAttributes.JobAccountIdSupported:
                case PrinterAttributes.JobAccountingUserIdSupported:
                case PrinterAttributes.JobMandatoryAttributesSupported:
                case PrinterAttributes.MarginsPreAppliedDefault:
                case PrinterAttributes.MarginsPreAppliedSupported:
                case PrinterAttributes.MultipleDocumentJobsSupported:
                case PrinterAttributes.PageRangesSupported:
                case PrinterAttributes.PdfFitToPageDefault:
                case PrinterAttributes.PdfFitToPageSupported:
                case PrinterAttributes.PrinterIsAcceptingJobs:
                case JobAttributes.IppAttributeFidelity:
                case PrinterAttributes.PullPrintEnabledWithOEMJobRelease:
                    return new List<Tag> { Tag.Boolean };

                // integer
                case PrinterAttributes.CopiesDefault:
                case PrinterAttributes.DocumentPasswordSupported:
                case PrinterAttributes.IppgetEventLife:
                case PrinterAttributes.MediaBottomMarginSupported:
                case PrinterAttributes.MediaLeftMarginSupported:
                case PrinterAttributes.MediaRightMarginSupported:
                case PrinterAttributes.MediaTopMarginSupported:
                case PrinterAttributes.MultipleOperationTimeout:
                case PrinterAttributes.JobPasswordSupported:
                case PrinterAttributes.MarkerHighLevels:
                case PrinterAttributes.MarkerLevels:
                case PrinterAttributes.MarkerLowLevels:
                case PrinterAttributes.NumberUpDefault:
                case PrinterAttributes.PagesPerMinute:
                case PrinterAttributes.PagesPerMinuteColor:
                case PrinterAttributes.PclmStripHeightPreferred:
                case PrinterAttributes.PclmStripHeightSupported:
                case PrinterAttributes.PdfSizeConstraints:
                case PrinterAttributes.PrinterConfigChangeTime:
                case PrinterAttributes.PrinterStateChangeTime:
                case PrinterAttributes.PrinterStaticResourceKOctetsFree:
                case PrinterAttributes.PrinterStaticResourceKOctetsSupported:
                case PrinterAttributes.PrinterUpTime:
                case PrinterAttributes.QueuedJobCount:
                case JobAttributes.Copies:
                case JobAttributes.CopiesActual:
                case JobAttributes.JobId:
                case JobAttributes.JobImpressions:
                case JobAttributes.JobImpressionsCompleted:
                case JobAttributes.JobKOctets:
                case JobAttributes.JobKOctetsCompleted:
                case JobAttributes.JobKOctetsProcessed:
                case JobAttributes.JobMediaSheets:
                case JobAttributes.JobMediaSheetsCompleted:
                case JobAttributes.JobPriority:
                case JobAttributes.JobPrinterUpTime:
                case JobAttributes.MediaBottomMargin:
                case JobAttributes.MediaHoleCount:
                case JobAttributes.MediaLeftMargin:
                case JobAttributes.MediaOrderCount:
                case JobAttributes.MediaThickness:
                case JobAttributes.MediaTopMargin:
                case JobAttributes.MediaWeightMetric:
                case JobAttributes.MicrosoftJobFetchedTimeInSeconds:
                case JobAttributes.MicrosoftJobPrintedTimeInSeconds:
                case JobAttributes.MicrosoftJobProcessedTimeInSeconds:
                case JobAttributes.MicrosoftJobSpoolerTimeInSeconds:
                case JobAttributes.MicrosoftJobPrinterTimeInSeconds:
                case JobAttributes.MicrosoftPdfToXpsJobConversionTimeInMilliseconds:
                case JobAttributes.MicrosoftPrintTicketGenerationTimeInMilliseconds:
                case JobAttributes.NumberOfDocuments:
                case JobAttributes.NumberOfInterveningJobs:
                case JobAttributes.NumberUp:
                case JobAttributes.JobPagesCompleted:
                case JobAttributes.TimeAtCreation:
                case JobAttributes.XDimension:
                case JobAttributes.YDimension:
                    return new List<Tag> { Tag.Integer };

                // integer | no-value
                case JobAttributes.TimeAtCompleted:
                case JobAttributes.TimeAtProcessing:
                    return new List<Tag> { Tag.Integer, Tag.NoValue };

                // rangeOfInteger
                case PrinterAttributes.CopiesSupported:
                case PrinterAttributes.PdfKOctetsSupported:
                case PrinterAttributes.JobPasswordLengthSupported:
                case JobAttributes.PageRanges:
                    return new List<Tag> { Tag.RangeOfInteger };

                // resolution
                case PrinterAttributes.PclmSourceResolutionSupported:
                case PrinterAttributes.PrinterResolutionDefault:
                case PrinterAttributes.PrinterResolutionSupported:
                case PrinterAttributes.PwgRasterDocumentResolutionSupported:
                case JobAttributes.PrinterResolution:
                    return new List<Tag> { Tag.Resolution };

                // collection
                case PrinterAttributes.FinishingsColDatabase:
                case PrinterAttributes.FinishingsColReady:
                case PrinterAttributes.JobConstraintsSupported:
                case PrinterAttributes.JobResolversSupported:
                case PrinterAttributes.MediaColDatabase:
                case PrinterAttributes.MediaColDefault:
                case PrinterAttributes.MediaSizeSupported:
                case PrinterAttributes.PrinterIccProfiles:
                case JobAttributes.MediaCol:
                case JobAttributes.Overrides:
                    return new List<Tag> { Tag.BegCollection, Tag.EndCollection };

                // datetime
                case PrinterAttributes.PrinterConfigChangeDateTime:
                case PrinterAttributes.PrinterStateChangeDateTime:
                case JobAttributes.DateTimeAtCreation:
                    return new List<Tag> { Tag.DateTime };

                // datetime | no-value
                case JobAttributes.DateTimeAtCompleted:
                case JobAttributes.DateTimeAtProcessing:
                    return new List<Tag> { Tag.DateTime, Tag.NoValue };

                // datetime | unknown
                case PrinterAttributes.PrinterCurrentTime:
                    return new List<Tag> { Tag.DateTime, Tag.Unknown };

                // collection | no-value
                case PrinterAttributes.FinishingsColDefault:
                case JobAttributes.FinishingsCol:
                case PrinterAttributes.MediaColReady:
                    return new List<Tag> { Tag.BegCollection, Tag.EndCollection, Tag.NoValue };

                // collection | integer
                case JobAttributes.MediaSize:
                    return new List<Tag> { Tag.BegCollection, Tag.EndCollection, Tag.Integer };

                // no-value | enum
                case PrinterAttributes.OrientationRequestedDefault:
                    return new List<Tag> { Tag.NoValue, Tag.Enum };

                // keyword | name
                case PrinterAttributes.JobPasswordEncryptionSupported:
                case PrinterAttributes.JobSheetsDefault:
                case PrinterAttributes.JobSheetsSupported:
                case PrinterAttributes.MediaSupported:
                case PrinterAttributes.MediaSourceSupported:
                case PrinterAttributes.MediaTypeSupported:
                case PrinterAttributes.MediaColorSupported:
                case JobAttributes.JobHoldUntil:
                case JobAttributes.JobSheets:
                case JobAttributes.Media:
                case JobAttributes.MediaBackCoating:
                case JobAttributes.MediaColor:
                case JobAttributes.MediaGrain:
                case JobAttributes.MediaFrontCoating:
                case JobAttributes.MediaKey:
                case JobAttributes.MediaPreprinted:
                case JobAttributes.MediaRecycled:
                case JobAttributes.MediaRightMargin:
                case JobAttributes.MediaSizeName:
                case JobAttributes.MediaSource:
                case JobAttributes.MediaTooth:
                case JobAttributes.MultipleDocumentHandling:
                    return new List<Tag> { Tag.Keyword, Tag.NameWithoutLanguage, Tag.NameWithLanguage };

                // integer | rangeOfInteger
                case PrinterAttributes.NumberUpSupported:
                    return new List<Tag> { Tag.Integer, Tag.RangeOfInteger };

                // no-value | keyword | name
                case PrinterAttributes.MediaDefault:
                case PrinterAttributes.MediaReady:
                    return new List<Tag> { Tag.NoValue, Tag.Keyword, Tag.NameWithoutLanguage, Tag.NameWithLanguage };

                // uri | unknown
                case PrinterAttributes.PrinterGeoLocation:
                    return new List<Tag> { Tag.Uri, Tag.Unknown };

                default:
                    return new List<Tag> { };
            }
        }

        private bool SupportsMultipleValues()
        {
            switch (this.ValueName)
            {
                case PrinterAttributes.CompressionSupported:
                case PrinterAttributes.ColorModeSupported:
                case PrinterAttributes.PrinterStateReasons:
                case PrinterAttributes.CharsetSupported:
                case PrinterAttributes.DocumentAccessSupported:
                case PrinterAttributes.DocumentFormatDetailsSupported:
                case PrinterAttributes.DocumentFormatSupported:
                case PrinterAttributes.FeedOrientationSupported:
                case PrinterAttributes.FinishingsColDatabase:
                case PrinterAttributes.FinishingsColDefault:
                case PrinterAttributes.FinishingsColReady:
                case PrinterAttributes.FinishingsColSupported:
                case PrinterAttributes.FinishingsDefault:
                case PrinterAttributes.FinishingsSupported:
                case PrinterAttributes.GeneratedNaturalLanguageSupported:
                case PrinterAttributes.IppFeaturesSupported:
                case PrinterAttributes.IppVersionsSupported:
                case PrinterAttributes.JobConstraintsSupported:
                case PrinterAttributes.JobCreationAttributesSupported:
                case PrinterAttributes.JobResolversSupported:
                case PrinterAttributes.JobPasswordEncryptionSupported:
                case PrinterAttributes.JobReleaseActionSupported:
                case PrinterAttributes.JobSheetsSupported:
                case PrinterAttributes.MarkerColors:
                case PrinterAttributes.MarkerHighLevels:
                case PrinterAttributes.MarkerLevels:
                case PrinterAttributes.MarkerLowLevels:
                case PrinterAttributes.MarkerNames:
                case PrinterAttributes.MarkerTypes:
                case PrinterAttributes.MediaColDatabase:
                case PrinterAttributes.MediaColReady:
                case PrinterAttributes.MediaColSupported:
                case PrinterAttributes.MediaColorSupported:
                case PrinterAttributes.MediaBottomMarginSupported:
                case PrinterAttributes.MediaLeftMarginSupported:
                case PrinterAttributes.MediaRightMarginSupported:
                case PrinterAttributes.MediaTopMarginSupported:
                case PrinterAttributes.MediaReady:
                case PrinterAttributes.MediaSupported:
                case PrinterAttributes.MediaSizeSupported:
                case PrinterAttributes.MediaSourceSupported:
                case PrinterAttributes.MediaTypeSupported:
                case PrinterAttributes.MicrosoftPageOrderSupported:
                case PrinterAttributes.MicrosoftUniversalPrintDocumentFormatSupportedViaConversion:
                case PrinterAttributes.MultipleDocumentHandlingSupported:
                case PrinterAttributes.NumberUpSupported:
                case PrinterAttributes.OperationsSupported:
                case PrinterAttributes.OrientationRequestedSupported:
                case PrinterAttributes.OutputBinSupported:
                case PrinterAttributes.OverridesSupported:
                case PrinterAttributes.PclmSourceResolutionSupported:
                case PrinterAttributes.PclmStripHeightSupported:
                case PrinterAttributes.PclmStripHeightPreferred:
                case PrinterAttributes.PresentationDirectionNumberUpSupported:
                case PrinterAttributes.PdfVersionsSupported:
                case PrinterAttributes.PrintContentOptimizeSupported:
                case PrinterAttributes.PrintQualitySupported:
                case PrinterAttributes.PrintRenderingIntentSupported:
                case PrinterAttributes.PrintScalingSupported:
                case PrinterAttributes.PrinterAlert:
                case PrinterAttributes.PrinterAlertDescription:
                case PrinterAttributes.PrinterFirmwareName:
                case PrinterAttributes.PrinterFirmwareStringVersion:
                case PrinterAttributes.PrinterFirmwarePatches:
                case PrinterAttributes.PrinterFirmwareVersion:
                case PrinterAttributes.PrinterGetAttributesSupported:
                case PrinterAttributes.PrinterIccProfiles:
                case PrinterAttributes.PrinterIcons:
                case PrinterAttributes.PrinterInputTray:
                case PrinterAttributes.PrinterKind:
                case PrinterAttributes.PrinterOrganization:
                case PrinterAttributes.PrinterOrganizationalUnit:
                case PrinterAttributes.PrinterOutputTray:
                case PrinterAttributes.PrinterResolutionSupported:
                case PrinterAttributes.PrinterSupply:
                case PrinterAttributes.PrinterSupplyDescription:
                case PrinterAttributes.PrinterUriSupported:
                case PrinterAttributes.PwgRasterDocumentResolutionSupported:
                case PrinterAttributes.PwgRasterDocumentTypeSupported:
                case PrinterAttributes.SidesSupported:
                case PrinterAttributes.UrfSupported:
                case PrinterAttributes.UriAuthenticationSupported:
                case PrinterAttributes.UriSecuritySupported:
                case PrinterAttributes.WhichJobsSupported:
                case JobAttributes.Finishings:
                case JobAttributes.FinishingsCol:
                case JobAttributes.JobStateReasons:
                case JobAttributes.MicrosoftPrintTicketGenerationMappings:
                case JobAttributes.OutputDeviceJobStateReasons:
                case JobAttributes.OutputDeviceJobStates:
                case JobAttributes.Overrides:
                case JobAttributes.PageRanges:
                    return true;

                default:
                    return false;
            }
        }

        private bool SupportsValue(IppValue value)
        {
            switch (this.ValueName)
            {
                case PrinterAttributes.PrinterState:
                    {
                        var printerState = (PrinterState)value.GetNativeValue();
                        return Enum.IsDefined(typeof(PrinterState), printerState);
                    }

                case PrinterAttributes.PrinterStateReasons:
                case PrinterAttributes.PrinterMakeAndModel:
                case PrinterAttributes.PrinterMoreInfoManufacturer:
                    {
                        var textValue = value.GetNativeValue<string>();
                        return !string.IsNullOrEmpty(textValue);
                    }

                case PrinterAttributes.IppgetEventLife:
                    {
                        var intValue = value.GetNativeValue<int>();
                        return intValue >= 15;
                    }

                case PrinterAttributes.CharsetConfigured:
                case PrinterAttributes.CharsetSupported:
                case PrinterAttributes.ColorModeDefault:
                case PrinterAttributes.ColorModeSupported:
                case PrinterAttributes.ColorSupported:
                case PrinterAttributes.CompressionSupported:
                case PrinterAttributes.CopiesDefault:
                case PrinterAttributes.CopiesSupported:
                case PrinterAttributes.DocumentAccessSupported:
                case PrinterAttributes.DocumentFormatDefault:
                case PrinterAttributes.DocumentFormatDetailsSupported:
                case PrinterAttributes.DocumentFormatPreferred:
                case PrinterAttributes.DocumentFormatSupported:
                case PrinterAttributes.DocumentPasswordSupported:
                case PrinterAttributes.FeedOrientationDefault:
                case PrinterAttributes.FeedOrientationSupported:
                case PrinterAttributes.FinishingsColDatabase:
                case PrinterAttributes.FinishingsColDefault:
                case PrinterAttributes.FinishingsColReady:
                case PrinterAttributes.FinishingsColSupported:
                case PrinterAttributes.FinishingsDefault:
                case PrinterAttributes.FinishingsSupported:
                case PrinterAttributes.GeneratedNaturalLanguageSupported:
                case PrinterAttributes.IppFeaturesSupported:
                case PrinterAttributes.IppVersionsSupported:
                case PrinterAttributes.JobConstraintsSupported:
                case PrinterAttributes.JobCreationAttributesSupported:
                case PrinterAttributes.JobIdsSupported:
                case PrinterAttributes.JobResolversSupported:
                case PrinterAttributes.JobAccountIdDefault:
                case PrinterAttributes.JobAccountIdSupported:
                case PrinterAttributes.JobAccountingUserIdDefault:
                case PrinterAttributes.JobAccountingUserIdSupported:
                case PrinterAttributes.JobMandatoryAttributesSupported:
                case PrinterAttributes.JobPasswordSupported:
                case PrinterAttributes.JobPasswordEncryptionSupported:
                case PrinterAttributes.JobPasswordLengthSupported:
                case PrinterAttributes.JobReleaseActionDefault:
                case PrinterAttributes.JobReleaseActionSupported:
                case PrinterAttributes.JobSheetsDefault:
                case PrinterAttributes.JobSheetsSupported:
                case PrinterAttributes.LandscapeOrientationRequestedPreferred:
                case PrinterAttributes.MarginsPreAppliedDefault:
                case PrinterAttributes.MarginsPreAppliedSupported:
                case PrinterAttributes.MarkerColors:
                case PrinterAttributes.MarkerHighLevels:
                case PrinterAttributes.MarkerLevels:
                case PrinterAttributes.MarkerLowLevels:
                case PrinterAttributes.MarkerNames:
                case PrinterAttributes.MarkerTypes:
                case PrinterAttributes.MediaColDatabase:
                case PrinterAttributes.MediaColDefault:
                case PrinterAttributes.MediaColReady:
                case PrinterAttributes.MediaColSupported:
                case PrinterAttributes.MediaBottomMarginSupported:
                case PrinterAttributes.MediaLeftMarginSupported:
                case PrinterAttributes.MediaRightMarginSupported:
                case PrinterAttributes.MediaTopMarginSupported:
                case PrinterAttributes.MediaDefault:
                case PrinterAttributes.MediaReady:
                case PrinterAttributes.MediaSizeSupported:
                case PrinterAttributes.MediaSourceSupported:
                case PrinterAttributes.MediaTypeSupported:
                case PrinterAttributes.MediaColorSupported:
                case PrinterAttributes.MediaSupported:
                case PrinterAttributes.MicrosoftPageOrderDefault:
                case PrinterAttributes.MicrosoftPageOrderSupported:
                case PrinterAttributes.MicrosoftUniversalPrintConnectorAppVersion:
                case PrinterAttributes.MicrosoftUniversalPrintConnectorOperatingSystem:
                case PrinterAttributes.MicrosoftUniversalPrintConnectorId:
                case PrinterAttributes.MicrosoftUniversalPrintDocumentFormatSupportedViaConversion:
                case PrinterAttributes.MicrosoftUniversalPrinterDriverName:
                case PrinterAttributes.MicrosoftUniversalPrinterDriverVersion:
                case PrinterAttributes.MopriaCertified:
                case PrinterAttributes.MultipleDocumentHandlingDefault:
                case PrinterAttributes.MultipleDocumentHandlingSupported:
                case PrinterAttributes.MultipleDocumentJobsSupported:
                case PrinterAttributes.MultipleOperationTimeout:
                case PrinterAttributes.MultipleOperationTimeoutAction:
                case PrinterAttributes.NaturalLanguageConfigured:
                case PrinterAttributes.NumberUpDefault:
                case PrinterAttributes.NumberUpSupported:
                case PrinterAttributes.OperationsSupported:
                case PrinterAttributes.OrientationRequestedDefault:
                case PrinterAttributes.OrientationRequestedSupported:
                case PrinterAttributes.OutputBinDefault:
                case PrinterAttributes.OutputBinSupported:
                case PrinterAttributes.OverridesSupported:
                case PrinterAttributes.PageRangesSupported:
                case PrinterAttributes.PagesPerMinute:
                case PrinterAttributes.PagesPerMinuteColor:
                case PrinterAttributes.PclmRasterBackSide:
                case PrinterAttributes.PclmSourceResolutionSupported:
                case PrinterAttributes.PclmStripHeightPreferred:
                case PrinterAttributes.PclmStripHeightSupported:
                case PrinterAttributes.PdlOverrideSupported:
                case PrinterAttributes.PrintContentOptimizeDefault:
                case PrinterAttributes.PrintContentOptimizeSupported:
                case PrinterAttributes.PrintRenderingIntentDefault:
                case PrinterAttributes.PrintRenderingIntentSupported:
                case PrinterAttributes.PrintQualityDefault:
                case PrinterAttributes.PrintScalingDefault:
                case PrinterAttributes.PrintScalingSupported:
                case PrinterAttributes.PdfFitToPageDefault:
                case PrinterAttributes.PdfFitToPageSupported:
                case PrinterAttributes.PdfKOctetsSupported:
                case PrinterAttributes.PdfSizeConstraints:
                case PrinterAttributes.PdfVersionsSupported:
                case PrinterAttributes.PresentationDirectionNumberUpDefault:
                case PrinterAttributes.PresentationDirectionNumberUpSupported:
                case PrinterAttributes.PrintQualitySupported:
                case PrinterAttributes.PrintWFDS:
                case PrinterAttributes.PrinterAlert:
                case PrinterAttributes.PrinterAlertDescription:
                case PrinterAttributes.PrinterConfigChangeDateTime:
                case PrinterAttributes.PrinterConfigChangeTime:
                case PrinterAttributes.PrinterCurrentTime:
                case PrinterAttributes.PrinterDeviceId:
                case PrinterAttributes.PrinterFirmwareName:
                case PrinterAttributes.PrinterFirmwarePatches:
                case PrinterAttributes.PrinterFirmwareStringVersion:
                case PrinterAttributes.PrinterFirmwareVersion:
                case PrinterAttributes.PrinterGeoLocation:
                case PrinterAttributes.PrinterGetAttributesSupported:
                case PrinterAttributes.PrinterIccProfiles:
                case PrinterAttributes.PrinterIcons:
                case PrinterAttributes.PrinterInfo:
                case PrinterAttributes.PrinterInputTray:
                case PrinterAttributes.PrinterIsAcceptingJobs:
                case PrinterAttributes.PrinterKind:
                case PrinterAttributes.PrinterLocation:
                case PrinterAttributes.PrinterMoreInfo:
                case PrinterAttributes.PrinterName:
                case PrinterAttributes.PrinterOrganization:
                case PrinterAttributes.PrinterOrganizationalUnit:
                case PrinterAttributes.PrinterOutputTray:
                case PrinterAttributes.PrinterResolutionDefault:
                case PrinterAttributes.PrinterResolutionSupported:
                case PrinterAttributes.PrinterStateMessage:
                case PrinterAttributes.PrinterStateChangeDateTime:
                case PrinterAttributes.PrinterStateChangeTime:
                case PrinterAttributes.PrinterStaticResourceDirectoryUri:
                case PrinterAttributes.PrinterStaticResourceKOctetsFree:
                case PrinterAttributes.PrinterStaticResourceKOctetsSupported:
                case PrinterAttributes.PrinterSupply:
                case PrinterAttributes.PrinterSupplyDescription:
                case PrinterAttributes.PrinterSupplyInfoUri:
                case PrinterAttributes.PrinterUpTime:
                case PrinterAttributes.PrinterUriSupported:
                case PrinterAttributes.PrinterUuid:
                case PrinterAttributes.PwgRasterDocumentResolutionSupported:
                case PrinterAttributes.PwgRasterDocumentSheetBack:
                case PrinterAttributes.PwgRasterDocumentTypeSupported:
                case PrinterAttributes.QueuedJobCount:
                case PrinterAttributes.SidesDefault:
                case PrinterAttributes.SidesSupported:
                case PrinterAttributes.UrfSupported:
                case PrinterAttributes.UriAuthenticationSupported:
                case PrinterAttributes.UriSecuritySupported:
                case PrinterAttributes.WhichJobsSupported:
                case PrinterAttributes.PullPrintEnabledWithOEMJobRelease:
                    return true;

                default:
                    return false;
            }
        }

        /// <summary>
        /// IPP attributes that are considered Pii.
        /// </summary>
        private bool IsPiiAttribute()
        {
            switch (this.ValueName)
            {
                case OperationAttributes.RequestingUserName:
                case OperationAttributes.RequestingUserUri:
                case OperationAttributes.DocumentName:
                case OperationAttributes.JobPassword:
                case JobAttributes.JobOriginatingUserName:
                case JobAttributes.JobOriginatingUserUri:
                case JobAttributes.JobName:
                    return true;

                default:
                    return false;
            }
        }
    }
}
