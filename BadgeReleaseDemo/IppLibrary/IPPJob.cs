//-----------------------------------------------------------------------
// <copyright file="IPPJob.cs" company="Microsoft">
// Copyright (c) Microsoft. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

namespace BadgeReleaseDemo.IppLibrary
{
    using System;
    using System.Collections.Generic;

    /// <summary>
    /// An object of IPP job description and status attribute as described in
    /// https://tools.ietf.org/html/rfc8011#section-5.3.
    /// </summary>
    public class IppJob
    {
        public const int JobStateUnknown = -1;

        public const int JobIdUnknown = 0;

        /// <summary>
        /// Initializes a new instance of the <see cref="IppJob"/> class.
        /// </summary>
        /// <param name="jobAttributeGroup">Optional job attributes.</param>
        /// <param name="operationAttributeGroup">Optional operation attributes.</param>
        public IppJob(IppAttributeGroup jobAttributeGroup = null, IppAttributeGroup operationAttributeGroup = null)
        {
            if (jobAttributeGroup == null)
            {
                return;
            }

            this.JobAttributeGroup = jobAttributeGroup;

            this.OperationAttributeGroup = operationAttributeGroup;

            this.JobStateReasons = new List<string>();

            if (jobAttributeGroup.Attributes.ContainsKey(Common.JobAttributes.JobUri))
            {
                this.JobUri = (string)jobAttributeGroup.Attributes[Common.JobAttributes.JobUri].FirstValue.GetNativeValue();
            }

            if (jobAttributeGroup.Attributes.ContainsKey(Common.JobAttributes.JobId))
            {
                this.JobId = (int)jobAttributeGroup.Attributes[Common.JobAttributes.JobId].FirstValue.GetNativeValue();
            }

            if (jobAttributeGroup.Attributes.ContainsKey(Common.JobAttributes.JobState))
            {
                this.JobState = (int)jobAttributeGroup.Attributes[Common.JobAttributes.JobState].FirstValue.GetNativeValue();
            }

            if (jobAttributeGroup.Attributes.ContainsKey(Common.JobAttributes.JobName))
            {
                this.JobName = jobAttributeGroup.Attributes[Common.JobAttributes.JobName].FirstValue.GetNativeValue().ToString();
            }

            if (jobAttributeGroup.Attributes.ContainsKey(Common.JobAttributes.JobOriginatingUserName))
            {
                this.JobOriginatingUserName = jobAttributeGroup.Attributes[Common.JobAttributes.JobOriginatingUserName].FirstValue.GetNativeValue().ToString();
            }

            if (jobAttributeGroup.Attributes.ContainsKey(Common.JobAttributes.JobOriginatingUserUri))
            {
                this.JobOriginatingUserUri = new Uri(jobAttributeGroup.Attributes[Common.JobAttributes.JobOriginatingUserUri].FirstValue.GetNativeValue().ToString());
            }

            if (jobAttributeGroup.Attributes.ContainsKey(Common.JobAttributes.JobStateReasons))
            {
                var jobStateReasonsAttributeValues = jobAttributeGroup.Attributes[Common.JobAttributes.JobStateReasons].Values;
                foreach (var value in jobStateReasonsAttributeValues)
                {
                    this.JobStateReasons.Add(value.GetNativeValue().ToString());
                }
            }

            // DateTimeAtCreation is always available for a job.
            if (jobAttributeGroup.Attributes.ContainsKey(Common.JobAttributes.DateTimeAtCreation))
            {
                this.DateTimeAtCreation = jobAttributeGroup.Attributes[Common.JobAttributes.DateTimeAtCreation].FirstValue.GetNativeValue().ToString();
            }

            // Service returns unknown ipp type if job is not yet processed.
            if (jobAttributeGroup.Attributes.ContainsKey(Common.JobAttributes.DateTimeAtProcessing) &&
                jobAttributeGroup.Attributes[Common.JobAttributes.DateTimeAtProcessing].FirstValue.ValueType == Tag.DateTime)
            {
                this.DateTimeAtProcessing = jobAttributeGroup.Attributes[Common.JobAttributes.DateTimeAtProcessing].FirstValue.GetNativeValue().ToString();
            }
            else
            {
                this.DateTimeAtProcessing = string.Empty;
            }

            // Service returns unknown ipp type if job is not yet completed.
            if (jobAttributeGroup.Attributes.ContainsKey(Common.JobAttributes.DateTimeAtCompleted) &&
                jobAttributeGroup.Attributes[Common.JobAttributes.DateTimeAtCompleted].FirstValue.ValueType == Tag.DateTime)
            {
                this.DateTimeAtCompleted = jobAttributeGroup.Attributes[Common.JobAttributes.DateTimeAtCompleted].FirstValue.GetNativeValue().ToString();
            }
            else
            {
                this.DateTimeAtCompleted = string.Empty;
            }

            if (jobAttributeGroup.Attributes.ContainsKey(Common.JobAttributes.TimeAtCreation))
            {
                this.TimeAtCreation = this.GetIntOrUnknownValue(jobAttributeGroup, Common.JobAttributes.TimeAtCreation);
            }

            // Service returns no-value ipp type if job is not yet processed.
            if (jobAttributeGroup.Attributes.ContainsKey(Common.JobAttributes.TimeAtProcessing) &&
                jobAttributeGroup.Attributes[Common.JobAttributes.TimeAtProcessing].FirstValue.ValueType == Tag.Integer)
            {
                this.TimeAtProcessing = this.GetIntOrUnknownValue(jobAttributeGroup, Common.JobAttributes.TimeAtProcessing);
            }
            else
            {
                this.TimeAtProcessing = 0;
            }

            // Service returns no-value ipp type if job is not yet completed.
            if (jobAttributeGroup.Attributes.ContainsKey(Common.JobAttributes.TimeAtCompleted) &&
                jobAttributeGroup.Attributes[Common.JobAttributes.TimeAtCompleted].FirstValue.ValueType == Tag.Integer)
            {
                this.TimeAtCompleted = this.GetIntOrUnknownValue(jobAttributeGroup, Common.JobAttributes.TimeAtCompleted);
            }
            else
            {
                this.TimeAtCompleted = 0;
            }
        }

