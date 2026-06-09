// ============================================================================
// Universal Print Alerting Infrastructure
// ============================================================================
// This template deploys the Azure Monitor infrastructure required for 
// Universal Print printer health, print job, and billing summary logging.
//
// Resources created:
// - Log Analytics Workspace
// - Data Collection Rule (DCR) with kind: Direct and custom log tables
// - RBAC role assignment for Universal Print service principal
//
// Schema Version: 0.3.0
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Name of the Log Analytics workspace. If a workspace with this name already exists in the resource group, it will be reused; otherwise a new one is created.')
param logAnalyticsWorkspaceName string

@description('Name of the Data Collection Rule (DCR). Must be 3-30 chars, letters/numbers/hyphens only for kind: Direct.')
@minLength(3)
@maxLength(30)
param dataCollectionRuleName string = take('dcrup-${logAnalyticsWorkspaceName}', 30)

@description('Interactive retention in days for the print job table (hot storage). Other tables use workspace defaults. To customize retention for all tables, use the Azure portal: https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-configure')
@minValue(30)
@maxValue(730)
param printJobRetentionInDays int = 30

@description('Total retention in days for the print job table including archive (must be >= printJobRetentionInDays). Other tables use workspace defaults.')
@minValue(30)
@maxValue(2556)
param printJobTotalRetentionInDays int = 365

@description('Universal Print service principal Object ID. Required for RBAC role assignments that allow data ingestion. Get this value by running: az ad sp show --id da9b70f6-5323-4ce6-ae5c-88dcc5082966 --query id -o tsv (or see Get-Started.md Step 2).')
param universalPrintServicePrincipalObjectId string

@description('Tags to apply to all resources.')
param tags object = {
  purpose: 'Universal Print Alerting'
  deployedBy: 'Bicep'
}

// ============================================================================
// Variables
// ============================================================================

// Monitoring Metrics Publisher role definition ID
var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

// Monitoring Contributor role definition ID - allows updating DCR properties (streams, data flows, transforms)
var monitoringContributorRoleId = '749f88d5-cbae-40b8-bcfc-e573ddc772fa'

// Log Analytics Contributor role definition ID - allows managing custom table schemas
var logAnalyticsContributorRoleId = '92aaf0da-9dab-42b6-94a3-d43ce8d16293'

// Custom table names - aligned with PowerShell scripts
var printerHealthTableName = 'UniversalPrintPrinterHealth_CL'
var printJobTableName = 'UniversalPrintJob_CL'
var billingSummaryTableName = 'UniversalPrintBillingSummary_CL'

// Stream names for DCR
var printerHealthStreamName = 'Custom-UniversalPrintPrinterHealthData'
var printJobStreamName = 'Custom-UniversalPrintJobData'
var billingSummaryStreamName = 'Custom-UniversalPrintBillingSummaryData'

// ============================================================================
// Log Analytics Workspace (creates new or reuses existing idempotently)
// Workspace settings (retention, access control, encryption) use defaults.
// Customize via the Azure portal based on your organization's requirements.
// ============================================================================
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: resourceGroup().location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

// ============================================================================
// Custom Log Tables - Schema aligned with PowerShell scripts
// ============================================================================

// PrinterHealthInformation_CL - Stores printer health events
resource printerHealthTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: logAnalyticsWorkspace
  name: printerHealthTableName
  properties:{
    schema: {
      name: printerHealthTableName
      columns: [
        { 
          name: 'TimeGenerated'
          type: 'datetime'
          description: 'Printer health status generated time stamp'
        }
        { 
          name: 'PrinterId'
          type: 'string'
          description: 'The identifier of the Printer'
        }
        { 
          name: 'PrinterName'
          type: 'string'
          description: 'The name of the Printer'
        }
        { 
          name: 'LocationInfo'
          type: 'dynamic'
          description: 'Location information (structured object for KQL property access)'
        }
        { 
          name: 'PrinterDetails'
          type: 'dynamic'
          description: 'Printer details including ShareIds, ShareNames, ConnectorIds, Manufacturer, Model, RegisteredDateTime'
        }
        { 
          name: 'PrinterStatusDetails'
          type: 'dynamic'
          description: 'Raw IPP printer status: PrinterState, PrinterStateMessage, LastUpdatedDateTime, IsAcceptingJobs, PrinterStateReasonErrors (string[]), PrinterStateReasonWarnings (string[]), PrinterStateReasonReports (string[])'
        }
      ]
    }
    plan: 'Analytics'
  }
}

