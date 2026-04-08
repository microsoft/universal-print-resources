//-----------------------------------------------------------------------
// <copyright file="IPPAttributeGroup.cs" company="Microsoft">
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

    public class IppAttributeGroup
    {
        private const string LexmarkStringForDuplicateAttributeException = "Lexmark";

        /// <summary>
        /// Contains 0 or more IPPAttributes associated with this Attribute Group
        /// TBD: consider ConcurrentDictionary() remove the need to create new APIs for Add, Remove, and Replace. [Tracked by: 19959905]
        /// </summary>
        private Dictionary<string, IppAttribute> attributes;

        /// <summary>
        /// Initializes a new instance of the <see cref="IppAttributeGroup"/> class.
        /// </summary>
        /// <param name="attributeType">The attribute type of the group.</param>
        public IppAttributeGroup(Tag attributeType)
        {
            this.Type = attributeType;
            this.attributes = new Dictionary<string, IppAttribute>();
        }

        /// <summary>
        /// Gets or sets the type of this Attribute Group
        /// </summary>
        public Tag Type { get; set; }

        /// <summary>
        /// Gets the attributes of the group.
        /// </summary>
        public IReadOnlyDictionary<string, IppAttribute> Attributes => (IReadOnlyDictionary<string, IppAttribute>)this.attributes;

        /// <summary>
        /// Add an attribute to the group.
        /// </summary>
        /// <param name="attribute">The attribute to add.</param>
        public void AddAttribute(IppAttribute attribute)
        {
            // Sanity check: duplicate attributes are not allowed (we're allowed to ignore them
            // or to return an error, I'm opting for an error..)
            if (this.attributes.ContainsKey(attribute.ValueName))
            {
                if (attribute.ValueName.Contains(LexmarkStringForDuplicateAttributeException))
                {
                    // skip attribute for Lexmark native printers due to bug in their firmware
                    // IcM: https://portal.microsofticm.com/imp/v3/incidents/details/264596539/home
                    return;
                }

                throw new IPPException(StatusCode.ClientErrorBadRequest, "Duplicate attribute name in IPP message:" + attribute.ValueName);
            }

            this.attributes.Add(attribute.ValueName, attribute);
        }

        /// <summary>
        /// Remove an attribute from attribute list.
        /// </summary>
        /// <param name="attributeName">The name of the attribute to be removed.</param>
        public void RemoveAttribute(string attributeName)
        {
            if (this.attributes.ContainsKey(attributeName))
            {
                this.attributes.Remove(attributeName);
            }
        }

        /// <summary>
        /// Replace an attribute.
        /// </summary>
        /// <param name="attribute">The new attribute object.</param>
        public void ReplaceAttribute(IppAttribute attribute)
        {
            this.RemoveAttribute(attribute.ValueName);
            this.AddAttribute(attribute);
        }

        /// <summary>
        /// Serialize the attribute group.
        /// </summary>
        /// <param name="output">The output stream.</param>
        public void Serialize(Stream output)
        {
            // Write the "begin-attribute-group" tag
            output.WriteByte((byte)this.Type);

            // And write out the attributes.
            // The requirement for Tag.OperationAttributes is to serialize the AttributesCharset and AttributesNaturalLanguage first.
            // From RFC 8081: https://tools.ietf.org/html/rfc8011#page-33
            // The "attributes-charset" and "attributes-natural-language" attributes
            // MUST be the first two attributes in every IPP request and response,
            // as part of the initial Operation Attributes group of the IPP message.
            // The "attributes-charset" attribute MUST be the first attribute in the
            // group, and the "attributes-natural-language" attribute MUST be the
            // second attribute in the group.
            if (this.Type == Tag.OperationAttributes)
            {
                if (this.attributes.TryGetValue(OperationAttributes.AttributesCharset, out IppAttribute charsetValue))
                {
                    charsetValue.Serialize(output);
                }

                if (this.attributes.TryGetValue(OperationAttributes.AttributesNaturalLanguage, out IppAttribute langValue))
                {
                    langValue.Serialize(output);
                }
            }

            // The rest of the attributes.
            foreach (var attribute in this.attributes.Values)
            {
                // Except for the AttributesCharset and AttributesNaturalLanguage attributes that are serialized first.
                if (string.CompareOrdinal(attribute.ValueName, OperationAttributes.AttributesCharset) == 0 ||
                    string.CompareOrdinal(attribute.ValueName, OperationAttributes.AttributesNaturalLanguage) == 0)
                {
                    continue;
                }

                attribute.Serialize(output);
            }
        }

        /// <summary>
        /// Serialize to string without IPP attributes that are considered Pii.
        /// </summary>
        /// <returns>The string representation of the attribute group.</returns>
        public override string ToString()
        {
            // The default is to exclude Pii attributes.  This prevents user of this library to accidentally log Pii information.
            return this.ToString(false);
        }

        /// <summary>
        /// Serialize to string with option to include IPP attributes that are considered Pii.
        /// </summary>
        public string ToString(bool includePiiAttributes)
        {
            var sb = new StringBuilder();
            sb.AppendFormat(CultureInfo.InvariantCulture, "Attribute Group: {0}\n", this.Type);

            foreach (var attribute in this.attributes.Values)
            {
                sb.AppendFormat(CultureInfo.InvariantCulture, "  {0}\n", attribute.ToString(includePiiAttributes));
            }

            return sb.ToString();
        }

        /// <summary>
        /// Compare two attribute groups.
        /// </summary>
        public override bool Equals(object obj)
        {
            if (obj is IppAttributeGroup other)
            {
                var isAttributeGroupTypeEqual = this.Type.Equals(other.Type);
                var areAttributesEqual = this.attributes.ToList().SequenceEqual(other.attributes.ToList());
                return isAttributeGroupTypeEqual && areAttributesEqual;
            }

            return false;
        }

        /// <summary>
        /// Avoid warning, need to override when overriding Object.Equals(). Nothing special here, rely on Equals.
        /// Attribute group comparison is used by test code.
        /// </summary>
        public override int GetHashCode()
        {
            return base.GetHashCode();
        }
    }
}