        /// <summary>
        /// Gets or sets see: https://tools.ietf.org/html/rfc8011#section-5.3.2
        /// </summary>
        public string JobUri { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets see: https://tools.ietf.org/html/rfc8011#section-5.3.1
        /// </summary>
        public int JobId { get; set; } = JobIdUnknown;

        /// <summary>
        /// Gets or sets see: https://tools.ietf.org/html/rfc8011#section-5.3.7
        /// </summary>
        public int JobState { get; set; } = JobStateUnknown;

        /// <summary>
        /// Gets or sets see: https://tools.ietf.org/html/rfc8011#section-5.3.8
        /// </summary>
        public List<string> JobStateReasons { get; set; }

        /// <summary>
        /// Gets or sets see: https://tools.ietf.org/html/rfc8011#section-5.3.5
        /// </summary>
        public string JobName { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets see: https://tools.ietf.org/html/rfc8011#section-5.3.6
        /// </summary>
        public string JobOriginatingUserName { get; set; } = string.Empty;

        /// <summary>
        /// Gets or sets the: https://ftp.pwg.org/pub/pwg/candidates/cs-ippjobprinterext3v10-20120727-5100.13.pdf
        /// section 5.3.3.
        /// </summary>
        public Uri JobOriginatingUserUri { get; set; } = null;

        /// <summary>
        /// Gets or sets the creation date time. https://tools.ietf.org/html/rfc8011#section-5.3.14.5
        /// </summary>
        public string DateTimeAtCreation { get; set; }

        /// <summary>
        /// Gets or sets the job processing date time.  https://tools.ietf.org/html/rfc8011#section-5.3.14.6
        /// </summary>
        public string DateTimeAtProcessing { get; set; }

        /// <summary>
        /// Gets or sets the job completed date time.  https://tools.ietf.org/html/rfc8011#section-5.3.14.7
        /// </summary>
        public string DateTimeAtCompleted { get; set; }

        /// <summary>
        /// Gets or sets the creation time. https://tools.ietf.org/html/rfc8011#section-5.3.14.1
        /// </summary>
        public int TimeAtCreation { get; set; } = 0;

        /// <summary>
        /// Gets or sets the processing time. https://tools.ietf.org/html/rfc8011#section-5.3.14.2
        /// </summary>
        public int TimeAtProcessing { get; set; } = 0;

        /// <summary>
        /// Gets or sets the completed time. https://tools.ietf.org/html/rfc8011#section-5.3.14.3
        /// </summary>
        public int TimeAtCompleted { get; set; } = 0;

        /// <summary>
        /// Gets the complete job attributes.
        /// </summary>
        public IppAttributeGroup JobAttributeGroup { get; } = null;

        /// <summary>
        /// Gets the complete operation attributes.
        /// </summary>
        public IppAttributeGroup OperationAttributeGroup { get; } = null;

        /// <summary>
        /// If attribute is unknown then return 0 otherwise attribute value.
        /// </summary>
        private int GetIntOrUnknownValue(IppAttributeGroup jobAttributeGroup, string attributeName)
        {
            object value = jobAttributeGroup.Attributes[attributeName].FirstValue.GetNativeValue();
            int returnInt = 0;

            if (value != null)
            {
                returnInt = (int)value;
            }

            return returnInt;
        }
    }
}
