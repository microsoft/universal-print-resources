//-----------------------------------------------------------------------
// <copyright file="IIppRequestFactory.cs" company="Microsoft">
// Copyright (c) Microsoft. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

namespace BadgeReleaseDemo.IppLibrary
{
    using System.Collections.Generic;
    using System.IO;
    using System.Threading.Tasks;

    public interface IIppRequestFactory
    {
        /// <summary>
        /// Create Cancel-Job request.
        /// </summary>
        /// <param name="requestId"></param>
        /// <param name="requestingUserName"></param>
        /// <param name="requestingUserUri"></param>
        /// <param name="jobId"></param>
        /// <param name="jobUri"></param>
        /// <returns></returns>
        Task<IppRequest> CreateCancelJobRequestAsync(int requestId, string requestingUserName, string requestingUserUri,
            int jobId, string jobUri);

        /// <summary>
        /// Create Get-Printer-Attributes request.
        /// </summary>
        /// <param name="requestId"></param>
        /// <param name="requestingUserName"></param>
        /// <param name="requestingUserUri"></param>
        /// <param name="extraOperationAttributes"></param>
        /// <param name="requestedAttributes"></param>
        /// <returns></returns>
        Task<IppRequest> CreateGetPrinterAttributesRequestAsync(
            int requestId, string requestingUserName, string requestingUserUri, List<IppAttribute> extraOperationAttributes, List<IppAttribute> requestedAttributes);

        /// <summary>
        /// Create Get-Output-Device-Attributes request.
        /// </summary>
        /// <param name="requestId"></param>
        /// <param name="requestingUserName"></param>
        /// <param name="requestingUserUri"></param>
        /// <param name="extraOperationAttributes"></param>
        /// <param name="requestedAttributes"></param>
        /// <returns></returns>
        Task<IppRequest> CreateGetOutputDeviceAttributesRequestAsync(
           int requestId, string requestingUserName, string requestingUserUri, List<IppAttribute> extraOperationAttributes, List<IppAttribute> requestedAttributes);

        /// <summary>
        /// Create Get-Printer-Attributes request.
        /// </summary>
        /// <param name="requestId"></param>
        /// <param name="requestingUserName"></param>
        /// <param name="requestingUserUri"></param>
        /// <param name="requestedAttributes"></param>
        /// <returns></returns>
        Task<IppRequest> CreateGetSupportedPrinterAttributesRequestAsync(
           int requestId, string requestingUserName, string requestingUserUri, List<IppAttribute> requestedAttributes);

        /// <summary>
        /// Create Get-Printer-Attributes request.
        /// </summary>
        /// <param name="requestId"></param>
        /// <param name="requestingUserName"></param>
        /// <param name="requestingUserUri"></param>
        /// <param name="attributesToSet"></param>
        /// <returns></returns>
        Task<IppRequest> CreateSetPrinterAttributesRequestAsync(
            int requestId,
            string requestingUserName,
            string requestingUserUri,
            IEnumerable<IppAttribute> attributesToSet);

        /// <summary>
        /// Create Get-Printer-Device-Capabilities request.
        /// </summary>
        /// <param name="requestId"></param>
        /// <param name="requestingUserName"></param>
        /// <param name="requestingUserUri"></param>
        Task<IppRequest> CreateGetPrinterDeviceCapabilitiesRequestAsync(int requestId, string requestingUserName, string requestingUserUri);

        /// <summary>
        /// Create Validate-Job operation (https://tools.ietf.org/html/rfc8011#section-4.2.3).
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="jobName"></param>
        /// <param name="documentName"></param>
        /// <param name="extraOperationAttributes"></param>
        /// <param name="jobTemplateAttributes"></param>
        Task<IppRequest> CreateValidateJobRequestAsync(
            int requestId,
            string jobName,
            string documentName,
            IppAttributeGroup extraOperationAttributes = null,
            IppAttributeGroup jobTemplateAttributes = null);

        /// <summary>
        /// Create Print-Job request.
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="jobName">jobName</param>
        /// <param name="documentName">documentName</param>
        /// <param name="documentPayload">documentPayload</param>
        /// <param name="extraOperationAttributes">Attributes to be included in the operation attribute group.</param>
        /// <param name="jobTemplateAttributes">The job template attributes to be included in the request.</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreatePrintJobRequestAsync(int requestId, string jobName, string documentName,
            Stream documentPayload, IppAttributeGroup extraOperationAttributes, IppAttributeGroup jobTemplateAttributes);

        /// <summary>
        /// Create Create-Job request.
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="jobName">jobName</param>
        /// <param name="jobTemplateAttributes">The job template attributes to be included in the request.</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateCreateJobRequestAsync(int requestId, string jobName = null, IppAttributeGroup jobTemplateAttributes = null);

