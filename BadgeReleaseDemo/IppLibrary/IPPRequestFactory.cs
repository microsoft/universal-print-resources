//-----------------------------------------------------------------------
// <copyright file="IPPRequestFactory.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

namespace BadgeReleaseDemo.IppLibrary
{
    using System;
    using System.Collections.Generic;
    using System.IO;
    using System.Threading.Tasks;
    using BadgeReleaseDemo.IppLibrary.Common;

    /// <summary>
    /// Provides implementations for standard IPP INFRA operations
    /// </summary>
    internal class IppRequestFactory : IIppRequestFactory
    {
        /// <summary>
        /// Gets or sets iPP requesting-user-name.
        /// </summary>
        public string RequestingUserName { get; set; }

        /// <summary>
        /// Gets or sets iPP-INFRA requesting-user-uri.
        /// </summary>
        public string RequestingUserUri { get; set; }

        /// <summary>
        /// Gets or sets iPP printer_uri.
        /// </summary>
        public Uri PrinterUri { get; set; }

        /// <summary>
        /// Create Cancel-Job request.
        /// </summary>
        /// <param name="requestId">Request id of the ipp request.</param>
        /// <param name="requestingUserName"></param>
        /// <param name="requestingUserUri">See IPP-INFRA section 5.</param>
        /// <param name="jobId">The id of the job.</param>
        /// <param name="jobUri">The uri of the job.</param>
        /// <returns></returns>
        public async Task<IppRequest> CreateCancelJobRequestAsync(
            int requestId,
            string requestingUserName,
            string requestingUserUri,
            int jobId,
            string jobUri)
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(
                new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));

            if (string.IsNullOrEmpty(jobUri))
            {
                operationAttributeGroup.AddAttribute(
                    new IppAttribute(OperationAttributes.JobId, IppValue.CreateIntegerValue(jobId)));
            }
            else
            {
                operationAttributeGroup.AddAttribute(
                    new IppAttribute(OperationAttributes.JobUri, IppValue.CreateURIValue(jobUri)));
            }

            var request = await IppRequest.CreateAsync(Operation.CancelJob, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            return request;
        }