// PrintJob_CL - Stores print job events
resource printJobTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: logAnalyticsWorkspace
  name: printJobTableName
  properties:{
    schema: {
      name: printJobTableName
      columns: [
        { 
          name: 'TimeGenerated'
          type: 'datetime'
          description: 'Print job event generated time stamp (maps to CreationTime)'
        }
        { 
          name: 'JobLifecycleEvent'
          type: 'string'
          description: 'The job lifecycle event: submitted, readyForPrinter, acquiredByPrinter, or finished'
        }
        { 
          name: 'JobId'
          type: 'string'
          description: 'The identifier of the print job'
        }
        { 
          name: 'PrinterShareId'
          type: 'string'
          description: 'The identifier of the printer share where the job is submitted'
        }
        { 
          name: 'PrinterShareName'
          type: 'string'
          description: 'The name of the printer share where the job is submitted'
        }
        { 
          name: 'PrinterId'
          type: 'string'
          description: 'The identifier of the physical printer where the job is routed for printing (can be null)'
        }
        { 
          name: 'PrinterName'
          type: 'string'
          description: 'The name of the physical printer where the job is routed for printing (can be null)'
        }
        { 
          name: 'CreatedBy'
          type: 'string'
          description: 'The userprincipalname of the job submitter'
        }
        { 
          name: 'CreatedDateTime'
          type: 'datetime'
          description: 'The job creation date time in UTC'
        }
        { 
          name: 'JobState'
          type: 'string'
          description: 'The job state (Graph values): pending, paused, processing, stopped, canceled, aborted, completed'
        }
        {
          name: 'DocumentSizeInBytes'
          type: 'long'
          description: 'The size of the print job document in bytes'
        }
        {
          name: 'ReadyForPrinterDateTime'
          type: 'datetime'
          description: 'The UTC date time when the document became fetchable by the printer (printer was notified about the job)'
        }
        {
          name: 'CompletedDateTime'
          type: 'datetime'
          description: 'The UTC date time when the job reached its terminal state (completed/canceled/aborted)'
        }
        { 
          name: 'Details'
          type: 'dynamic'
          description: 'Print job details including RedirectedFromPrinterId, Copies, PageCount, MediaSheetCount, ColorMode, DuplexMode, DocumentUploadedDateTime, ReleasedDateTime, AcquiredByPrinterDateTime, DocumentDownloadedDateTime, JobStateReasons (string[]), Dpi, Orientation, InputBin, OutputBin, MediaSize, MediaType, Finishings (string[]), PagesPerSheet, MultipageLayout, Collate, Scaling, FeedOrientation, PauseReason (camelCase: heldForRelease or taskTrigger; present on Submitted events for jobs held by 1P pull-print/held-for-release or by a 3P JobStarted task trigger)'
        }
      ]
    }
    plan: 'Analytics'
    retentionInDays: printJobRetentionInDays
    totalRetentionInDays: printJobTotalRetentionInDays
  }
}

// BillingSummary_CL- Stores billing summary events
resource billingSummaryTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: logAnalyticsWorkspace
  name: billingSummaryTableName
  properties:{
    schema: {
      name: billingSummaryTableName
      columns: [
        { 
          name: 'TimeGenerated'
          type: 'datetime'
          description: 'Billing summary event generated time stamp'
        }
        { 
          name: 'UsedPrintJobCount'
          type: 'int'
          description: 'The number of billable print jobs for the billing period'
        }
        { 
          name: 'IncludedPrintJobCount'
          type: 'int'
          description: 'The included print job limit (maximum allowed jobs) for the billing period'
        }
        { 
          name: 'BillingPeriodStartDateTime'
          type: 'datetime'
          description: 'The start date of the billing period'
        }
        { 
          name: 'BillingPeriodEndDateTime'
          type: 'datetime'
          description: 'The end date of the billing period'
        }
      ]
    }
    plan: 'Analytics'
  }
}

