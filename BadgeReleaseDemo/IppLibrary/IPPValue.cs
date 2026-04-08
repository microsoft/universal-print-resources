//-----------------------------------------------------------------------
// <copyright file="IPPValue.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
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
    using BadgeReleaseDemo.IppLibrary.Common;

    public class IppValue
    {
        /// <summary>
        /// Gets the value of the property.
        /// </summary>
        private byte[] Value { get; }

        /// <summary>
        /// Gets the member attributes of the collection attribute.
        /// </summary>
        private List<IppMemberAttribute> memberAttributes { get; }

        /// <summary>
        /// Initializes a new instance of the <see cref="IppValue"/> class.
        /// Constructs a TypeValuePair from raw data (used in deserialization and by factory methods)
        /// We will validate that the size of the incoming data is appropriate for the specified type.
        /// </summary>
        /// <param name="type">The type of the attribute.</param>
        /// <param name="value">The value of the attribute.</param>
        /// <param name="skipDataValidation">Should only be used by unit tests to prep bad data.</param>
        public IppValue(Tag type, byte[] value, bool skipDataValidation = false)
        {
            if (!skipDataValidation)
            {
                ValidateDataSize(type, value);
            }

            this.ValueType = type;
            this.ExtendedType = 0;
            this.Value = value;

            if (type == Tag.BegCollection)
            {
                this.memberAttributes = new List<IppMemberAttribute>();
            }
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="IppValue"/> class.
        /// </summary>
        /// <param name="extendedType">The extended type of the attribute.</param>
        /// <param name="value">The value of the attribute.</param>
        public IppValue(int extendedType, byte[] value)
        {
            // Note:  In general we can't validate the size of the value here.
            //        As we add support for extended types we can add validation for them.
            this.ValueType = Tag.TypeExtension;
            this.ExtendedType = extendedType;
            this.Value = value;
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="IppValue"/> class.
        /// </summary>
        /// <param name="type">The type of the attribute.</param>
        public IppValue(Tag type)
        {
            this.ValueType = type;
            this.ExtendedType = 0;
            if (type == Tag.BegCollection)
            {
                this.memberAttributes = new List<IppMemberAttribute>();
            }
        }

        /// <summary>
        /// Gets the value type of the property.
        /// </summary>
        public Tag ValueType { get; }

        /// <summary>
        /// Gets the extended type of the property.
        /// </summary>
        public int ExtendedType { get; }

        /// <summary>
        /// Gets the member attributes of the collection attribute.
        /// </summary>
        public IReadOnlyList<IppMemberAttribute> MemberAttributes => this.memberAttributes?.AsReadOnly();

        /// <summary>
        /// Factory constructors for IPP types.  These are used to construct and encode TypeValuePairs for IPP responses
        /// </summary>
        /// <param name="value">The value for the integer attribute.</param>
        /// <returns>The integer attribute.</returns>
        public static IppValue CreateIntegerValue(int value)
        {
            return new IppValue(Tag.Integer, Helpers.IntegerToByteArray(value));
        }

        /// <summary>
        /// Creates a boolean attribute.
        /// </summary>
        /// <param name="value">The value for the boolean attribute.</param>
        /// <returns>The boolean attribute.</returns>
        public static IppValue CreateBooleanValue(bool value)
        {
            return new IppValue(Tag.Boolean, Helpers.BoolToByteArray(value));
        }

        /// <summary>
        /// Creates an enum attribute.
        /// </summary>
        /// <param name="value">The value for the enum attribute.</param>
        /// <returns>The enum attribute.</returns>
        public static IppValue CreateEnumValue(int value)
        {
            return new IppValue(Tag.Enum, Helpers.IntegerToByteArray(value));
        }

        /// <summary>
        /// Creates an octet string attribute.
        /// </summary>
        /// <param name="value">The values of the octet string attribute.</param>
        /// <returns>The octet string attribute.</returns>
        public static IppValue CreateOctetStringValue(byte[] value)
        {
            // For clarity: an OCTET-STRING in IPP is not a text string (necessarily).
            // it's just one or more bytes (effectively an array).
            return new IppValue(Tag.OctetString, value);
        }

        /// <summary>
        /// Creates an octet string attribute.
        /// </summary>
        /// <param name="value">The values of the octet string attribute.</param>
        /// <returns>The octet string attribute.</returns>
        public static IppValue CreateBadOctetStringValueForUnitTest(byte[] value)
        {
            // For clarity: an OCTET-STRING in IPP is not a text string (necessarily).
            // it's just one or more bytes (effectively an array).
            return new IppValue(Tag.OctetString, value, skipDataValidation: true);
        }

        /// <summary>
        /// Creates a date time attribute.
        /// </summary>
        /// <param name="value">The value of the attribute.</param>
        /// <returns>A date time attribute object.</returns>
        public static IppValue CreateDateTimeValue(DateTime value)
        {
            return new IppValue(Tag.DateTime, Helpers.DateTimeToByteArray(value));
        }

        /// <summary>
        /// Creates a resolution attribute.
        /// </summary>
        /// <param name="x">The x value of the attribute.</param>
        /// <param name="y">The y value of the attribute.</param>
        /// <param name="units">The unit of the attribute.</param>
        /// <returns>A resolution attribute object.</returns>
        public static IppValue CreateResolutionValue(int x, int y, sbyte units)
        {
            return new IppValue(Tag.Resolution, Helpers.ResolutionToByteArray(x, y, units));
        }

        /// <summary>
        /// Creates a range of integer attribute.
        /// </summary>
        /// <param name="lower">The lower range of the value.</param>
        /// <param name="upper">The upper range of the value.</param>
        /// <returns>A range of integer attribute object.</returns>
        public static IppValue CreateRangeOfIntegerValue(int lower, int upper)
        {
            return new IppValue(Tag.RangeOfInteger, Helpers.IntegerRangeToByteArray(lower, upper));
        }

        /// <summary>
        /// Creates a text with language value attribute.
        /// </summary>
        /// <param name="theString">The value of the text.</param>
        /// <param name="naturalLanguage">The value of the natural language.</param>
        /// <returns>A text with natural language attribute.</returns>
        public static IppValue CreateTextWithLanguageValue(string theString, string naturalLanguage)
        {
            return new IppValue(Tag.TextWithLanguage, Helpers.StringWithNaturalLanguageToByteArray(theString, naturalLanguage));
        }

        /// <summary>
        /// Creates a name with language value attribute.
        /// </summary>
        /// <param name="theString">The value of the name string.</param>
        /// <param name="naturalLanguage">The value of the natural language.</param>
        /// <returns>A name with natural language attribute.</returns>
        public static IppValue CreateNameWithLanguageValue(string theString, string naturalLanguage)
        {
            return new IppValue(Tag.NameWithLanguage, Helpers.StringWithNaturalLanguageToByteArray(theString, naturalLanguage));
        }

        /// <summary>
        /// Creates a text without language value.
        /// </summary>
        /// <param name="value">The value of the text.</param>
        /// <param name="maxLength">The maximum length of the text.</param>
        /// <returns>A text without natural language attribute.</returns>
        public static IppValue CreateTextWithoutLanguageValue(string value, int maxLength = Constants.MaxTextLength)
        {
            // Truncate strings longer than maxLength
            if (value.Length > maxLength)
            {
                value = value.Substring(0, maxLength);
            }

            // Note:  Since we are only supporting UTF-8 encodings for both requests and responses,
            //        we don't need or care to support specifying an encoding here, we just always
            //        encode the string into UTF-8 in the byte array, which StringToByteArray does.
            return new IppValue(Tag.TextWithoutLanguage, Helpers.StringToUTF8ByteArray(value));
        }

        /// <summary>
        /// Creates a name without language value.
        /// </summary>
        /// <param name="value">The value of the name.</param>
        /// <param name="maxLength">The maximum length of the name.</param>
        /// <returns>A name without language value attribute.</returns>
        public static IppValue CreateNameWithoutLanguageValue(string value, int maxLength = Constants.MaxNameLength)
        {
            // Truncate strings longer than maxLength
            if (value.Length > maxLength)
            {
                value = value.Substring(0, maxLength);
            }

            // Note:  See above comments.
            return new IppValue(Tag.NameWithoutLanguage, Helpers.StringToUTF8ByteArray(value));
        }

        /// <summary>
        /// Creates a key word attribute.
        /// </summary>
        /// <param name="value">The value of the keyword.</param>
        /// <returns>A keyword attribute.</returns>
        public static IppValue CreateKeywordValue(string value)
        {
            if (value.Length > Constants.MaxKeywordLength)
            {
                throw new IPPException(StatusCode.ServerErrorInternalError, string.Format(CultureInfo.InvariantCulture, "Keyword value is greater than maximum keyword length: {0}", value));
            }

            // Note:  Keywords are always encoded as US-ASCII; this means that anything unicode
            //        in the incoming string is ignored (we strip off the top 8 bits).
            return new IppValue(Tag.Keyword, Helpers.StringToASCIIByteArray(value));
        }

        /// <summary>
        /// Creates a uri attribute.
        /// </summary>
        /// <param name="value">The uri value.</param>
        /// <returns>A uri attribute object.</returns>
        public static IppValue CreateURIValue(string value)
        {
            if (value.Length > Constants.MaxUriLength)
            {
                throw new IPPException(StatusCode.ServerErrorInternalError, string.Format(CultureInfo.InvariantCulture, "Uri value is greater than maximum url length: {0}", value));
            }

            return new IppValue(Tag.Uri, Helpers.StringToASCIIByteArray(value));
        }

        /// <summary>
        /// Creates a uri scheme attribute.
        /// </summary>
        /// <param name="value">The value of the uri scheme.</param>
        /// <returns>A uri scheme attribute object.</returns>
        public static IppValue CreateUriSchemeValue(string value)
        {
            return new IppValue(Tag.UriScheme, Helpers.StringToASCIIByteArray(value));
        }

        /// <summary>
        /// Creates a charset value attribute.
        /// </summary>
        /// <param name="value">The value of the attribute.</param>
        /// <returns>The new charset attribute object.</returns>
        public static IppValue CreateCharsetValue(string value)
        {
            return new IppValue(Tag.Charset, Helpers.StringToASCIIByteArray(value));
        }

        /// <summary>
        /// Creates a natural language attribute.
        /// </summary>
        /// <param name="value">The value of the natural language.</param>
        /// <returns>The new attribute.</returns>
        public static IppValue CreateNaturalLanguageValue(string value)
        {
            return new IppValue(Tag.NaturalLanguage, Helpers.StringToASCIIByteArray(value));
        }

        /// <summary>
        /// Creates a mime media type attribute.
        /// </summary>
        /// <param name="value">The mime value.</param>
        /// <returns>The newly created attribute.</returns>
        public static IppValue CreateMimeMediaTypeValue(string value)
        {
            if (value.Length > Constants.MaxMimeTypeLength)
            {
                throw new IPPException(StatusCode.ServerErrorInternalError, string.Format(CultureInfo.InvariantCulture, "Mime type value is greater than maximum mime type length: {0}", value));
            }

            return new IppValue(Tag.MimeMediaType, Helpers.StringToASCIIByteArray(value));
        }

        /// <summary>
        /// Creates no-value value attribute.
        /// </summary>
        /// <returns>A value with Tag.NoVaue.</returns>
        public static IppValue CreateNoValueValue()
        {
            // Empty byte array.
            return new IppValue(Tag.NoValue, new byte[] { });
        }

        /// <summary>
        /// Creates unknown value attribute.
        /// </summary>
        /// <returns>A value with Tag.Unknown.</returns>
        public static IppValue CreateUnknownValue()
        {
            // Empty byte array.
            return new IppValue(Tag.Unknown, new byte[] { });
        }

        /// <summary>
        /// Creates collection attribute value.
        /// </summary>
        /// <returns>A beg collection.</returns>
        public static IppValue CreateCollectionAttributeValue()
        {
            return new IppValue(Tag.BegCollection);
        }

        /// <summary>
        /// Adds member attribute to the collection value
        /// </summary>
        /// <param name="memberAttribute">Member attribute to be added to the current collection value</param>
        public void AddMemberAttribute(IppMemberAttribute memberAttribute)
        {
            if (this.IsCollectionAttributeValue())
            {
                this.memberAttributes.Add(memberAttribute);
            }
            else
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, "Cannot add member attributes to a non-collection attribute");
            }
        }

        /// <summary>
        /// Adds member attribute to the collection value
        /// </summary>
        /// <param name="memberAttributeName">Name to use for the member attribute.</param>
        /// <param name="memberAttributeValue">Member attribute to be added to the current collection value</param>
        public void AddMemberAttribute(string memberAttributeName, IppValue memberAttributeValue)
        {
            this.AddMemberAttribute(new IppMemberAttribute(memberAttributeName, memberAttributeValue));
        }

        public bool IsCollectionAttributeValue()
        {
            return this.ValueType == Tag.BegCollection;
        }

        public bool IsOutOfBandValue()
        {
            return this.ValueType == Tag.Unknown || this.ValueType == Tag.NoValue;
        }

        /// <summary>
        /// Returns the serialized binary value
        /// </summary>
        public byte[] GetSerializedValue()
        {
            return this.Value;
        }

        /// <summary>
        /// Returns the value as a .NET type (used for consuming the value)
        /// </summary>
        public T GetNativeValue<T>()
        {
            return (T)this.GetNativeValue();
        }

        /// <summary>
        /// Returns the value as a .NET type (used for consuming the value)
        /// </summary>
        public object GetNativeValue()
        {
            object value = null;

            switch (this.ValueType)
            {
                case Tag.Resolution:
                    value = Helpers.ByteArrayToResolution(this.Value);
                    break;

                case Tag.DateTime:
                    value = Helpers.ByteArrayToDateTime(this.Value);
                    break;

                case Tag.Integer:
                case Tag.Enum:
                    value = Helpers.ByteArrayToInteger(this.Value);
                    break;

                case Tag.RangeOfInteger:
                    value = Helpers.ByteArrayToIntegerRange(this.Value);
                    break;

                case Tag.Boolean:
                    value = Helpers.ByteArrayToBool(this.Value);
                    break;

                case Tag.OctetString:
                    value = this.Value;
                    break;

                case Tag.TextWithLanguage:
                case Tag.NameWithLanguage:
                    // Untill we find some customer scenarioes that need the language code, we decided to only give back the string value.
                    // At least Windows client side does NOT need to do any parsing or casing based on the language code.
                    value = Helpers.ByteArrayToStringWithNaturalLanguage(this.Value).Item1;
                    break;

                /*
                 * https://tools.ietf.org/html/rfc8010#section-3
                 * 3.9. (Attribute) "value".
                 * NOTE: textWithoutLanguage is LOCALIZED - STRING
                +----------------------+--------------------------------------------+

                | Syntax of Attribute  | Encoding                                   |

                | Value |                                                           |
                +----------------------+--------------------------------------------+

                | textWithoutLanguage, | LOCALIZED - STRING
                */
                case Tag.TextWithoutLanguage:
                case Tag.NameWithoutLanguage:
                    value = Helpers.UTF8ByteArrayToString(this.Value);
                    break;

                case Tag.Keyword:
                case Tag.Uri:
                case Tag.UriScheme:
                case Tag.Charset:
                case Tag.NaturalLanguage:
                case Tag.MimeMediaType:
                    value = Helpers.ASCIIByteArrayToString(this.Value);
                    break;

                case Tag.TypeExtension:
                    throw new NotImplementedException("Extended types not supported yet.");

                case Tag.NoValue:
                case Tag.Unknown:
                    value = null;
                    break;

                case Tag.BegCollection:
                    throw new IPPException(StatusCode.ClientErrorBadRequest, "Collection attribute cannot have a native value.");
                default:
                    throw new IPPException(StatusCode.ClientErrorBadRequest, "Unhandled attribute type.");
            }

            return value;
        }

        /// <summary>
        /// Serializes this pair as an "attribute-with-one-value" if attribute name is non-empty
        /// Serializes this pair as an "additional-value" if attribute name is empty or null
        /// </summary>
        /// <param name="output">The output stream.</param>
        /// <param name="attributeName">The name of the attribute.</param>
        public void Serialize(Stream output, string attributeName = null)
        {
            if (this.IsCollectionAttributeValue())
            {
                // Setup the collection attribute: https://tools.ietf.org/html/rfc8010#section-3.1.6
                output.WriteByte((byte)Tag.BegCollection);                          // value-tag            This is a collection attribute: 0x34.

                if (string.IsNullOrEmpty(attributeName))
                {
                    Helpers.WriteNetworkShort(output, (short)0x0000);               // name-length          Set to 0 for additional collection attribute values. see https://tools.ietf.org/html/rfc8010#section-3.1.6.
                }
                else
                {
                    Helpers.WriteNetworkShort(output, (short)attributeName.Length); // name-length          Length of the attribute name.
                    Helpers.WriteAsciiString(output, attributeName);                // name                 Attribute name.
                }

                Helpers.WriteNetworkShort(output, (short)0x00);                     // value-length         Always 0, signifying a collection attribute.

                // Serialize the member attributes.
                for (var i = 0; i < this.memberAttributes.Count; i++)
                {
                    this.memberAttributes[i].SerializeMemberAttribute(output, 1);   // member-attribute     The serialized content of all member attributes.
                }

                // Complete the collection attribute.
                output.WriteByte((byte)Tag.EndCollection);                          // end-value-tag        Always 0x37 denoting end of the collection.
                Helpers.WriteNetworkShort(output, (short)0x00);                     // end-name-length      Always 0x0000.
                Helpers.WriteNetworkShort(output, (short)0x00);                     // end-value-length     Always 0x0000.
            }
            else
            {
                output.WriteByte((byte)this.ValueType);                             // value-tag            Type of attribute.

                if (string.IsNullOrEmpty(attributeName))
                {
                    Helpers.WriteNetworkShort(output, (short)0x0000);               // name-length          0x0000 for additional values.
                }
                else
                {
                    Helpers.WriteNetworkShort(output, (short)attributeName.Length); // name-length          Length of the attribute name.
                    Helpers.WriteAsciiString(output, attributeName);                // name                 Attribute name.
                }

                Helpers.WriteNetworkShort(output, (short)this.Value.Length);        // value-length         Length of the attribute value.
                output.Write(this.Value, 0, this.Value.Length);                     // value                Value of the attribute.
            }
        }

        /// <summary>
        /// Serializes a member attribute.
        /// </summary>
        /// <param name="output">The output stream.</param>
        public void SerializeAsMemberAttribute(Stream output, string memberAttributeName, int collectionDepth)
        {
            // Setup the member attribute: https://tools.ietf.org/html/rfc8010#section-3.1.6
            if (this.IsCollectionAttributeValue())
            {
                const int MaxCollectionDepthAllowed = 5;

                // Limit how many layers of collection of collection are allowed.
                if (collectionDepth++ > MaxCollectionDepthAllowed)
                {
                    throw new IPPException(
                                StatusCode.ClientErrorBadRequest,
                                FormattableString.Invariant($"Max collection depth of {MaxCollectionDepthAllowed} reached."));
                }

                // Setup this collection attribute as a member attribute.
                output.WriteByte((byte)Tag.MemberAttrName);                                 // value-tag            This is a member attribute: 0x4a.
                Helpers.WriteNetworkShort(output, (short)0x00);                             // name-length          Always 0, signifying a member attr.

                if (string.IsNullOrEmpty(memberAttributeName))
                {
                    Helpers.WriteNetworkShort(output, (short)0x0000);                       // name-length          0x0000 for additional values.
                }
                else
                {
                    Helpers.WriteNetworkShort(output, (short)memberAttributeName.Length);   // value-length         Length of member-name.
                    Helpers.WriteAsciiString(output, memberAttributeName);                  // value                The member-name.
                }

                output.WriteByte((byte)Tag.BegCollection);                                  // member-value-tag     This is a collection member attribute.
                Helpers.WriteNetworkShort(output, (short)0x00);                             // name-length          Second name length, always 0.
                Helpers.WriteNetworkShort(output, (short)0x00);                             // member-value-length  Always zero as what follows are member attributes.

                // Serialize the member attributes.
                foreach (var memberAttribute in this.memberAttributes)
                {
                    memberAttribute.SerializeMemberAttribute(output, collectionDepth);
                }

                // Complete this collection attribute.
                output.WriteByte((byte)Tag.EndCollection);                                  // end-value-tag        Always 0x37 denoting end of the collection.
                Helpers.WriteNetworkShort(output, (short)0x00);                             // end-name-length      Always 0x0000.
                Helpers.WriteNetworkShort(output, (short)0x00);                             // end-value-length     Always 0x0000.
            }
            else
            {
                output.WriteByte((byte)Tag.MemberAttrName);                                 // value-tag            This is a member attribute: 0x4a.
                Helpers.WriteNetworkShort(output, (short)0x0000);                           // name-length          Always 0, signifying a member attr.

                if (string.IsNullOrEmpty(memberAttributeName))
                {
                    Helpers.WriteNetworkShort(output, (short)0x0000);                       // name-length          0x0000 for additional values.
                }
                else
                {
                    Helpers.WriteNetworkShort(output, (short)memberAttributeName.Length);   // value-length         Length of member-name.
                    Helpers.WriteAsciiString(output, memberAttributeName);                  // value                The member-name.
                }

                output.WriteByte((byte)this.ValueType);                                     // member-value-tag     Type of member attribute.
                Helpers.WriteNetworkShort(output, (short)0x0000);                           // name-length          Second name length, always 0.
                Helpers.WriteNetworkShort(output, (short)this.Value.Length);                // member-value-length  Length of the member attribute value.
                output.Write(this.Value, 0, this.Value.Length);                             // member-value         The value of the member attribute.
            }
        }

        public override string ToString()
        {
            if (this.IsCollectionAttributeValue())
            {
                var sb = new StringBuilder();

                sb.AppendFormat(CultureInfo.InvariantCulture, "Collection Attribute Value - Member Attribute list:\n");
                foreach (var memberAttribute in this.memberAttributes)
                {
                    sb.AppendFormat(CultureInfo.InvariantCulture, "\t" + memberAttribute.ToString() + "\n");
                }

                return sb.ToString();
            }
            else
            {
                return string.Format(
                        CultureInfo.InvariantCulture,
                        "SimpleIppValue-Type:{0}-Value:{1}\n",
                        this.ValueType,
                        (object)this.GetNativeValue());
            }
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
        /// Compare two IppValue objects.
        /// </summary>
        public override bool Equals(object obj)
        {
            if (obj is IppValue other)
            {
                if (this.IsCollectionAttributeValue())
                {
                    var isCollectionValueEqual = this.IsCollectionAttributeValue().Equals(other.IsCollectionAttributeValue());
                    if (isCollectionValueEqual)
                    {
                        var areMemberAttributesEqual = this.memberAttributes.SequenceEqual(other.memberAttributes);
                        return areMemberAttributesEqual;
                    }
                }
                else
                {
                    var isValueTypeEqual = this.ValueType.Equals(other.ValueType);
                    var isValueEqual = this.Value.SequenceEqual(other.Value);
                    return isValueTypeEqual && isValueEqual;
                }
            }

            return false;
        }

        /// <summary>
        /// Return a member attribute with name that matches memberAttributeName.
        /// </summary>
        /// <param name="memberAttributeName">The name of the member attribute.</param>
        /// <returns>The member attribute.</returns>
        public IppMemberAttribute GetMemberAttribute(string memberAttributeName)
        {
            if (!this.IsCollectionAttributeValue())
            {
                return null;
            }

            return this.memberAttributes.Find(x => string.Equals(x.ValueName, memberAttributeName, StringComparison.Ordinal));
        }

        /// <summary>
        /// Return a member attribute with name that matches memberAttributeName.
        /// </summary>
        /// <param name="memberAttributeName">The name of the member attribute.</param>
        /// <returns>The member attribute.</returns>
        public object GetMemberAttributeNativeValue(string memberAttributeName)
        {
            if (!this.IsCollectionAttributeValue())
            {
                return null;
            }

            return this.memberAttributes.Find(x => string.Equals(x.ValueName, memberAttributeName, StringComparison.Ordinal)).FirstValue.GetNativeValue();
        }

        public static bool IsUPKnownMediaTypeKeyword(string mediaType)
        {
            switch (mediaType.ToLower())
            {
                case MediaTypes.Aluminum:
                case MediaTypes.Auto:
                case MediaTypes.BackPrintFilm:
                case MediaTypes.Cardboard:
                case MediaTypes.Cardstock:
                case MediaTypes.CardstockCoated:
                case MediaTypes.CardstockHeavyweight:
                case MediaTypes.CardstockHeavyweightCoated:
                case MediaTypes.CardstockLightweight:
                case MediaTypes.CardstockLightweightCoated:
                case MediaTypes.Cd:
                case MediaTypes.Continuous:
                case MediaTypes.ContinuousLong:
                case MediaTypes.ContinuousShort:
                case MediaTypes.CorrugatedBoard:
                case MediaTypes.Disc:
                case MediaTypes.DiscGlossy:
                case MediaTypes.DiscHighGloss:
                case MediaTypes.DiscMatte:
                case MediaTypes.DiscSatin:
                case MediaTypes.DiscSemiGloss:
                case MediaTypes.DoubleWall:
                case MediaTypes.DryFilm:
                case MediaTypes.Dvd:
                case MediaTypes.EmbossingFoil:
                case MediaTypes.EndBoard:
                case MediaTypes.Envelope:
                case MediaTypes.EnvelopeArchival:
                case MediaTypes.EnvelopeBond:
                case MediaTypes.EnvelopeCoated:
                case MediaTypes.EnvelopeCotton:
                case MediaTypes.EnvelopeFine:
                case MediaTypes.EnvelopeHeavyweight:
                case MediaTypes.EnvelopeInkjet:
                case MediaTypes.EnvelopeLightweight:
                case MediaTypes.EnvelopePlain:
                case MediaTypes.EnvelopePreprinted:
                case MediaTypes.EnvelopeWindow:
                case MediaTypes.Fabric:
                case MediaTypes.FabricArchival:
                case MediaTypes.FabricGlossy:
                case MediaTypes.FabricHighGloss:
                case MediaTypes.FabricMatte:
                case MediaTypes.FabricSemiGloss:
                case MediaTypes.FabricWaterproof:
                case MediaTypes.Film:
                case MediaTypes.FlexoBase:
                case MediaTypes.FlexoPhotoPolymer:
                case MediaTypes.Flute:
                case MediaTypes.Foil:
                case MediaTypes.FullCutTabs:
                case MediaTypes.Glass:
                case MediaTypes.GlassColored:
                case MediaTypes.GlassOpaque:
                case MediaTypes.GlassSurfaced:
                case MediaTypes.GlassTextured:
                case MediaTypes.GravureCylinder:
                case MediaTypes.ImageSetterPaper:
                case MediaTypes.ImagingCylinder:
                case MediaTypes.Labels:
                case MediaTypes.LabelsColored:
                case MediaTypes.LabelsContinuous:
                case MediaTypes.LabelsGlossy:
                case MediaTypes.LabelsHeavyweight:
                case MediaTypes.LabelsHighGloss:
                case MediaTypes.LabelsInkjet:
                case MediaTypes.LabelsLightweight:
                case MediaTypes.LabelsMatte:
                case MediaTypes.LabelsPermanent:
                case MediaTypes.LabelsSatin:
                case MediaTypes.LabelsSecurity:
                case MediaTypes.LabelsSemiGloss:
                case MediaTypes.LaminatingFoil:
                case MediaTypes.Letterhead:
                case MediaTypes.Metal:
                case MediaTypes.MetalGlossy:
                case MediaTypes.MetalHighGloss:
                case MediaTypes.MetalMatte:
                case MediaTypes.MetalSatin:
                case MediaTypes.MetalSemiGloss:
                case MediaTypes.MountingTape:
                case MediaTypes.MultiLayer:
                case MediaTypes.MultiPartForm:
                case MediaTypes.Other:
                case MediaTypes.Paper:
                case MediaTypes.Photographic:
                case MediaTypes.PhotographicArchival:
                case MediaTypes.PhotographicFilm:
                case MediaTypes.PhotographicGlossy:
                case MediaTypes.PhotographicHighGloss:
                case MediaTypes.PhotographicMatte:
                case MediaTypes.PhotographicSatin:
                case MediaTypes.PhotographicSemiGloss:
                case MediaTypes.Plastic:
                case MediaTypes.PlasticArchival:
                case MediaTypes.PlasticColored:
                case MediaTypes.PlasticGlossy:
                case MediaTypes.PlasticHighGloss:
                case MediaTypes.PlasticMatte:
                case MediaTypes.PlasticSatin:
                case MediaTypes.PlasticSemiGloss:
                case MediaTypes.Plate:
                case MediaTypes.Polyester:
                case MediaTypes.PreCutTabs:
                case MediaTypes.Roll:
                case MediaTypes.Screen:
                case MediaTypes.ScreenPaged:
                case MediaTypes.SelfAdhesive:
                case MediaTypes.SelfAdhesiveFilm:
                case MediaTypes.ShrinkFoil:
                case MediaTypes.SingleFace:
                case MediaTypes.SingleWall:
                case MediaTypes.Sleeve:
                case MediaTypes.Stationery:
                case MediaTypes.StationeryArchival:
                case MediaTypes.StationeryBond:
                case MediaTypes.StationeryCoated:
                case MediaTypes.StationeryColored:
                case MediaTypes.StationeryCotton:
                case MediaTypes.StationeryFine:
                case MediaTypes.StationeryHeavyweight:
                case MediaTypes.StationeryHeavyweightCoated:
                case MediaTypes.StationeryInkjet:
                case MediaTypes.StationeryLetterhead:
                case MediaTypes.StationeryLightweight:
                case MediaTypes.StationeryPreprinted:
                case MediaTypes.StationeryPrepunched:
                case MediaTypes.StationeryRecycled:
                case MediaTypes.TabStock:
                case MediaTypes.Tractor:
                case MediaTypes.Transfer:
                case MediaTypes.Transparency:
                case MediaTypes.TripleWall:
                case MediaTypes.WetFilm:
                    return true;

                default:
                    return false;
            }
        }

        /// <summary>
        /// Validate that there are expected number of bytes for the given type.
        /// </summary>
        private static void ValidateDataSize(Tag type, byte[] value)
        {
            var invalid = false;
            switch (type)
            {
                case Tag.Integer:
                case Tag.Enum:
                    invalid = value.Length != 4;
                    break;

                case Tag.RangeOfInteger:
                    invalid = value.Length != 8;
                    break;

                case Tag.Boolean:
                    invalid = value.Length != 1;
                    break;

                case Tag.OctetString:
                    // See: https://tools.ietf.org/html/rfc8011#section-5.1.11
                    invalid = value.Length > 1023;
                    break;

                case Tag.DateTime:
                    // See:https://tools.ietf.org/html/rfc2579 page 18.
                    invalid = value.Length != 11;
                    break;

                case Tag.Resolution:
                    // See: https://tools.ietf.org/html/rfc8011#section-5.1.16.
                    invalid = value.Length != 9;
                    break;

                case Tag.TextWithLanguage:
                case Tag.NameWithLanguage:
                    // Note:  from the RFC:
                    //    a. a SIGNED-SHORT which is the number of
                    //         octets in the following field
                    //    b. a value of type natural-language,
                    //    c. a SIGNED-SHORT which is the number of
                    //         octets in the following field,
                    //    d. a value of type textWithoutLanguage.
                    //    The length of a textWithLanguage value MUST be
                    //    2 + the value of field a + 2 + the value of field c.

                    // Validate that the buffer is at least 4 bytes long (the
                    // degenerate case).
                    invalid = value.Length < 4;

                    // Validate the length of the buffer based on the length fields
                    if (!invalid)
                    {
                        short nlLength = Helpers.ByteArrayToShort(value);
                        invalid = value.Length < 2 + nlLength;

                        if (!invalid)
                        {
                            short textLength = (short)(ushort)((value[2 + nlLength] << 8) | value[2 + nlLength + 1]);
                            invalid = value.Length != 2 + nlLength + 2 + textLength;
                        }
                    }

                    break;

                case Tag.TextWithoutLanguage:
                case Tag.NameWithoutLanguage:
                case Tag.Keyword:
                case Tag.Uri:
                case Tag.UriScheme:
                case Tag.Charset:
                case Tag.NaturalLanguage:
                case Tag.MimeMediaType:
                    // These cases require no specific validation, they are string values.
                    // For some of these (keyword, name, etc) having a zero-length string
                    // seems odd, but I can find nothing in the RFC specifically disallowing it.
                    invalid = false;
                    break;

                case Tag.NoValue:
                case Tag.Unknown:
                    invalid = value.Length != 0;
                    break;

                case Tag.BegCollection:
                    // TBD: check that this is a valid collection attribute.
                    invalid = false;
                    break;

                default:
                    throw new IPPException(StatusCode.ClientErrorBadRequest, "Invalid type in encoding.");
            }

            if (invalid)
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, FormattableString.Invariant($"Invalid encoding for type {type}."))
                {
                    DetailedInternalInfo = FormattableString.Invariant($"Invalid encoding for type {type}. Got {value.Length} bytes of data '{BitConverter.ToString(value).Replace("-", string.Empty)}'")
                };
            }
        }
    }
}
