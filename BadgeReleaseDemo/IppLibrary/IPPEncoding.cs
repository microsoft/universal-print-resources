//-----------------------------------------------------------------------
// <copyright file="IPPEncoding.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

#pragma warning disable SA1402 // File may only contain a single type.  IPP types, this is fine.
#pragma warning disable SA1602 // Document enum values.  IPP types, this is fine.

namespace BadgeReleaseDemo.IppLibrary
{
    using System;
    using System.IO;
    using System.Threading;
    using System.Threading.Tasks;
    using BadgeReleaseDemo.IppLibrary.Common;

    /// <summary>
    /// The IPP version supported by this library.
    /// </summary>
    public enum IppMajorVersion : sbyte
    {
        Version1 = 0x1,
        Version2 = 0x2,
    }

    /// <summary>
    /// Describes the standard IPP tag types.
    /// </summary>
    public enum Tag
    {
        // Attribute tags
        Reserved = 0x0,
        OperationAttributes = 0x1,
        JobAttributes = 0x2,
        EndOfAttributes = 0x3,
        PrinterAttributes = 0x4,
        UnsupportedAttributes = 0x5,
        SubscriptionAttributes = 0x6,
        EventNotificationAttributes = 0x7,
        DocumentAttributes = 0x9,

        // RawValue tags
        Unsupported = 0x10,
        ReservedDefault = 0x11,
        Unknown = 0x12,
        NoValue = 0x13,

        Integer = 0x21,
        Boolean = 0x22,
        Enum = 0x23,

        OctetString = 0x30,
        DateTime = 0x31,
        Resolution = 0x32,
        RangeOfInteger = 0x33,
        BegCollection = 0x34,
        TextWithLanguage = 0x35,
        NameWithLanguage = 0x36,
        EndCollection = 0x37,

        TextWithoutLanguage = 0x41,
        NameWithoutLanguage = 0x42,
        Keyword = 0x44,
        Uri = 0x45,
        UriScheme = 0x46,
        Charset = 0x47,
        NaturalLanguage = 0x48,
        MimeMediaType = 0x49,

        MemberAttrName = 0x4a,

        TypeExtension = 0x7f,       // indicates a type beyond 255, first 4 bytes of value field are the tag value.
    }

    /// <summary>
    /// Public facing encoding related utility functions.
    /// </summary>
    public static class IppEncodingUtil
    {
        public static async Task<Tuple<Tag, bool>> DeserializeAttributeGroupAsync(Stream input, IppAttributeGroup newGroup, CancellationToken cancellationToken)
        {
            var ippStream = new IPPInputStream(input);
            return await DeserializeAttributeGroupAsync(ippStream, newGroup, cancellationToken);
        }

