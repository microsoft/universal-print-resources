//-----------------------------------------------------------------------
// <copyright file="IPPMemberAttribute.cs" company="Microsoft">
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

    public class IppMemberAttribute
    {
        private readonly IppAttribute MemberAttributeImpl;

        /// <summary>
        /// Initializes a new instance of the <see cref="IppMemberAttribute"/> class with no values and member attributes.
        /// </summary>
        public IppMemberAttribute(string attributeName)
        {
            this.MemberAttributeImpl = new IppAttribute(attributeName);
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="IppMemberAttribute"/> class with a value.
        /// </summary>
        public IppMemberAttribute(string attributeName, IppValue value)
            : this(attributeName, new List<IppValue> { value })
        {
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="IppMemberAttribute"/> class with a list of values.
        /// </summary>
        public IppMemberAttribute(string attributeName, List<IppValue> values)
        {
            this.MemberAttributeImpl = new IppAttribute(attributeName, values);
        }

        /// <summary>
        /// Gets the values of the attribute.
        /// </summary>
        public IReadOnlyList<IppValue> Values => this.MemberAttributeImpl.Values;

        /// <summary>
        /// Gets the name of the value, i.e., attribute name.
        /// </summary>
        public string ValueName => this.MemberAttributeImpl.ValueName;

        /// <summary>
        /// Gets the the first value.
        /// </summary>
        public IppValue FirstValue => this.Values.First();

        /// <summary>
        /// Serialize a member attribute.
        /// </summary>
        public void SerializeMemberAttribute(Stream output, int collectionDepth)
        {
            if (this.Values.Count == 0)
            {
                throw new Exception("Values of a member attribute cannot be empty");
            }

            // Setup the member attribute: https://tools.ietf.org/html/rfc8010#section-3.1.6
            this.Values.ElementAt(0).SerializeAsMemberAttribute(output, this.ValueName, collectionDepth);       // The first attribute value carries the name of the attribute

            for (int i = 1; i < this.Values.Count; i++)
            {
                this.Values.ElementAt(i).SerializeAsMemberAttribute(output, string.Empty, collectionDepth);     // Additional attribute values use a name length of 0x0000.
            }
        }

        /// <summary>
        /// Add additional value to the attribute.
        /// </summary>
        /// <param name="newValue">The value to add.</param>
        public void AddAdditionalValue(IppValue ippValue)
        {
            this.MemberAttributeImpl.AddAdditionalValue(ippValue);
        }

        /// <summary>
        /// Gets value indicating whether this is a collection attribute.
        /// </summary>
        public bool IsCollectionAttribute()
        {
            return this.MemberAttributeImpl.IsCollectionAttribute;
        }

        /// <summary>
        /// Compare two attributes.
        /// </summary>
        public override bool Equals(object obj)
        {
            if (obj is IppMemberAttribute other)
            {
                var isAttributeNameEqual = this.ValueName.Equals(other.ValueName, StringComparison.Ordinal);
                var areValuesEqual = this.Values.SequenceEqual(other.Values);
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
        /// Serialize the member attribute to string.
        /// </summary>
        /// <returns>String representation of the attribute.</returns>
        public override string ToString()
        {
            if (this.Values.Count == 0)
            {
                throw new Exception("Values of a member attribute cannot be empty");
            }

            if (this.Values.Count > 1)
            {
                var sb = new StringBuilder();
                if (string.IsNullOrEmpty(this.ValueName))
                {
                    sb.Append(string.Empty);
                }

                sb.AppendFormat(CultureInfo.InvariantCulture, "Member Attribute {0} - Multiple Values:\n", this.ValueName);

                foreach (var value in this.Values)
                {
                    sb.Append("\t\t" + value.ToString());
                }

                return sb.ToString();
            }
            else
            {
                // Single valued attribute
                return string.Format(CultureInfo.InvariantCulture, "\t\tMember Attribute {0}: {1}", this.ValueName, this.FirstValue.ToString());
            }
        }
    }
}