        /// <summary>
        /// Create Get-Printer-Attributes request.
        /// </summary>
        /// <param name="requestId">Request id of the ipp request.</param>
        /// <param name="requestingUserName"></param>
        /// <param name="requestingUserUri">See IPP-INFRA section 5.</param>
        /// <param name="extraOperationAttributes">Additional operation attributes to included.</param>
        /// <param name="requestedAttributes">Printer attributes requested.</param>
        /// <returns></returns>
        public async Task<IppRequest> CreateGetPrinterAttributesRequestAsync(
                                int requestId,
                                string requestingUserName,
                                string requestingUserUri,
                                List<IppAttribute> extraOperationAttributes,
                                List<IppAttribute> requestedAttributes)
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(
                new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));

            if (extraOperationAttributes != null
                && extraOperationAttributes.Count != 0)
            {
                foreach (var attr in extraOperationAttributes)
                {
                    operationAttributeGroup.AddAttribute(attr);
                }
            }

            /* RequestedAttributes is optional according to IPP. If requestedAttributes is null, IPP service should consider it as requesting "ALL" attributes
            and should return all attributes of printer. Currently, MPS is not doing this and a bug has been created for same.  Bug 20689820 */
            this.AddRequestedAttributesToOperationAttributeGroup(requestedAttributes, operationAttributeGroup);
            var request = await IppRequest.CreateAsync(Operation.GetPrinterAttributes, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            return request;
        }

        /// <summary>
        /// Create Get-Output-Device-Attributes request.
        /// </summary>
        /// <param name="requestId">Request id of the ipp request.</param>
        /// <param name="requestingUserName"></param>
        /// <param name="requestingUserUri">See IPP-INFRA section 5.</param>
        /// <param name="extraOperationAttributes">Additional operation attributes to included.</param>
        /// <param name="requestedAttributes">Printer attributes requested.</param>
        /// <returns></returns>
        public async Task<IppRequest> CreateGetOutputDeviceAttributesRequestAsync(
                                int requestId,
                                string requestingUserName,
                                string requestingUserUri,
                                List<IppAttribute> extraOperationAttributes,
                                List<IppAttribute> requestedAttributes)
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(
                new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));

            if (extraOperationAttributes != null)
            {
                foreach (var attr in extraOperationAttributes)
                {
                    operationAttributeGroup.AddAttribute(attr);
                }
            }

            this.AddRequestedAttributesToOperationAttributeGroup(requestedAttributes, operationAttributeGroup);
            var request = await IppRequest.CreateAsync(Operation.GetOutputDeviceAttributes, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            return request;
        }

        /// <summary>
        /// Create Set-Printer-Attributes request.
        /// </summary>
        /// <param name="requestId">Request id of the ipp request.</param>
        /// <param name="requestingUserName"></param>
        /// <param name="requestingUserUri">See IPP-INFRA section 5.</param>
        /// <param name="attributesToSet">Attributes to set</param>
        /// <returns></returns>
        public async Task<IppRequest> CreateSetPrinterAttributesRequestAsync(
                                int requestId,
                                string requestingUserName,
                                string requestingUserUri,
                                IEnumerable<IppAttribute> attributesToSet)
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(
                new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));

            var request = await IppRequest.CreateAsync(Operation.SetPrinterAttributes, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);

            var attributesGrp = new IppAttributeGroup(Tag.PrinterAttributes);

            foreach (var attr in attributesToSet)
            {
                attributesGrp.AddAttribute(attr);
            }

            request.AttributeGroups.Add(attributesGrp);

            return request;
        }

        /// <summary>
        /// Create Get-Printer-Supported-Values request.
        /// </summary>
        /// <param name="requestId">Request id of the ipp request.</param>
        /// <param name="requestingUserName"></param>
        /// <param name="requestingUserUri">See IPP-INFRA section 5.</param>
        /// <param name="requestedAttributes">Printer attributes requested.</param>
        /// <returns></returns>
        public async Task<IppRequest> CreateGetSupportedPrinterAttributesRequestAsync(
                                int requestId,
                                string requestingUserName,
                                string requestingUserUri,
                                List<IppAttribute> requestedAttributes)
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(
                new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));

            if (requestedAttributes != null)
            {
                this.AddRequestedAttributesToOperationAttributeGroup(requestedAttributes, operationAttributeGroup);
            }

            var request = await IppRequest.CreateAsync(Operation.GetPrinterSupportedValues, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            return request;
        }

        /// <summary>
        /// Create Get-Printer-Device-Capabilities request.
        /// </summary>
        /// <param name="requestId">Request id of the ipp request.</param>
        /// <param name="requestingUserName"></param>
        /// <param name="requestingUserUri">See IPP-INFRA section 5.</param>
        public async Task<IppRequest> CreateGetPrinterDeviceCapabilitiesRequestAsync(
                                int requestId,
                                string requestingUserName,
                                string requestingUserUri)
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(
                new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));

            var request = await IppRequest.CreateAsync(Operation.GetPrintDeviceCapabilities, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            return request;
        }

#pragma warning disable SA1515 // Single-line comment must be preceded by blank line
#pragma warning disable SA1614 // Element parameter documentation must have text
        /// <summary>
        /// Create Print-Job operation (https://tools.ietf.org/html/rfc8011#section-4.2.1).
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="jobName"></param>
        /// <param name="documentName"></param>
        /// <param name="documentPayload"></param>
        /// <param name="extraOperationAttributes"></param>
        /// <param name="jobTemplateAttributes"></param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreatePrintJobRequestAsync(
            int requestId,
            string jobName,
            string documentName,
            Stream documentPayload,
            IppAttributeGroup extraOperationAttributes = null,
            IppAttributeGroup jobTemplateAttributes = null)