// ============================================================================
// Data Collection Rule (DCR)— kind: Direct (uses built-in logsIngestion endpoint)
// ============================================================================
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dataCollectionRuleName
  location: resourceGroup().location
  tags: tags
  kind: 'Direct'
  properties: {
    streamDeclarations: {
      '${printerHealthStreamName}': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'PrinterId', type: 'string' }
          { name: 'PrinterName', type: 'string' }
          { name: 'LocationInfo', type: 'dynamic' }
          { name: 'PrinterDetails', type: 'dynamic' }
          { name: 'PrinterStatusDetails', type: 'dynamic' }
        ]
      }
      '${printJobStreamName}': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'JobLifecycleEvent', type: 'string' }
          { name: 'JobId', type: 'string' }
          { name: 'PrinterShareId', type: 'string' }
          { name: 'PrinterShareName', type: 'string' }
          { name: 'PrinterId', type: 'string' }
          { name: 'PrinterName', type: 'string' }
          { name: 'CreatedBy', type: 'string' }
          { name: 'CreatedDateTime', type: 'datetime' }
          { name: 'JobState', type: 'string' }
          { name: 'DocumentSizeInBytes', type: 'long' }
          { name: 'ReadyForPrinterDateTime', type: 'datetime' }
          { name: 'CompletedDateTime', type: 'datetime' }
          { name: 'Details', type: 'dynamic' }
        ]
      }
      '${billingSummaryStreamName}': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'UsedPrintJobCount', type: 'int' }
          { name: 'IncludedPrintJobCount', type: 'int' }
          { name: 'BillingPeriodStartDateTime', type: 'datetime' }
          { name: 'BillingPeriodEndDateTime', type: 'datetime' }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: 'upworkspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: [printerHealthStreamName]
        destinations: ['upworkspace']
        transformKql: 'source'
        outputStream: 'Custom-${printerHealthTableName}'
      }
      {
        streams: [printJobStreamName]
        destinations: ['upworkspace']
        transformKql: 'source'
        outputStream: 'Custom-${printJobTableName}'
      }
      {
        streams: [billingSummaryStreamName]
        destinations: ['upworkspace']
        transformKql: 'source'
        outputStream: 'Custom-${billingSummaryTableName}'
      }
    ]
  }
  dependsOn: [
    printerHealthTable
    printJobTable
    billingSummaryTable
  ]
}

// ============================================================================
// RBAC: Monitoring Metrics Publisher Role Assignment for Universal Print
// ============================================================================
resource upRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataCollectionRule.id, universalPrintServicePrincipalObjectId, monitoringMetricsPublisherRoleId)
  scope: dataCollectionRule
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalId: universalPrintServicePrincipalObjectId
    principalType: 'ServicePrincipal'
    description: 'Allows Universal Print service to ingest data into this DCR'
  }
}

// ============================================================================
// RBAC: Monitoring Contributor Role Assignment for Universal Print
// Allows updating DCR properties (streams, data flows, transforms) for schema evolution
// ============================================================================
resource upDcrContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataCollectionRule.id, universalPrintServicePrincipalObjectId, monitoringContributorRoleId)
  scope: dataCollectionRule
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringContributorRoleId)
    principalId: universalPrintServicePrincipalObjectId
    principalType: 'ServicePrincipal'
    description: 'Allows Universal Print service to update DCR streams and data flows'
  }
}

// ============================================================================
// RBAC: Log Analytics Contributor Role Assignment for Universal Print
// Allows creating and updating custom table schemas in the workspace
// ============================================================================
resource upWorkspaceContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalyticsWorkspace.id, universalPrintServicePrincipalObjectId, logAnalyticsContributorRoleId)
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsContributorRoleId)
    principalId: universalPrintServicePrincipalObjectId
    principalType: 'ServicePrincipal'
    description: 'Allows Universal Print service to manage custom table schemas'
  }
}

// ============================================================================
// Outputs - Values needed for Universal Print Portal/Graph API configuration
// ============================================================================

@description('Subscription display name - select this in the Universal Print Admin Portal')
output subscriptionName string = subscription().displayName

@description('Subscription ID')
output subscriptionId string = subscription().subscriptionId

@description('Resource group containing the Log Analytics workspace and data collection rule')
output resourceGroupName string = resourceGroup().name

@description('Log Analytics Workspace name - select this in the Universal Print Admin Portal')
output workspaceName string = logAnalyticsWorkspace.name

@description('Data Collection Rule name - select this in the Universal Print Admin Portal')
output dcrName string = dataCollectionRule.name

@description('Printer Health Table Name')
output printerHealthTableName string = printerHealthTableName

@description('Print Job Table Name')
output printJobTableName string = printJobTableName

@description('Billing Summary Table Name')
output billingSummaryTableName string = billingSummaryTableName