        /// <summary>
        /// Create Send-Document request.
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="lastDocument">lastDocument</param>
        /// <param name="jobUri">jobUri</param>
        /// <param name="jobId">jobId</param>
        /// <param name="documentPayload">documentPayload</param>
        /// <param name="extraOperationAttributes">Attributes to be included in the operation attribute group.</param>
        /// <param name="jobTemplateAttributes">The job template attributes to be included in the request.</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateSendDocumentRequestAsync(
            int requestId,
            bool lastDocument,
            string jobUri = null,
            int jobId = 0,
            Stream documentPayload = null,
            IppAttributeGroup extraOperationAttributes = null,
            IppAttributeGroup jobTemplateAttributes = null);

        /// <summary>
        /// Create Close-Job request.
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="jobUri">jobUri</param>
        /// <param name="jobId">jobId</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateCloseJobRequestAsync(int requestId, string jobUri = null, int jobId = 0);

        /// <summary>
        /// Create Get-Job-Attributes request.
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="jobUri">jobUri</param>
        /// <param name="requestedAttributes">requestedAttributes</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateGetJobAttributesRequestAsync(int requestId, string jobUri,
            List<IppAttribute> requestedAttributes);

        /// <summary>
        /// Create Get-Jobs request.
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="jobType">jobType</param>
        /// <param name="requestingUserName">requestingUserName</param>
        /// <param name="requestingUserUri">requestingUserUri</param>
        /// <param name="printerUri">printerUri</param>
        /// <param name="outputDeviceUuid">outputDeviceUuid</param>
        /// <param name="requestedAttributes">requestedAttributes</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateGetJobsRequestAsync(int requestId,
            string jobType,
            string requestingUserName,
            string requestingUserUri,
            string printerUri,
            string outputDeviceUuid,
            List<IppAttribute> requestedAttributes);

        /// <summary>
        /// Create Acknowledge-Job request.
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="outputDeviceUuid">outputDeviceUuid</param>
        /// <param name="jobId">jobId</param>
        /// <param name="fetchStatusCode">fetchStatusCode</param>
        /// <param name="fetchStatusMessage">fetchStatusMessage</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateAcknowledgeJobRequestAsync(int requestId, string outputDeviceUuid, int jobId,
            StatusCode fetchStatusCode, string fetchStatusMessage);

        /// <summary>
        /// Create IPP-INFRA Acknowledge-Document request.
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="outputDeviceUuid">outputDeviceUuid</param>
        /// <param name="jobId">jobId</param>
        /// <param name="documentNumber">documentNumber</param>
        /// <param name="fetchStatusCode">fetchStatusCode</param>
        /// <param name="fetchStatusMessage">fetchStatusMessage</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateAcknowledgeDocumentRequestAsync(int requestId, string outputDeviceUuid, int jobId,
            int documentNumber, StatusCode fetchStatusCode, string fetchStatusMessage);

        /// <summary>
        /// Create Fetch-Job request.
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="outputDeviceUuid">outputDeviceUuid</param>
        /// <param name="jobId">jobId</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateFetchJobRequestAsync(int requestId, string outputDeviceUuid, int jobId);

        /// <summary>
        /// Create Fetch-Document request.
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="outputDeviceUuid">outputDeviceUuid</param>
        /// <param name="jobId">jobId</param>
        /// <param name="documentNumber">documentNumber</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateFetchDocumentRequestAsync(int requestId, string outputDeviceUuid, int jobId,
            int documentNumber);

        /// <summary>
        /// Create Update-Output-Device-Attribute request.
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="outputDeviceUuid">outputDeviceUuid</param>
        /// <param name="optionalPrinterAttributes">optionalPrinterAttributes</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateUpdateOutputDeviceAttributesRequestAsync(int requestId, string outputDeviceUuid,
            IppAttributeGroup optionalPrinterAttributes);

        /// <summary>
        /// Create Update-Active-Jobs request.
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="outputDeviceUuid">outputDeviceUuid</param>
        /// <param name="optionalOperationAttributes">optionalOperationAttributes</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateUpdateActiveJobsRequestAsync(int requestId, string outputDeviceUuid, IppAttributeGroup optionalOperationAttributes);

        /// <summary>
        /// Create Update-Document-Status request.
        /// </summary>
        /// <returns><see cref="IppRequest"/> representation</returns>
        IppRequest CreateUpdateDocumentStatusRequest();

        /// <summary>
        /// Create Update-Job-Status request
        /// </summary>
        /// <param name="requestId">requestId</param>
        /// <param name="outputDeviceUuid">outputDeviceUuid</param>
        /// <param name="optionalJobAttributes">optionalJobAttributes</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateUpdateJobStatusRequestAsync(int requestId, string outputDeviceUuid, IppAttributeGroup optionalJobAttributes);

        /// <summary>
        /// Creates Microsoft's custom Set-Print-Device-Capabilities request.
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="outputDeviceUuid">The identify of the output device for the request.</param>
        /// <param name="data">The PDC stream.</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateSendPdcRequestAsync(int requestId, string outputDeviceUuid, Stream pdcData);

        /// <summary>
        /// Creates Microsoft's custom Set-Print-Capabilities request.
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="outputDeviceUuid">The identify of the output device for the request.</param>
        /// <param name="data">The PC stream.</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateSendPcRequestAsync(int requestId, string outputDeviceUuid, Stream pcData);

        /// <summary>
        /// Creates a Subscriptions related request
        /// </summary>
        /// <param name="requestId">Request id of the IPP packet.</param>
        /// <param name="optionalSubscriptionAttributeGroups">additional attributes</param>
        /// <returns><see cref="IppRequest"/> representation</returns>
        Task<IppRequest> CreateSubscriptionRelatedRequestAsync(Operation operation, int requestId, List<IppAttributeGroup> optionalSubscriptionAttributeGroups);
    }
}