#pragma warning restore SA1614 // Element parameter documentation must have text
#pragma warning restore SA1515 // Single-line comment must be preceded by blank line
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));
            operationAttributeGroup.AddAttribute(new IppAttribute(JobAttributes.JobName, IppValue.CreateURIValue(jobName)));
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.DocumentName, IppValue.CreateURIValue(documentName)));

            if (extraOperationAttributes != null)
            {
                foreach (var attr in extraOperationAttributes.Attributes)
                {
                    operationAttributeGroup.AddAttribute(attr.Value);
                }
            }

            var request = await IppRequest.CreateAsync(Operation.PrintJob, requestId, documentPayload);
            request.AttributeGroups.Add(operationAttributeGroup);

            if (jobTemplateAttributes != null)
            {
                request.AttributeGroups.Add(jobTemplateAttributes);
            }

            return request;
        }

#pragma warning disable SA1515 // Single-line comment must be preceded by blank line
#pragma warning disable SA1614 // Element parameter documentation must have text
        /// <summary>
        /// Create Validate-Job operation (https://tools.ietf.org/html/rfc8011#section-4.2.3).
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="jobName"></param>
        /// <param name="documentName"></param>
        /// <param name="extraOperationAttributes"></param>
        /// <param name="jobTemplateAttributes"></param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateValidateJobRequestAsync(
            int requestId,
            string jobName,
            string documentName,
            IppAttributeGroup extraOperationAttributes = null,
            IppAttributeGroup jobTemplateAttributes = null)
#pragma warning restore SA1614 // Element parameter documentation must have text
#pragma warning restore SA1515 // Single-line comment must be preceded by blank line
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));
            operationAttributeGroup.AddAttribute(new IppAttribute(JobAttributes.JobName, IppValue.CreateURIValue(jobName)));
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.DocumentName, IppValue.CreateURIValue(documentName)));

            if (extraOperationAttributes != null)
            {
                foreach (var attr in extraOperationAttributes.Attributes)
                {
                    operationAttributeGroup.AddAttribute(attr.Value);
                }
            }

            var request = await IppRequest.CreateAsync(Operation.ValidateJob, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);

            if (jobTemplateAttributes != null)
            {
                request.AttributeGroups.Add(jobTemplateAttributes);
            }

            return request;
        }

#pragma warning disable SA1515 // Single-line comment must be preceded by blank line
#pragma warning disable SA1614 // Element parameter documentation must have text
        /// <summary>
        /// Create Create-Job operation (https://tools.ietf.org/html/rfc8011#section-4.2.4).
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="jobName"></param>
        /// <param name="jobTemplateAttributes"></param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateCreateJobRequestAsync(
            int requestId,
            string jobName = null,
            IppAttributeGroup jobTemplateAttributes = null)
#pragma warning restore SA1614 // Element parameter documentation must have text
#pragma warning restore SA1515 // Single-line comment must be preceded by blank line
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();

            // As per https://www.rfc-editor.org/rfc/rfc8011.html#section-4.1.5, printer-uri must be third operation attribute.
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));
            this.AddUserNameAndUserUri(operationAttributeGroup);
            if (jobName != null)
            {
                operationAttributeGroup.AddAttribute(new IppAttribute(JobAttributes.JobName, IppValue.CreateURIValue(jobName)));
            }

            var request = await IppRequest.CreateAsync(Operation.CreateJob, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            if (jobTemplateAttributes != null)
            {
                request.AttributeGroups.Add(jobTemplateAttributes);
            }

            return request;
        }

#pragma warning disable SA1515 // Single-line comment must be preceded by blank line
#pragma warning disable SA1614 // Element parameter documentation must have text
        /// <summary>
        /// Create Send-Document request.
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="lastDocument"></param>
        /// <param name="jobUri">jobUri</param>
        /// <param name="jobId">jobId</param>
        /// <param name="documentPayload">documentPayload</param>
        /// <param name="extraOperationAttributes">Attributes to be included in the operation attribute group.</param>
        /// <param name="jobTemplateAttributes">The job template attributes to be included in the request.</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateSendDocumentRequestAsync(
            int requestId,
            bool lastDocument,
            string jobUri = null,
            int jobId = 0,
            Stream documentPayload = null,
            IppAttributeGroup extraOperationAttributes = null,
            IppAttributeGroup jobTemplateAttributes = null)
