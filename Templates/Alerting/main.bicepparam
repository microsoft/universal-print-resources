using 'main.bicep'

// ============================================================================
// Universal Print Alerting Infrastructure - Parameters
// ============================================================================

// Required: Log Analytics Workspace name (creates new or reuses existing)
param logAnalyticsWorkspaceName = 'law-universalprint'

// Required: Universal Print service principal Object ID
// ⚠️ IMPORTANT: You must be logged into the CORRECT TENANT before running this command.
//    The Object ID is tenant-specific — running in the wrong tenant returns a different (invalid) value.
// To find the value, run:
//   az login --tenant <your-tenant-id>
//   az ad sp show --id da9b70f6-5323-4ce6-ae5c-88dcc5082966 --query id -o tsv
param universalPrintServicePrincipalObjectId = '<your-service-principal-object-id>'

// Optional: DCR name (defaults to dcrup-<workspace-name>, max 30 chars)
// Uncomment to override:
// param dataCollectionRuleName = 'dcrup-custom'

// Optional: Interactive retention in days for the print job table (30-730, hot storage)
param printJobRetentionInDays = 30

// Optional: Total retention in days for the print job table including archive (30-2556, must be >= printJobRetentionInDays)
param printJobTotalRetentionInDays = 365

// Optional: Resource tags
param tags = {
  purpose: 'Universal Print Alerting'
  deployedBy: 'Bicep'
  environment: 'production'
}