        /// <summary>
        /// Deserialize the input stream to IPPAttributeGroups stored in this.AttributeGroups.
        /// </summary>
        public static async Task<Tuple<Tag, bool>> DeserializeAttributeGroupAsync(IPPInputStream input, IppAttributeGroup newGroup, CancellationToken cancellationToken)
        {
            var isOperationGroupRfcCompliant = true;
            var isOperationGroup = newGroup.Type == Tag.OperationAttributes;

            // An attribute group contains zero or more attribute fields.
            // Read a single "attribute-with-one-value" field;
            // this may be followed by one or more "additional-value" fields
            // for attributes with multiple values, or it may be a
            // begin-attribute-group tag (indicating an empty group) or an
            // end-of-attributes tag (indicating the end of attributes)
            var tag = await input.ReadTagAsync(cancellationToken);
            string nextAttributeName = null;

            while (Helpers.IsValueTag(tag))
            {
                var returnedValue = await IppAttribute.DeserializeIppAttributeAsync(input, cancellationToken, tag, nextAttributeName);
                var newAttribute = returnedValue.Item1;
                tag = returnedValue.Item2;
                nextAttributeName = returnedValue.Item3;

                // Per RFC 2911 section 3.1.4
                // "However, for these two attributes within the Operation Attributes group, the order
                // is critical.The "attributes-charset" attribute MUST be the first attribute in the group and
                // the "attributes-natural-language" attribute MUST be the second attribute in the group"
                if (isOperationGroup)
                {
                    // At least for now, we only support UTF-8 charset, otherwise we need to appropriately handle localized text, name encoding and decoding.
                    if (string.Compare(newAttribute.ValueName, OperationAttributes.AttributesCharset, StringComparison.OrdinalIgnoreCase) == 0 &&
                        string.Compare(newAttribute.Values[0].GetNativeValue<string>(), Constants.CharSet, StringComparison.OrdinalIgnoreCase) != 0)
                    {
                        throw new IPPException(BadgeReleaseDemo.IppLibrary.StatusCode.ClientErrorCharsetNotSupported, FormattableString.Invariant($"IPP charset {newAttribute.Values[0].GetNativeValue<string>()} not supported"));
                    }

                    if (newGroup.Attributes.Count == 0 &&
                        string.Compare(newAttribute.ValueName, OperationAttributes.AttributesCharset, StringComparison.Ordinal) != 0)
                    {
                        isOperationGroupRfcCompliant = false;
                    }

                    if (newGroup.Attributes.Count == 1 &&
                        string.Compare(newAttribute.ValueName, OperationAttributes.AttributesNaturalLanguage, StringComparison.Ordinal) != 0)
                    {
                        isOperationGroupRfcCompliant = false;
                    }
                }

                newGroup.AddAttribute(newAttribute);
            }

            return new Tuple<Tag, bool>(tag, isOperationGroupRfcCompliant);
        }

        /// <summary>
        /// Deserialize a complete IPP attribute group object. Intended to deserialize a single IppAttributeGroup stored on
        /// its own, e.g. in the PrinterObject. This will throw if an IPP request or response stream is passed in.
        /// </summary>
        /// <param name="input">The serialized attribute group.</param>
        /// <param name="attrGroup">The deserialized IPPAttributeGroup object.</param>
        public static async Task DeserializeFullAttributeGroupAsync(Stream input, IppAttributeGroup attrGroup, CancellationToken cancellationToken)
        {
            if (input == null)
            {
                throw new ArgumentNullException(nameof(input));
            }

            if (attrGroup == null)
            {
                throw new ArgumentNullException(nameof(attrGroup));
            }

            input.Seek(0, SeekOrigin.Begin);
            attrGroup.Type = (Tag)input.ReadByte();

            // This function is used to deserialize IppAttributeGroup objects, as opposed to deserializing requests and responses.
            // Hence it is valid for the stream to end immediately after the begin-attribute-group-tag if the group is empty.
            // Read next byte rather than Position and Length because Length can be 0 when HTTP chunked encoding is being used.
            if (await input.ReadAsync(new byte[sizeof(byte)], 0, sizeof(byte), cancellationToken) <= 0)
            {
                return;
            }

            // We still need the byte we read above to perform deserialization, so seek back to it.
            input.Seek(-1, SeekOrigin.Current);

            // The byte returned by deserialization should be -1 because DeserializeAttributeGroupAsync uses ReadByte,
            // which returns -1 when the end of the stream is reached. If a single, serialized attribute group was
            // passed in, we should be at the end of the stream once deserialization is finished.
            var lastByteRead = (await DeserializeAttributeGroupAsync(input, attrGroup, cancellationToken)).Item1;
            if (lastByteRead >= 0)
            {
                throw new InvalidDataException($"Additional data found after serialized IPP attribute group. First byte of additional data: {lastByteRead}");
            }
        }
    }

    internal static class IppEncoding
    {
        public static sbyte IppVersionMajor => (sbyte)IppMajorVersion.Version2;

        public static sbyte IppVersionMinor => 0;

        public static string ContentType => "application/ipp";

        public static string CharSet => "UTF-8";
    }
}
#pragma warning restore SA1402 // File may only contain a single type
#pragma warning restore SA1602 // Document enum values.  IPP types, this is fine.