#pragma warning restore SA1614 // Element parameter documentation must have text
#pragma warning restore SA1515 // Single-line comment must be preceded by blank line
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddJobUriOrId(jobUri, jobId, operationAttributeGroup);
            this.AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.LastDocument, IppValue.CreateBooleanValue(lastDocument)));
            if (extraOperationAttributes != null)
            {
                foreach (var attr in extraOperationAttributes.Attributes)
                {
                    operationAttributeGroup.AddAttribute(attr.Value);
                }
            }

            var request = await IppRequest.CreateAsync(Operation.SendDocument, requestId, documentPayload);
            request.AttributeGroups.Add(operationAttributeGroup);
            if (jobTemplateAttributes != null)
            {
                request.AttributeGroups.Add(jobTemplateAttributes);
            }

            return request;
        }

        /// <summary>
        /// Create Close-Job request.
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="jobUri">jobUri</param>
        /// <param name="jobId">jobId</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateCloseJobRequestAsync(
            int requestId,
            string jobUri = null,
            int jobId = 0)
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddJobUriOrId(jobUri, jobId, operationAttributeGroup);
            this.AddUserNameAndUserUri(operationAttributeGroup);

            var request = await IppRequest.CreateAsync(Operation.CloseJob, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            return request;
        }

#pragma warning disable SA1515 // Single-line comment must be preceded by blank line
#pragma warning disable SA1614 // Element parameter documentation must have text
        /// <summary>
        /// Create Get-Job-AttributeGroups operation (https://tools.ietf.org/html/rfc8011#section-4.3.4).
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="jobUri"></param>
        /// <param name="requestedAttributes"></param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateGetJobAttributesRequestAsync(int requestId, string jobUri, List<IppAttribute> requestedAttributes)
#pragma warning restore SA1614 // Element parameter documentation must have text
#pragma warning restore SA1515 // Single-line comment must be preceded by blank line
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(new IppAttribute(JobAttributes.JobUri, IppValue.CreateURIValue(jobUri)));

            this.AddRequestedAttributesToOperationAttributeGroup(requestedAttributes, operationAttributeGroup);
            var request = await IppRequest.CreateAsync(Operation.GetJobAttributes, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            return request;
        }

        /// <summary>
        /// Create Get-Jobs request.
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="jobType">
        ///     Determine the value of "which-jobs"
        ///     See: section 8.2 http://ftp.pwg.org/pub/pwg/candidates/cs-ippinfra10-20150619-5100.18.pdf
        /// </param>
        /// <param name="requestingUserName">See IPP-INFRA section 5.
        ///     All of the new operations defined in this section are sent by the Proxy to the Infrastructure
        ///     Printer.  For each operation, the "requesting-user-name" [RFC2911] and "requesting-useruri"
        ///     [PWG5100.13] operation attributes provide the unauthenticated identity of the Proxy
        ///     owner, e.g., "Jane Smith" and "mailto:jane.smith@example.com".
        /// </param>
        /// <param name="requestingUserUri">See IPP-INFRA section 5.</param>
        /// <param name="printerUri">Value for printer-uri attribute.</param>
        /// <param name="outputDeviceUuid">Value for output-device-uuid attribute (required for get-jobs requests from IPP-INFRA printers).</param>
        /// <param name="requestedAttributes">Job attributes requested.</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateGetJobsRequestAsync(
                                int requestId,
                                string jobType,
                                string requestingUserName,
                                string requestingUserUri,
                                string printerUri,
                                string outputDeviceUuid,
                                List<IppAttribute> requestedAttributes)
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddUserNameAndUserUri(operationAttributeGroup);

            if (!string.IsNullOrEmpty(requestingUserUri))
            {
                operationAttributeGroup.AddAttribute(
                    new IppAttribute(OperationAttributes.MyJobs, IppValue.CreateBooleanValue(true)));
            }

            // Use printerUri value if provided.
            var printerUriToUse = string.IsNullOrEmpty(printerUri) ? this.PrinterUri.ToString() : printerUri;
            operationAttributeGroup.AddAttribute(
                new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(printerUriToUse)));

            // Add output-device-uuid if provided.
            if (!string.IsNullOrEmpty(outputDeviceUuid))
            {
                operationAttributeGroup.AddAttribute(
                    new IppAttribute(OperationAttributes.OutputDeviceUuid, IppValue.CreateCharsetValue(CreateOutputDeviceUuidUri(outputDeviceUuid).ToString())));
            }

            if (!string.IsNullOrEmpty(jobType))
            {
                operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.WhichJobs, IppValue.CreateKeywordValue(jobType)));
            }

            this.AddRequestedAttributesToOperationAttributeGroup(requestedAttributes, operationAttributeGroup);
            var request = await IppRequest.CreateAsync(Operation.GetJobs, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            return request;
        }

        /// <summary>
        /// Creates a Fetch-Job request
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="outputDeviceUuid">The identify of the output device for the request.</param>
        /// <param name="jobId">The id of the job.</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateFetchJobRequestAsync(int requestId, string outputDeviceUuid, int jobId)
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));
            operationAttributeGroup.AddAttribute(
                new IppAttribute(OperationAttributes.OutputDeviceUuid, IppValue.CreateCharsetValue(CreateOutputDeviceUuidUri(outputDeviceUuid).ToString())));
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.JobId, IppValue.CreateIntegerValue(jobId)));

            var request = await IppRequest.CreateAsync(Operation.FetchJob, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            return request;
        }

        /// <summary>
        /// Create IPP-INFRA Acknowledge-Job request.
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="outputDeviceUuid">The identify of the output device for the request.</param>
        /// <param name="jobId">The id of the job.</param>
        /// <param name="fetchStatusCode">See IPP-INFRA section 5.3.1 Acknowledge-Job Request.</param>
        /// <param name="fetchStatusMessage">See IPP-INFRA section 5.3.1 Acknowledge-Job Request. again</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateAcknowledgeJobRequestAsync(int requestId, string outputDeviceUuid, int jobId, StatusCode fetchStatusCode, string fetchStatusMessage)
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));
            operationAttributeGroup.AddAttribute(
                new IppAttribute(OperationAttributes.OutputDeviceUuid, IppValue.CreateCharsetValue(CreateOutputDeviceUuidUri(outputDeviceUuid).ToString())));
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.JobId, IppValue.CreateIntegerValue(jobId)));

            // Undefined means the caller is not sending any value for fetchStatusCode.
            if (fetchStatusCode != StatusCode.Undefined)
            {
                operationAttributeGroup.AddAttribute(
                    new IppAttribute(OperationAttributes.FetchStatusCode, IppValue.CreateEnumValue((int)fetchStatusCode)));
            }

            // Include optional fetch-status-message attribute.
            if (string.IsNullOrEmpty(fetchStatusMessage) == false)
            {
                operationAttributeGroup.AddAttribute(
                    new IppAttribute(OperationAttributes.FetchStatusMessage, IppValue.CreateTextWithoutLanguageValue(fetchStatusMessage)));
            }

            var request = await IppRequest.CreateAsync(Operation.AcknowledgeJob, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            return request;
        }

        /// <summary>
        /// Create IPP-INFRA Acknowledge-Document request.
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="outputDeviceUuid">The identify of the output device for the request.</param>
        /// <param name="jobId">The id of the job.</param>
        /// <param name="documentNumber">The document number (a job can have multiple documents).</param>
        /// <param name="fetchStatusCode">See IPP-INFRA section 5.3.1 Acknowledge-Job Request.</param>
        /// <param name="fetchStatusMessage">See IPP-INFRA section 5.3.1 Acknowledge-Job Request. again</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateAcknowledgeDocumentRequestAsync(
                int requestId, string outputDeviceUuid, int jobId, int documentNumber, StatusCode fetchStatusCode, string fetchStatusMessage)
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));
            operationAttributeGroup.AddAttribute(
                new IppAttribute(OperationAttributes.OutputDeviceUuid, IppValue.CreateCharsetValue(CreateOutputDeviceUuidUri(outputDeviceUuid).ToString())));
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.JobId, IppValue.CreateIntegerValue(jobId)));
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.DocumentNumber, IppValue.CreateIntegerValue(documentNumber)));

            // Undefined means the caller is not sending any value for fetchStatusCode.
            if (fetchStatusCode != StatusCode.Undefined)
            {
                operationAttributeGroup.AddAttribute(
                    new IppAttribute(OperationAttributes.FetchStatusCode, IppValue.CreateEnumValue((int)fetchStatusCode)));
            }

            // Include optional fetch-status-message attribute.
            if (string.IsNullOrEmpty(fetchStatusMessage) == false)
            {
                operationAttributeGroup.AddAttribute(
                    new IppAttribute(OperationAttributes.FetchStatusMessage, IppValue.CreateTextWithoutLanguageValue(fetchStatusMessage)));
            }

            var request = await IppRequest.CreateAsync(Operation.AcknowledgeDocument, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            return request;
        }

        /// <summary>
        /// Create IPP-INFRA Fetch-Document request.
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="outputDeviceUuid">The identify of the output device for the request.</param>
        /// <param name="jobId">The id of the job.</param>
        /// <param name="documentNumber">The document number (a job can have multiple documents).</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateFetchDocumentRequestAsync(int requestId, string outputDeviceUuid, int jobId, int documentNumber)
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));
            operationAttributeGroup.AddAttribute(
                new IppAttribute(OperationAttributes.OutputDeviceUuid, IppValue.CreateCharsetValue(CreateOutputDeviceUuidUri(outputDeviceUuid).ToString())));
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.DocumentNumber, IppValue.CreateIntegerValue(documentNumber)));
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.JobId, IppValue.CreateIntegerValue(jobId)));

            var request = await IppRequest.CreateAsync(Operation.FetchDocument, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            return request;
        }

        /// <summary>
        /// Creates an Update-Output-device-attributes request
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="outputDeviceUuid">The identify of the output device for the request.</param>
        /// <param name="optionalPrinterAttributes"> additional attributes</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateUpdateOutputDeviceAttributesRequestAsync(int requestId, string outputDeviceUuid, IppAttributeGroup optionalPrinterAttributes)
        {
            // REQUIRED (common): (Lang+Charset), "printer-uri", "output-device-uuid"
            // OPTIONAL (common): (UserName+Uri) "requesting-user-name", "requesting-user-uri"
            // OPTIONAL (group1): "printer-name", "copies-supported", "color-supported", "duplex-supported"

            // Generate the required required operation attributes
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));

            // 'outputDeviceUuid' (aka., Device Id) is really the AADID
            operationAttributeGroup.AddAttribute(
                new IppAttribute(OperationAttributes.OutputDeviceUuid, IppValue.CreateCharsetValue(CreateOutputDeviceUuidUri(outputDeviceUuid).ToString())));

            // Generate a request for the caller with the supplied information
            return await this.CreateUpdateRequestInternalAsync(Operation.UpdateOutputDeviceAttributes, requestId, operationAttributeGroup, optionalPrinterAttributes);
        }

        /// <summary>
        /// Creates an Get-Active-Jobs-Request
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="outputDeviceUuid">The identify of the output device for the request.</param>
        /// <param name="optionalOperationAttributes">additional attributes</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateUpdateActiveJobsRequestAsync(int requestId, string outputDeviceUuid, IppAttributeGroup optionalOperationAttributes)
        {
            // REQUIRED (common): (Lang+Charset), "printer-uri", "output-device-uuid"
            // OPTIONAL (group1): (UserName+Uri), "job-ids", "output-device-job-states", "output-device-job-reasons"
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(
                new IppAttribute(OperationAttributes.OutputDeviceUuid, IppValue.CreateCharsetValue(CreateOutputDeviceUuidUri(outputDeviceUuid).ToString())));

            if (optionalOperationAttributes != null)
            {
                foreach (var attr in optionalOperationAttributes.Attributes)
                {
                    operationAttributeGroup.AddAttribute(attr.Value);
                }
            }

            return await this.CreateUpdateRequestInternalAsync(Operation.UpdateActiveJobs, requestId, operationAttributeGroup, null);
        }

        /// <summary>
        /// Creates a Update-Doument-Status request
        /// </summary>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public IppRequest CreateUpdateDocumentStatusRequest()
        {
            // REQUIRED (common): (Lang+Charset), "printer-uri", "output-device-uuid"
            // REQUIRED (group1): "job-id", "document-number"
            // OPTIONAL (group1): (UserName+Uri)
            // OPTIONAL (subset of group2): "pages-completed", "output-device-document-state", "output-device-document-state-reasons"
            throw new NotImplementedException();
        }

        /// <summary>
        /// Creates a Update-Job-Status request
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="outputDeviceUuid">The identify of the output device for the request.</param>
        /// <param name="optionalJobAttributes">additional attributes</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateUpdateJobStatusRequestAsync(int requestId, string outputDeviceUuid, IppAttributeGroup optionalJobAttributes)
        {
            // REQUIRED (common): (Lang+Charset), "printer-uri", "output-device-uuid"
            // REQUIRED (group1): "job-id"
            // OPTIONAL (group1): (UserName+Uri)
            // OPTIONAL (subset of group2): "job-pages-completed", "output-device-job-state", "output-device-job-reasons"
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(new IppAttribute(
                OperationAttributes.OutputDeviceUuid, IppValue.CreateTextWithoutLanguageValue(CreateOutputDeviceUuidUri(outputDeviceUuid).ToString())));

            if (optionalJobAttributes != null)
            {
                // If there is JobId in the JobAttributes group, move it to Operation group
                if (optionalJobAttributes.Attributes.ContainsKey(JobAttributes.JobId))
                {
                    var jobId = optionalJobAttributes.Attributes[JobAttributes.JobId];
                    operationAttributeGroup.AddAttribute(jobId);
                    optionalJobAttributes.RemoveAttribute(JobAttributes.JobId);
                }
            }

            return await this.CreateUpdateRequestInternalAsync(Operation.UpdateJobStatus, requestId, operationAttributeGroup, optionalJobAttributes);
        }

        /// <summary>
        /// Creates Microsoft's custom Set-Printer-Device-Capabilities request.
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="outputDeviceUuid">The identify of the output device for the request.</param>
        /// <param name="data">The PDC stream.</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateSendPdcRequestAsync(int requestId, string outputDeviceUuid, Stream pdcData)
        {
            var request = await this.CreateDataRequestAsync(Operation.SetPrintDeviceCapabilities, requestId, outputDeviceUuid, pdcData);
            return request;
        }

        /// <summary>
        /// Creates Microsoft's custom Set-Print-Capabilities request.
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="outputDeviceUuid">The identify of the output device for the request.</param>
        /// <param name="data">The PC stream.</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateSendPcRequestAsync(int requestId, string outputDeviceUuid, Stream pcData)
        {
            var request = await this.CreateDataRequestAsync(Operation.SetPrintCapabilities, requestId, outputDeviceUuid, pcData);
            return request;
        }

        /// <summary>
        /// Creates a Create-Printer-Subscriptions request
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="optionalSubscriptionAttributeGroups">additional attributes</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateSubscriptionRelatedRequestAsync(Operation operation, int requestId, List<IppAttributeGroup> optionalSubscriptionAttributeGroups)
        {
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));
            var request = await IppRequest.CreateAsync(operation, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            if (optionalSubscriptionAttributeGroups != null)
            {
                foreach (var attrGroup in optionalSubscriptionAttributeGroups)
                {
                    request.AttributeGroups.Add(attrGroup);
                }
            }

            return request;
        }

        /// <summary>
        ///
        /// </summary>
        /// <param name="operation"></param>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="operationAttributes"></param>
        /// <param name="optionalAttributes"></param>
        /// <returns></returns>
        private async Task<IppRequest> CreateUpdateRequestInternalAsync(Operation operation, int requestId, IppAttributeGroup operationAttributes, IppAttributeGroup optionalAttributes)
        {
            var request = await IppRequest.CreateAsync(operation, requestId);
            request.AttributeGroups.Add(operationAttributes);
            if (optionalAttributes != null)
            {
                request.AttributeGroups.Add(optionalAttributes);
            }

            return request;
        }

        /// <summary>
        /// Add user name and/or user uri to the provided operation attribute group.
        /// </summary>
        /// <param name="operationAttributeGroup">Attribute group to add the user name and uri attributes.</param>
        private void AddUserNameAndUserUri(IppAttributeGroup operationAttributeGroup)
        {
            // The user name and user uri are initialized in CreateIppRequestFactory call.
            if (!string.IsNullOrEmpty(this.RequestingUserName))
            {
                operationAttributeGroup.AddAttribute(new IppAttribute(
                    OperationAttributes.RequestingUserName,
                    IppValue.CreateURIValue(this.RequestingUserName)));
            }

            if (!string.IsNullOrEmpty(this.RequestingUserUri))
            {
                operationAttributeGroup.AddAttribute(new IppAttribute(
                    OperationAttributes.RequestingUserUri,
                    IppValue.CreateURIValue(this.RequestingUserUri)));
            }
        }

        /// <summary>
        /// Creates a minimal IPP request with a data payload.
        /// </summary>
        /// <param name="operation">The type of IPP operation to create.</param>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="outputDeviceUuid">The identify of the output device for the request.</param>
        /// <param name="data">The PC stream.</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        public async Task<IppRequest> CreateDataRequestAsync(Operation operation, int requestId, string outputDeviceUuid, Stream data)
        {
            // REQUIRED (common): (Lang+Charset), "printer-uri", "output-device-uuid"
            var operationAttributeGroup = Helpers.CreateOperationAttributes();
            this.AddUserNameAndUserUri(operationAttributeGroup);
            operationAttributeGroup.AddAttribute(new IppAttribute(
                OperationAttributes.OutputDeviceUuid, IppValue.CreateTextWithoutLanguageValue(CreateOutputDeviceUuidUri(outputDeviceUuid).ToString())));

            var request = await IppRequest.CreateAsync(operation, requestId);
            request.AttributeGroups.Add(operationAttributeGroup);
            request.Data = data;
            return request;
        }

        /// <summary>
        /// Create URI format of output-device-uuid.
        /// Example: urn:uuid:01234567-89AB-CDEF-FEDC-BA9876543210.
        /// </summary>
        /// <param name="outputdeviceUuid">Plain uuid.</param>
        /// <returns></returns>
        private static Uri CreateOutputDeviceUuidUri(string outputdeviceUuid)
        {
            const string urnScheme = "urn:";
            const string uuidPrefix = "uuid:";
            return new UriBuilder(urnScheme + uuidPrefix + outputdeviceUuid).Uri;
        }

        /// <summary>
        /// Adds the given list of requested attributes to the operation attributes group of the request
        /// </summary>
        /// <param name="requestedAttributes">Reqeusted attributes to be sent in the request</param>
        /// <param name="operationAttributeGroup">Operation attribute group of the request</param>
        private void AddRequestedAttributesToOperationAttributeGroup(List<IppAttribute> requestedAttributes, IppAttributeGroup operationAttributeGroup)
        {
            if (requestedAttributes?.Count > 0)
            {
                var requestedAttributesCollection = new IppAttribute(OperationAttributes.RequestedAttributes, IppValue.CreateKeywordValue(requestedAttributes[0].ValueName));
                foreach (var reqAttribute in requestedAttributes.GetRange(1, requestedAttributes.Count - 1))
                {
                    requestedAttributesCollection.AddAdditionalValue(IppValue.CreateKeywordValue(reqAttribute.ValueName));
                }

                operationAttributeGroup.AddAttribute(requestedAttributesCollection);
            }
        }

        private void AddJobUriOrId(string jobUri, int jobId, IppAttributeGroup operationAttributeGroup)
        {
            // See https://www.rfc-editor.org/rfc/rfc8011.html#section-4.1.5
            // for operation target attributes and their ordering
            if (!((!string.IsNullOrEmpty(jobUri)) ^ (jobId != 0)))
            {
                throw new ArgumentException("Either the job-uri or job-id must be provided, but not both.");
            }

            if (string.IsNullOrEmpty(jobUri))
            {
                operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.PrinterUri, IppValue.CreateURIValue(this.PrinterUri.ToString())));
                operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.JobId, IppValue.CreateIntegerValue(jobId)));
            }
            else
            {
                operationAttributeGroup.AddAttribute(new IppAttribute(OperationAttributes.JobUri, IppValue.CreateURIValue(jobUri)));
            }
        }
    }
}