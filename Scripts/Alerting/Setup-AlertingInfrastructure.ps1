<#
.SYNOPSIS
    Creates Azure infrastructure for enabling the Universal Print Logs and Alerts feature.

.DESCRIPTION
    Customer-facing setup script for IT administrators. Provisions all required Azure
    Monitor resources in the customer's subscription so that Universal Print can deliver
    printer health, print job, and billing summary logs.
    
    ⚠️ PERMISSIONS REQUIRED (Azure RBAC)
    ─────────────────────────────────────
    The user running this script must have:
    - Contributor (or Owner) on the target resource group
    - User Access Administrator (or Owner) on the target resource group
    - Microsoft Graph 'Application.Read.All' (or provide -UniversalPrintServicePrincipalObjectId directly)
    
    If the resource group does not exist yet, Contributor on the subscription is also required.
    
    Resources created (if they don't already exist):
    - Resource Group
    - Log Analytics Workspace with custom tables:
      - UniversalPrintPrinterHealth_CL (printer health events)
      - UniversalPrintJob_CL (print job events)
      - UniversalPrintBillingSummary_CL (billing summary events)
    - Data Collection Rule (DCR) with kind: Direct and stream mappings
    
    Permissions assigned:
    - Monitoring Metrics Publisher on DCR (required for data ingestion)
    - Monitoring Contributor on DCR (required for updating DCR schema and stream declarations)
    - Log Analytics Contributor on workspace (required for updating table schemas)

.NOTES
    Version: 0.3.0
    Last Updated: 2026-02-24

.PARAMETER TenantId
    Required. Your Azure Active Directory Tenant ID (GUID format).
    Example: "12345678-1234-1234-1234-123456789012"

.PARAMETER LogAnalyticsSubscription
    Required. The Azure Subscription ID where resources will be created.
    Example: "12345678-1234-1234-1234-123456789012"

.PARAMETER LogAnalyticsLocation
    Required. Azure region for the Log Analytics workspace and related resources.
    Example: "West US 2", "East US", "West Europe"

.PARAMETER LogAnalyticsResourceGroup
    Required. Name of the resource group for the Log Analytics workspace.
    Will be created if it doesn't exist.
    Example: "rg-universalprint-alerting"

.PARAMETER LogAnalyticsWorkspaceName
    Required. Name for the Log Analytics workspace.
    Will be created if it doesn't exist.
    Example: "law-universalprint"

.PARAMETER AzDcrResourceGroup
    Optional. Resource group for the Data Collection Rule.
    Will be created if it doesn't exist.
    Defaults to the same value as LogAnalyticsResourceGroup.

.PARAMETER AzDcrName
    Optional. Name for the Data Collection Rule.
    Will be created if it doesn't exist.
    Defaults to "dcrup-<LogAnalyticsWorkspaceName>".

.EXAMPLE
    .\Setup-AlertingInfrastructure.ps1 `
        -TenantId "12345678-1234-1234-1234-123456789012" `
        -LogAnalyticsSubscription "87654321-4321-4321-4321-210987654321" `
        -LogAnalyticsLocation "West US 2" `
        -LogAnalyticsResourceGroup "rg-universalprint-alerting" `
        -LogAnalyticsWorkspaceName "law-universalprint"

.EXAMPLE
    # With custom DCR name
    .\Setup-AlertingInfrastructure.ps1 `
        -TenantId "12345678-1234-1234-1234-123456789012" `
        -LogAnalyticsSubscription "87654321-4321-4321-4321-210987654321" `
        -LogAnalyticsLocation "East US" `
        -LogAnalyticsResourceGroup "rg-print-monitoring" `
        -LogAnalyticsWorkspaceName "law-print" `
        -AzDcrName "dcrup-print-routing"

.EXAMPLE
    # Deploy to GCC High / DOD environment
    .\Setup-AlertingInfrastructure.ps1 `
        -TenantId "12345678-1234-1234-1234-123456789012" `
        -LogAnalyticsSubscription "87654321-4321-4321-4321-210987654321" `
        -LogAnalyticsLocation "USGov Virginia" `
        -LogAnalyticsResourceGroup "rg-universalprint-alerting" `
        -LogAnalyticsWorkspaceName "law-universalprint" `
        -AzureEnvironment AzureUSGovernment

.OUTPUTS
    The script outputs the following values for Universal Print Admin Portal configuration:
    - Subscription (name and ID)
    - Log Analytics Workspace name (and resource group)
    - Data Collection Rule name (and resource group)

.NOTES
    PERMISSIONS REQUIRED (Azure RBAC, not Entra ID roles):
    - Contributor (or Owner) on the target resource group
    - User Access Administrator (or Owner) on the target resource group
    - Microsoft Graph Application.Read.All (or provide -UniversalPrintServicePrincipalObjectId directly)
    - If the resource group does not exist yet, Contributor on the subscription is also required
    
    SOVEREIGN CLOUD SUPPORT:
    Use -AzureEnvironment to target sovereign clouds:
    - AzureCloud (default) — Public / GCC
    - AzureUSGovernment — GCC High / DOD
    - AzureChinaCloud — China (21Vianet)
    
    PREREQUISITES:
    - Azure PowerShell (Az module) — will be installed automatically if missing
    - Microsoft Graph PowerShell SDK (for permissions) — will be installed automatically if missing
    
    NEXT STEPS:
    After running this script, configure the alerting feature in the Universal Print Admin Portal
    (portal.azure.com for Public, portal.azure.us for GCC High/DOD, portal.azure.cn for China)
    Navigate to: Universal Print > Settings > Logs and alerts
    In the portal, select these from the dropdowns using the values from the output:
    
    - Subscription (name and ID)
    - Log Analytics Workspace name (and resource group)
    - Data Collection Rule name (and resource group)
    
    Also enable the log types you want to receive:
    - PrinterHealth: Printer health status events
    - PrintJob: Print job lifecycle events
    - Billing: Billing summary events
#>

#------------------------------------------------------------------------------------------------------------
# Parameters
#------------------------------------------------------------------------------------------------------------
param(
    [Parameter(Mandatory=$true, HelpMessage="Your Azure AD Tenant ID (GUID format)")]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$TenantId,
    
    [Parameter(Mandatory=$true, HelpMessage="Azure Subscription ID where resources will be created")]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$LogAnalyticsSubscription,
    
    [Parameter(Mandatory=$true, HelpMessage="Azure region (e.g., 'West US 2', 'East US')")]
    [string]$LogAnalyticsLocation,
    
    [Parameter(Mandatory=$true, HelpMessage="Resource group name for Log Analytics workspace")]
    [string]$LogAnalyticsResourceGroup,
    
    [Parameter(Mandatory=$true, HelpMessage="Name for the Log Analytics workspace")]
    [string]$LogAnalyticsWorkspaceName,
    
    [Parameter(Mandatory=$false, HelpMessage="Resource group for DCR (defaults to LogAnalyticsResourceGroup)")]
    [string]$AzDcrResourceGroup = $LogAnalyticsResourceGroup,
    
    [Parameter(Mandatory=$false, HelpMessage="Name for the Data Collection Rule")]
    [string]$AzDcrName = "dcrup-$LogAnalyticsWorkspaceName".Substring(0, [Math]::Min("dcrup-$LogAnalyticsWorkspaceName".Length, 30)),
    
    [Parameter(Mandatory=$false, HelpMessage="Interactive retention in days for the print job table (30-730). Other tables use workspace defaults.")]
    [ValidateRange(30, 730)]
    [int]$PrintJobRetentionInDays = 30,
    
    [Parameter(Mandatory=$false, HelpMessage="Total retention in days for the print job table including archive (must be >= PrintJobRetentionInDays, 30-2556).")]
    [ValidateRange(30, 2556)]
    [int]$PrintJobTotalRetentionInDays = 365,

    [Parameter(Mandatory=$false, HelpMessage="Azure cloud environment. Use 'AzureUSGovernment' for GCC High/DOD, 'AzureChinaCloud' for China. Defaults to 'AzureCloud' (public).")]
    [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')]
    [string]$AzureEnvironment = 'AzureCloud'
)

#------------------------------------------------------------------------------------------------------------
# Fail-Fast Configuration
#------------------------------------------------------------------------------------------------------------
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Helper function to exit with error
function Exit-WithError {
    param([string]$Message)
    Write-Error "FATAL ERROR: $Message"
    exit 1
}

# Helper function to validate resource exists
function Test-ResourceExists {
    param(
        [string]$ResourceType,
        [string]$ResourceName,
        [scriptblock]$TestScript
    )
    try {
        $result = & $TestScript
        return ($null -ne $result)
    } catch {
        return $false
    }
}

# Helper function to retry operations with exponential backoff
function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [string]$OperationName,
        [int]$MaxRetries = 5,
        [int]$InitialDelaySeconds = 5,
        [string[]]$RetryableErrors = @("ResourceNotFound", "NotFound", "ResourceGroupNotFound", "ParentResourceNotFound", "404", "The Resource * under resource group * was not found")
    )
    
    $attempt = 0
    $delay = $InitialDelaySeconds
    
    while ($true) {
        $attempt++
        try {
            $result = & $ScriptBlock
            return $result
        } catch {
            $errorMessage = $_.Exception.Message
            $isRetryable = $false
            
            foreach ($pattern in $RetryableErrors) {
                if ($errorMessage -match $pattern) {
                    $isRetryable = $true
                    break
                }
            }
            
            if ($isRetryable -and $attempt -lt $MaxRetries) {
                Write-Output "Attempt $attempt/$MaxRetries failed (resource propagation delay). Retrying in $delay seconds..."
                Start-Sleep -Seconds $delay
                $delay = [Math]::Min($delay * 2, 60)  # Exponential backoff, max 60 seconds
            } else {
                throw $_
            }
        }
    }
}

#------------------------------------------------------------------------------------------------------------
# Module Installation Check
#------------------------------------------------------------------------------------------------------------
Write-Output "Checking required PowerShell modules..."

$requiredAzModules = @('Az.Accounts', 'Az.Resources', 'Az.OperationalInsights')
$missingModules = @()
foreach ($mod in $requiredAzModules) {
    if (-not (Get-Module -Name $mod -ListAvailable -ErrorAction SilentlyContinue)) {
        $missingModules += $mod
    }
}

if ($missingModules.Count -gt 0) {
    Write-Output "Missing Az modules: $($missingModules -join ', '). Installing Az module in CurrentUser scope..."
    try {
        Install-Module -Name Az -Force -Scope CurrentUser -ErrorAction Stop
    } catch {
        Exit-WithError "Failed to install Az module: $($_.Exception.Message)"
    }
    # Verify the modules are now available
    foreach ($mod in $missingModules) {
        if (-not (Get-Module -Name $mod -ListAvailable -ErrorAction SilentlyContinue)) {
            Exit-WithError "Module '$mod' is still not available after installing Az. Please install it manually: Install-Module -Name $mod -Force -Scope CurrentUser"
        }
    }
} else {
    Write-Output "  All required Az modules found: $($requiredAzModules -join ', ')"
}

$ModuleCheck = Get-Module -Name Microsoft.Graph -ListAvailable -ErrorAction SilentlyContinue
If (!($ModuleCheck))
{
    Write-Output "Installing Microsoft.Graph module in CurrentUser scope..."
    try {
        Install-Module -Name Microsoft.Graph -Force -Scope CurrentUser -ErrorAction Stop
    } catch {
        Exit-WithError "Failed to install Microsoft.Graph module: $($_.Exception.Message)"
    }
}

#------------------------------------------------------------------------------------------------------------
# Azure Authentication and Context Setup
#------------------------------------------------------------------------------------------------------------
Write-Output ""
Write-Output "Connecting to Azure ($AzureEnvironment)..."
try {
    Connect-AzAccount -Tenant $TenantId -Environment $AzureEnvironment -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
} catch {
    Exit-WithError "Failed to connect to Azure: $($_.Exception.Message)"
}

# Verify we're in the correct subscription context
Write-Output ""
Write-Output "Validating Azure context is subscription [ $($LogAnalyticsSubscription) ]"
$AzContext = Get-AzContext

# Resolve ARM endpoint from current cloud environment (supports sovereign clouds)
$ArmEndpoint = $AzContext.Environment.ResourceManagerUrl.TrimEnd('/')
Write-Output "  ARM endpoint: $ArmEndpoint"

If ($AzContext.Subscription.Id -ne $LogAnalyticsSubscription)
{
    Write-Output ""
    Write-Output "Switching Azure context to subscription [ $($LogAnalyticsSubscription) ]"
    try {
        $AzContext = Set-AzContext -Subscription $LogAnalyticsSubscription -Tenant $TenantId -ErrorAction Stop
    } catch {
        Exit-WithError "Failed to switch subscription context: $($_.Exception.Message)"
    }
}

# Get access token for Azure REST API calls
try {
    $AccessToken = Get-AzAccessToken -ResourceUrl "$ArmEndpoint/" -ErrorAction Stop
    $AccessToken = $AccessToken.Token
} catch {
    Exit-WithError "Failed to get access token: $($_.Exception.Message)"
}

$Headers = @{
    "Authorization"="Bearer $($AccessToken)"
    "Content-Type"="application/json"
}

#------------------------------------------------------------------------------------------------------------
# Normalize Location to Canonical Name (e.g., "West US 2" -> "westus2")
#------------------------------------------------------------------------------------------------------------
Write-Output ""
Write-Output "Normalizing location..."
$azLocation = Get-AzLocation | Where-Object { $_.Location -eq $LogAnalyticsLocation -or $_.DisplayName -eq $LogAnalyticsLocation } | Select-Object -First 1
if ($azLocation) {
    $LogAnalyticsLocation = $azLocation.Location
    Write-Output "  Using location: $LogAnalyticsLocation"
} else {
    Write-Output "  WARNING: Could not verify location '$LogAnalyticsLocation'. Proceeding as-is."
}

#------------------------------------------------------------------------------------------------------------
# Verify Prerequisites: Permissions
#------------------------------------------------------------------------------------------------------------
Write-Output ""
Write-Output "=============================================="
Write-Output "Checking prerequisites..."
Write-Output "=============================================="

$currentUser = $AzContext.Account.Id
$subscriptionScope = "/subscriptions/$LogAnalyticsSubscription"
$resourceGroupScope = "/subscriptions/$LogAnalyticsSubscription/resourceGroups/$LogAnalyticsResourceGroup"
$roleCheckFailed = $false

# Helper: query role assignments with graceful error handling.
# Returns $null if the query itself fails (e.g., user lacks permission to read role assignments).
function Get-RoleAssignmentsSafe {
    param(
        [string]$Scope,
        [string]$SignInName
    )
    try {
        return Get-AzRoleAssignment -Scope $Scope -SignInName $SignInName -ErrorAction Stop
    } catch {
        return $null
    }
}

#--- Check 1: Contributor (or Owner) on resource group / subscription ---
Write-Output ""
Write-Output "1. Verifying Contributor permissions..."

# Check if resource group exists
$existingRg = Get-AzResourceGroup -Name $LogAnalyticsResourceGroup -ErrorAction SilentlyContinue

if ($existingRg)
{
    # Resource group exists - check permissions at RG level
    Write-Output "Resource group exists. Checking permissions at resource group level..."
    $roleAssignments = Get-RoleAssignmentsSafe -Scope $resourceGroupScope -SignInName $currentUser
    $permissionScope = "resource group [ $LogAnalyticsResourceGroup ]"
}
else
{
    # Resource group doesn't exist - need subscription level to create it
    Write-Output "Resource group does not exist. Checking permissions at subscription level..."
    $roleAssignments = Get-RoleAssignmentsSafe -Scope $subscriptionScope -SignInName $currentUser
    $permissionScope = "subscription [ $LogAnalyticsSubscription ]"
}

if ($null -eq $roleAssignments)
{
    Write-Warning "WARNING: Unable to read role assignments on $permissionScope. You may lack read access to role assignments."
    Write-Warning "Proceeding anyway — resource creation will fail later if you lack the required Contributor role."
}
else
{
    $hasContributorAccess = $roleAssignments | Where-Object {
        $_.RoleDefinitionName -eq "Contributor" -or
        $_.RoleDefinitionName -eq "Owner"
    }

    if (-not $hasContributorAccess)
    {
        Write-Error "ERROR: You do not have Contributor or Owner role on $permissionScope"
        Write-Error ""
        if ($existingRg)
        {
            Write-Error "The resource group exists. You need Contributor role on the resource group."
            Write-Error "Ask a subscription administrator to run:"
            Write-Error "  New-AzRoleAssignment -SignInName '$currentUser' -RoleDefinitionName 'Contributor' -Scope '$resourceGroupScope'"
        }
        else
        {
            Write-Error "The resource group does not exist. You need Contributor role on the subscription to create it."
            Write-Error "Alternatively, ask an admin to create the resource group first, then you only need"
            Write-Error "Contributor role on the resource group."
            Write-Error ""
            Write-Error "To create the resource group:"
            Write-Error "  New-AzResourceGroup -Name '$LogAnalyticsResourceGroup' -Location '$LogAnalyticsLocation'"
            Write-Error "Then grant Contributor on it:"
            Write-Error "  New-AzRoleAssignment -SignInName '$currentUser' -RoleDefinitionName 'Contributor' -Scope '$resourceGroupScope'"
        }
        exit 1
    }

    Write-Output "OK — $($hasContributorAccess[0].RoleDefinitionName) role found on $permissionScope."
}

# If DCR resource group differs from the LA resource group, also check Contributor there
if ($AzDcrResourceGroup -ne $LogAnalyticsResourceGroup) {
    Write-Output ""
    Write-Output "DCR resource group differs from workspace resource group. Checking Contributor on [ $AzDcrResourceGroup ]..."
    $dcrRgScope = "/subscriptions/$LogAnalyticsSubscription/resourceGroups/$AzDcrResourceGroup"
    $existingDcrRgPreCheck = Get-AzResourceGroup -Name $AzDcrResourceGroup -ErrorAction SilentlyContinue

    if ($existingDcrRgPreCheck) {
        $dcrRgRoles = Get-RoleAssignmentsSafe -Scope $dcrRgScope -SignInName $currentUser
        $dcrCheckScope = "resource group [ $AzDcrResourceGroup ]"
    } else {
        $dcrRgRoles = Get-RoleAssignmentsSafe -Scope $subscriptionScope -SignInName $currentUser
        $dcrCheckScope = "subscription [ $LogAnalyticsSubscription ] (DCR resource group does not exist yet)"
    }

    if ($null -eq $dcrRgRoles) {
        Write-Warning "WARNING: Unable to read role assignments for DCR resource group scope. Proceeding anyway."
    } else {
        $hasDcrRgContributor = $dcrRgRoles | Where-Object {
            $_.RoleDefinitionName -eq "Contributor" -or
            $_.RoleDefinitionName -eq "Owner"
        }
        if (-not $hasDcrRgContributor) {
            Write-Error "ERROR: You do not have Contributor or Owner role on $dcrCheckScope."
            Write-Error "This is needed to create the Data Collection Rule."
            Write-Error "Ask a subscription administrator to grant Contributor on the DCR resource group."
            exit 1
        }
        Write-Output "OK — $($hasDcrRgContributor[0].RoleDefinitionName) role found on $dcrCheckScope."
    }
}

#--- Check 2: User Access Administrator (or Owner) for RBAC assignment ---
Write-Output ""
Write-Output "2. Verifying User Access Administrator permissions (needed for RBAC assignment)..."

# Check at subscription level — User Access Administrator is typically granted at subscription or RG scope,
# and we need it on both DCR and workspace scopes (which may not exist yet).
# Subscription-level check covers both.
$uaaRoleAssignments = Get-RoleAssignmentsSafe -Scope $subscriptionScope -SignInName $currentUser

if ($null -eq $uaaRoleAssignments)
{
    Write-Warning "WARNING: Unable to read role assignments at subscription level."
    Write-Warning "Cannot verify User Access Administrator role. Proceeding anyway."
    Write-Warning "RBAC assignment will fail later if you lack the required role."
}
else
{
    $hasUaaAccess = $uaaRoleAssignments | Where-Object {
        $_.RoleDefinitionName -eq "User Access Administrator" -or
        $_.RoleDefinitionName -eq "Owner"
    }

    if (-not $hasUaaAccess)
    {
        # Also check at RG level — the user might have User Access Administrator on just the RG
        if ($existingRg) {
            $rgRoleAssignments = Get-RoleAssignmentsSafe -Scope $resourceGroupScope -SignInName $currentUser
            if ($rgRoleAssignments) {
                $hasUaaAccess = $rgRoleAssignments | Where-Object {
                    $_.RoleDefinitionName -eq "User Access Administrator" -or
                    $_.RoleDefinitionName -eq "Owner"
                }
            }
        }
    }

    if (-not $hasUaaAccess)
    {
        Write-Error "ERROR: You do not have User Access Administrator or Owner role."
        Write-Error ""
        Write-Error "This role is required to assign RBAC permissions (Monitoring Metrics Publisher,"
        Write-Error "Monitoring Contributor, Log Analytics Contributor) to the Universal Print service principal."
        Write-Error ""
        Write-Error "Options:"
        Write-Error "  1. Ask an admin to grant User Access Administrator on the resource group:"
        Write-Error "     New-AzRoleAssignment -SignInName '$currentUser' -RoleDefinitionName 'User Access Administrator' -Scope '$resourceGroupScope'"
        exit 1
    }

    Write-Output "OK — $($hasUaaAccess[0].RoleDefinitionName) role found (sufficient for RBAC assignment)."
}

Write-Output ""
Write-Output "=============================================="
Write-Output "Prerequisite checks passed."
Write-Output "=============================================="

#------------------------------------------------------------------------------------------------------------
# Step 1: Create Resource Group for Log Analytics Workspace (if not exists)
#------------------------------------------------------------------------------------------------------------
Write-Output ""
Write-Output "Step 1: Validating resource group [ $($LogAnalyticsResourceGroup) ]..."
$existingRg = Get-AzResourceGroup -Name $LogAnalyticsResourceGroup -ErrorAction SilentlyContinue
if ($existingRg) {
    Write-Output "  Resource group already exists. Skipping creation."
} else {
    Write-Output "  Creating resource group [ $($LogAnalyticsResourceGroup) ]..."
    try {
        New-AzResourceGroup -Name $LogAnalyticsResourceGroup -Location $LogAnalyticsLocation -ErrorAction Stop | Out-Null
        Write-Output "  Resource group created successfully."
    } catch {
        Exit-WithError "Failed to create resource group: $($_.Exception.Message)"
    }
}

#------------------------------------------------------------------------------------------------------------
# Step 2: Create Log Analytics Workspace (if not exists)
#------------------------------------------------------------------------------------------------------------
Write-Output ""
Write-Output "Step 2: Validating Log Analytics workspace [ $($LogAnalyticsWorkspaceName) ]..."
$LogWorkspaceInfo = Get-AzOperationalInsightsWorkspace -Name $LogAnalyticsWorkspaceName -ResourceGroupName $LogAnalyticsResourceGroup -ErrorAction SilentlyContinue
if ($LogWorkspaceInfo) {
    Write-Output "  Log Analytics workspace already exists. Skipping creation."
} else {
    Write-Output "  Creating Log Analytics workspace [ $($LogAnalyticsWorkspaceName) ]..."
    try {
        New-AzOperationalInsightsWorkspace -Location $LogAnalyticsLocation -Name $LogAnalyticsWorkspaceName -ResourceGroupName $LogAnalyticsResourceGroup -ErrorAction Stop | Out-Null
        Write-Output "  Log Analytics workspace created successfully."
    } catch {
        Exit-WithError "Failed to create Log Analytics workspace: $($_.Exception.Message)"
    }
}

#------------------------------------------------------------------------------------------------------------
# Get Log Analytics Workspace Details
#------------------------------------------------------------------------------------------------------------
try {
    $LogWorkspaceInfo = Get-AzOperationalInsightsWorkspace -Name $LogAnalyticsWorkspaceName -ResourceGroupName $LogAnalyticsResourceGroup -ErrorAction Stop
    $LogAnalyticsWorkspaceResourceId = $LogWorkspaceInfo.ResourceId
} catch {
    Exit-WithError "Failed to get Log Analytics workspace details: $($_.Exception.Message)"
}

#------------------------------------------------------------------------------------------------------------
# Wait for Workspace to Become Active
#------------------------------------------------------------------------------------------------------------
Write-Output ""
Write-Output "Waiting for Log Analytics workspace to become active..."
Write-Output "  (New workspaces can take 1-2 minutes to initialize)"

$maxRetries = 12
$retryDelay = 10
$workspaceActive = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    # Try a simple query to check if workspace is active
    $testTableUri = "/subscriptions/$LogAnalyticsSubscription/resourceGroups/$LogAnalyticsResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$LogAnalyticsWorkspaceName/tables?api-version=2022-10-01"
    $testResult = Invoke-AzRestMethod -Path $testTableUri -Method GET -ErrorAction SilentlyContinue
    
    if ($testResult.StatusCode -eq 200) {
        Write-Output "  Workspace is active."
        $workspaceActive = $true
        break
    }
    
    Write-Output "  Attempt $i/$maxRetries - Workspace not ready yet. Waiting $retryDelay seconds..."
    Start-Sleep -Seconds $retryDelay
}

if (-not $workspaceActive) {
    Exit-WithError "Log Analytics workspace did not become active within the expected time. Please wait a few minutes and run the script again."
}

#------------------------------------------------------------------------------------------------------------
# Step 3: Create Custom Tables in Log Analytics Workspace
#------------------------------------------------------------------------------------------------------------
Write-Output ""
Write-Output "Step 3: Creating custom tables in Log Analytics workspace..."

$PrinterHealthTable = @"
{
    "properties": {
        "schema": {
            "name": "UniversalPrintPrinterHealth_CL",
            "columns": [
                {
                    "name": "TimeGenerated",
                    "type": "DateTime",
                    "description": "Printer health status generated time stamp"
                },
                {
                    "name": "PrinterId",
                    "type": "String",
                    "description": "The identifier of the Printer"
                },
                {
                    "name": "PrinterName",
                    "type": "String",
                    "description": "The name of the Printer"
                },
                {
                    "name": "LocationInfo",
                    "type": "dynamic",
                    "description": "Location information (structured object for KQL property access)"
                },
                {
                    "name": "PrinterDetails",
                    "type": "Dynamic",
                    "description": "Additional printer details including ShareIds, ShareNames, ConnectorIds, Manufacturer, Model, RegisteredDateTime."
                },
                {
                    "name": "PrinterStatusDetails",
                    "type": "Dynamic",
                    "description": "Raw IPP printer status: PrinterState, PrinterStateMessage, LastUpdatedDateTime, IsAcceptingJobs, PrinterStateReasonErrors, PrinterStateReasonWarnings, PrinterStateReasonReports."
                }
            ]
        },
        "plan": "Analytics"
    }
}
"@

$PrintJobTable= @"
{
    "properties": {
        "schema": {
            "name": "UniversalPrintJob_CL",
            "columns": [
                {
                    "name": "TimeGenerated",
                    "type": "DateTime",
                    "description": "Print job event generated time stamp (maps to CreationTime)."
                },
                {
                    "name": "JobLifecycleEvent",
                    "type": "String",
                    "description": "The job lifecycle event (Graph values: submitted, readyForPrinter, acquiredByPrinter, finished)."
                },
                {
                    "name": "JobId",
                    "type": "String",
                    "description": "The identifier of the print job."
                },
                {
                    "name": "PrinterShareId",
                    "type": "String",
                    "description": "The identifier of the printer share where the job is submitted."
                },
                {
                    "name": "PrinterShareName",
                    "type": "String",
                    "description": "The name of the printer share where the job is submitted."
                },
                {
                    "name": "PrinterId",
                    "type": "String",
                    "description": "The identifier of the physical printer where the job is routed for printing. It can be null."
                },
                {
                    "name": "PrinterName",
                    "type": "String",
                    "description": "The name of the physical printer where the job is routed for printing. It can be null."
                },
                {
                    "name": "CreatedBy",
                    "type": "String",
                    "description": "The userprincipalname of the job submitter."
                },
                {
                    "name": "CreatedDateTime",
                    "type": "DateTime",
                    "description": "The job creation date time in UTC."
                },
                {
                    "name": "JobState",
                    "type": "String",
                    "description": "The job state (Graph values: pending, paused, processing, stopped, canceled, aborted, completed, unknown)."
                },
                {
                    "name": "DocumentSizeInBytes",
                    "type": "Long",
                    "description": "The size of the print job document in bytes."
                },
                {
                    "name": "ReadyForPrinterDateTime",
                    "type": "DateTime",
                    "description": "The UTC date time when the document became fetchable by the printer."
                },
                {
                    "name": "CompletedDateTime",
                    "type": "DateTime",
                    "description": "The UTC date time when the job reached its terminal state (completed/canceled/aborted)."
                },
                {
                    "name": "Details",
                    "type": "Dynamic",
                    "description": "Additional details including RedirectedFromPrinterId, Copies, PageCount, MediaSheetCount, ColorMode, DuplexMode, DocumentUploadedDateTime, ReleasedDateTime, AcquiredByPrinterDateTime, DocumentDownloadedDateTime, JobStateReasons (string[]), Dpi, Orientation, InputBin, OutputBin, MediaSize, MediaType, Finishings (string[]), PagesPerSheet, MultipageLayout, Collate, Scaling, FeedOrientation, PauseReason (camelCase: heldForRelease | taskTrigger; present on Submitted events for jobs held by 1P pull-print/held-for-release or by a 3P JobStarted task trigger)."
                }
            ]
        },
        "plan": "Analytics",
        "retentionInDays": $PrintJobRetentionInDays,
        "totalRetentionInDays": $PrintJobTotalRetentionInDays
    }
}
"@

# Check if UniversalPrintPrinterHealth_CL table exists and is configured correctly
Write-Output "  Validating UniversalPrintPrinterHealth_CL table..."
$printerHealthTableUri = "/subscriptions/$LogAnalyticsSubscription/resourceGroups/$LogAnalyticsResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$LogAnalyticsWorkspaceName/tables/UniversalPrintPrinterHealth_CL?api-version=2022-10-01"
$existingPrinterHealthTable = Invoke-AzRestMethod -Path $printerHealthTableUri -Method GET -ErrorAction SilentlyContinue

# Always PUT the table schema (idempotent upsert) so re-runs pick up schema renames/changes.
Write-Output "Creating or updating UniversalPrintPrinterHealth_CL table (idempotent PUT)..."
$result = Invoke-WithRetry -OperationName "Upsert UniversalPrintPrinterHealth_CL table" -ScriptBlock {
    $r = Invoke-AzRestMethod -Path $printerHealthTableUri -Method PUT -Payload $PrinterHealthTable -ErrorAction Stop
    if ($r.StatusCode -ne 200 -and $r.StatusCode -ne 201 -and $r.StatusCode -ne 202) {
        throw "Status: $($r.StatusCode), Response: $($r.Content)"
    }
    return $r
}
Write-Output "UniversalPrintPrinterHealth_CL table is up to date."

# Check if UniversalPrintJob_CL table exists and is configured correctly
Write-Output "  Validating UniversalPrintJob_CL table..."
$printJobTableUri = "/subscriptions/$LogAnalyticsSubscription/resourceGroups/$LogAnalyticsResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$LogAnalyticsWorkspaceName/tables/UniversalPrintJob_CL?api-version=2022-10-01"
$existingPrintJobTable = Invoke-AzRestMethod -Path $printJobTableUri -Method GET -ErrorAction SilentlyContinue

# Always PUT the table schema (idempotent upsert) so re-runs pick up schema renames/changes.
Write-Output "Creating or updating UniversalPrintJob_CL table (idempotent PUT)..."
$result = Invoke-WithRetry -OperationName "Upsert UniversalPrintJob_CL table" -ScriptBlock {
    $r = Invoke-AzRestMethod -Path $printJobTableUri -Method PUT -Payload $PrintJobTable -ErrorAction Stop
    if ($r.StatusCode -ne 200 -and $r.StatusCode -ne 201 -and $r.StatusCode -ne 202) {
        throw "Status: $($r.StatusCode), Response: $($r.Content)"
    }
    return $r
}
Write-Output "UniversalPrintJob_CL table is up to date."

# Define UniversalPrintBillingSummary_CL table schema
$BillingSummaryTable = @"
{
    "properties": {
        "schema": {
            "name": "UniversalPrintBillingSummary_CL",
            "columns": [
                {
                    "name": "TimeGenerated",
                    "type": "DateTime",
                    "description": "Billing summary event generated time stamp"
                },
                {
                    "name": "UsedPrintJobCount",
                    "type": "Int",
                    "description": "The number of billable print jobs for the billing period"
                },
                {
                    "name": "IncludedPrintJobCount",
                    "type": "Int",
                    "description": "The number of print jobs included in the billing period (the print capacity)."
                },
                {
                    "name": "BillingPeriodStartDateTime",
                    "type": "DateTime",
                    "description": "The start date of the billing period"
                },
                {
                    "name": "BillingPeriodEndDateTime",
                    "type": "DateTime",
                    "description": "The end date of the billing period"
                }
            ]
        },
        "plan": "Analytics"
    }
}
"@

# Check if UniversalPrintBillingSummary_CLtable exists and is configured correctly
Write-Output "  Validating UniversalPrintBillingSummary_CL table..."
$billingSummaryTableUri = "/subscriptions/$LogAnalyticsSubscription/resourceGroups/$LogAnalyticsResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$LogAnalyticsWorkspaceName/tables/UniversalPrintBillingSummary_CL?api-version=2022-10-01"
$existingBillingSummaryTable = Invoke-AzRestMethod -Path $billingSummaryTableUri -Method GET -ErrorAction SilentlyContinue

if ($existingBillingSummaryTable.StatusCode -eq 200) {
    Write-Output "Updating UniversalPrintBillingSummary_CL table schema (idempotent PUT)..."
} else {
    Write-Output "Creating UniversalPrintBillingSummary_CL table..."
}
$result = Invoke-WithRetry -OperationName "Upsert UniversalPrintBillingSummary_CL table" -ScriptBlock {
    $r = Invoke-AzRestMethod -Path $billingSummaryTableUri -Method PUT -Payload $BillingSummaryTable -ErrorAction Stop
    if ($r.StatusCode -ne 200 -and $r.StatusCode -ne 201 -and $r.StatusCode -ne 202) {
        throw "Status: $($r.StatusCode), Response: $($r.Content)"
    }
    return $r
}
Write-Output "UniversalPrintBillingSummary_CL table is up to date."

#------------------------------------------------------------------------------------------------------------
# Step 4: Create Resource Group for Data Collection Rule (if not exists)
#------------------------------------------------------------------------------------------------------------
Write-Output ""
Write-Output "Step 4: Validating DCR resource group [ $($AzDcrResourceGroup) ]..."
$existingDcrRg = Get-AzResourceGroup -Name $AzDcrResourceGroup -ErrorAction SilentlyContinue
if ($existingDcrRg) {
    Write-Output "  DCR resource group already exists. Skipping creation."
} else {
    Write-Output "  Creating DCR resource group [ $($AzDcrResourceGroup) ]..."
    try {
        New-AzResourceGroup -Name $AzDcrResourceGroup -Location $LogAnalyticsLocation -ErrorAction Stop | Out-Null
        Write-Output "  DCR resource group created successfully."
    } catch {
        Exit-WithError "Failed to create DCR resource group: $($_.Exception.Message)"
    }
}

#------------------------------------------------------------------------------------------------------------
# Step 5: Create Data Collection Rule (DCR) with kind: Direct
#------------------------------------------------------------------------------------------------------------
Write-Output ""
Write-Output "Step 5: Validating Data Collection Rule [ $($AzDcrName) ]..."

$AzDcrResourceId = "/subscriptions/$LogAnalyticsSubscription/resourceGroups/$AzDcrResourceGroup/providers/Microsoft.Insights/dataCollectionRules/$AzDcrName"

# Check if DCR already exists
$existingDcr = Invoke-AzRestMethod -Path "$AzDcrResourceId`?api-version=2023-03-11" -Method GET -ErrorAction SilentlyContinue

# Always PUT the DCR (idempotent upsert) so re-runs pick up stream/column renames.
if ($existingDcr.StatusCode -eq 200) {
    Write-Output "  Updating existing DCR [ $($AzDcrName) ] (idempotent PUT)..."
} else {
    Write-Output "  Creating DCR [ $($AzDcrName) ]..."
}

$DCRContent = @"
{
    "kind": "Direct",
    "properties": {
        "streamDeclarations": {
            "Custom-UniversalPrintPrinterHealthData": {
                "columns": [
                    { "name": "TimeGenerated", "type": "datetime" },
                    { "name": "PrinterId", "type": "string" },
                    { "name": "PrinterName", "type": "string" },
                    { "name": "LocationInfo", "type": "dynamic" },
                    { "name": "PrinterDetails", "type": "dynamic" },
                    { "name": "PrinterStatusDetails", "type": "dynamic" }
                ]
            },
            "Custom-UniversalPrintJobData": {
                "columns": [
                    { "name": "TimeGenerated", "type": "datetime" },
                    { "name": "JobLifecycleEvent", "type": "string" },
                    { "name": "JobId", "type": "string" },
                    { "name": "PrinterShareId", "type": "string" },
                    { "name": "PrinterShareName", "type": "string" },
                    { "name": "PrinterId", "type": "string" },
                    { "name": "PrinterName", "type": "string" },
                    { "name": "CreatedBy", "type": "string" },
                    { "name": "CreatedDateTime", "type": "datetime" },
                    { "name": "JobState", "type": "string" },
                    { "name": "DocumentSizeInBytes", "type": "long" },
                    { "name": "ReadyForPrinterDateTime", "type": "datetime" },
                    { "name": "CompletedDateTime", "type": "datetime" },
                    { "name": "Details", "type": "dynamic" }
                ]
            },
            "Custom-UniversalPrintBillingSummaryData": {
                "columns": [
                    { "name": "TimeGenerated", "type": "datetime" },
                    { "name": "UsedPrintJobCount", "type": "int" },
                    { "name": "IncludedPrintJobCount", "type": "int" },
                    { "name": "BillingPeriodStartDateTime", "type": "datetime" },
                    { "name": "BillingPeriodEndDateTime", "type": "datetime" }
                ]
            }
        },
        "destinations": {
            "logAnalytics": [
                {
                    "workspaceResourceId": "$LogAnalyticsWorkspaceResourceId",
                    "name": "upworkspace"
                }
            ]
        },
        "dataFlows": [
            {
                "streams": ["Custom-UniversalPrintPrinterHealthData"],
                "destinations": ["upworkspace"],
                "transformKql": "source",
                "outputStream": "Custom-UniversalPrintPrinterHealth_CL"
            },
            {
                "streams": ["Custom-UniversalPrintJobData"],
                "destinations": ["upworkspace"],
                "transformKql": "source",
                "outputStream": "Custom-UniversalPrintJob_CL"
            },
            {
                "streams": ["Custom-UniversalPrintBillingSummaryData"],
                "destinations": ["upworkspace"],
                "transformKql": "source",
                "outputStream": "Custom-UniversalPrintBillingSummary_CL"
            }
        ]
    },
    "location": "$LogAnalyticsLocation"
}
"@

    $DcrResult = Invoke-WithRetry -OperationName "Upsert DCR" -ScriptBlock {
        $r = Invoke-AzRestMethod -Path "$AzDcrResourceId`?api-version=2023-03-11" -Method PUT -Payload $DCRContent
        if ($r.StatusCode -ne 200 -and $r.StatusCode -ne 201) {
            # Check if error is due to resource propagation delay
            if ($r.Content -match "NotFound|ResourceNotFound|ParentResourceNotFound") {
                throw "Resource propagation delay: $($r.Content)"
            }
            throw "Status: $($r.StatusCode), Response: $($r.Content)"
        }
        return $r
    }
Write-Output "  DCR is up to date."

# Wait for DCR to be fully provisioned
Write-Output "  Waiting for DCR to be fully provisioned..."
Invoke-WithRetry -OperationName "Verify DCR provisioned" -MaxRetries 6 -InitialDelaySeconds 10 -ScriptBlock {
    $dcrCheck = Invoke-AzRestMethod -Path "$AzDcrResourceId`?api-version=2023-03-11" -Method GET -ErrorAction Stop
    if ($dcrCheck.StatusCode -ne 200) {
        throw "DCR not fully provisioned yet"
    }
    $dcrContent = $dcrCheck.Content | ConvertFrom-Json
    if (-not $dcrContent.properties.immutableId) {
        throw "DCR immutableId not available yet"
    }
}
Write-Output "  DCR is ready."

#------------------------------------------------------------------------------------------------------------
# Output: Values Needed for Universal Print Configuration
#------------------------------------------------------------------------------------------------------------
Write-Output ""
Write-Output "=============================================="
Write-Output "INFRASTRUCTURE SETUP COMPLETE"
Write-Output "=============================================="
Write-Output ""
Write-Output "Select these values in the Universal Print Admin Portal:"
Write-Output ""
Write-Output "  Subscription:             $($AzContext.Subscription.Name) ($($AzContext.Subscription.Id))"
Write-Output ""
Write-Output "  Log Analytics Workspace:  $LogAnalyticsWorkspaceName"
Write-Output "    Resource Group:         $LogAnalyticsResourceGroup"
Write-Output ""
Write-Output "  Data Collection Rule:     $AzDcrName"
Write-Output "    Resource Group:         $AzDcrResourceGroup"
Write-Output ""

#------------------------------------------------------------------------------------------------------------
# RBAC Permission Assignment
#------------------------------------------------------------------------------------------------------------
Write-Output "----------------------------------------------"
Write-Output "Configuring RBAC permissions..."
Write-Output "----------------------------------------------"

# Universal Print service principal App ID (fixed value)
$UniversalPrintAppId = "da9b70f6-5323-4ce6-ae5c-88dcc5082966"

#--- Microsoft Graph Connection (Read-Only Access) ---
Write-Output ""
Write-Output "Connecting to Microsoft Graph..."

# Map Azure environment to Microsoft Graph environment (supports sovereign clouds)
$MgEnvironment = switch ($AzContext.Environment.Name) {
    "AzureUSGovernment" { "USGov" }
    "AzureChinaCloud"   { "China" }
    default             { "Global" }
}

$MgScope = @("Application.Read.All")
try {
    Connect-MgGraph -TenantId $TenantId -Scopes $MgScope -Environment $MgEnvironment -ErrorAction Stop | Out-Null
} catch {
    Exit-WithError "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
}

#--- Look up Universal Print Service Principal ---
Write-Output ""
Write-Output "Looking up Universal Print service principal..."
$ServicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '$UniversalPrintAppId'" -ErrorAction SilentlyContinue

If (!$ServicePrincipal)
{
    Exit-WithError "Universal Print service principal not found in this tenant (AppId: $UniversalPrintAppId). Please ensure Universal Print is enabled for your tenant."
}

$ServicePrincipalObjectId = $ServicePrincipal.Id
$ServicePrincipalDisplayName = $ServicePrincipal.DisplayName
Write-Output "  Found: $ServicePrincipalDisplayName (ObjectId: $ServicePrincipalObjectId)"

#--- Build Role Assignment List ---
# Role IDs (built-in Azure roles)
$MonitoringMetricsPublisherRoleId = "3913510d-42f4-4e42-8a64-420c390055eb"
$MonitoringContributorRoleId = "749f88d5-cbae-40b8-bcfc-e573ddc772fa"
$LogAnalyticsContributorRoleId = "92aaf0da-9dab-42b6-94a3-d43ce8d16293"

$rolesToAssign = @(
    @{ RoleId = $MonitoringMetricsPublisherRoleId; RoleName = "Monitoring Metrics Publisher"; Scope = $AzDcrResourceId; Description = "Ingest data into DCR" }
    @{ RoleId = $MonitoringContributorRoleId;      RoleName = "Monitoring Contributor";       Scope = $AzDcrResourceId; Description = "Update DCR schema, stream declarations, and data flows" }
    @{ RoleId = $LogAnalyticsContributorRoleId;    RoleName = "Log Analytics Contributor";    Scope = $LogAnalyticsWorkspaceResourceId; Description = "Update table schemas (add/modify columns)" }
)

Write-Output ""
Write-Output "  Roles to assign:"
Write-Output "- Monitoring Metrics Publisher on DCR (data ingestion)"
Write-Output "- Monitoring Contributor on DCR (DCR schema updates)"
Write-Output "- Log Analytics Contributor on workspace (table schema updates)"

#--- Assign Roles ---
Write-Output ""
Write-Output "Assigning roles to Universal Print..."

foreach ($role in $rolesToAssign) {
    Write-Output ""
    Write-Output "  Checking '$($role.RoleName)' on $($role.Scope)..."

    $existingAssignments = Get-AzRoleAssignment -Scope $role.Scope -ObjectId $ServicePrincipalObjectId -ErrorAction SilentlyContinue
    $existingRole = $existingAssignments | Where-Object { $_.RoleDefinitionId -match $role.RoleId }

    if ($existingRole) {
        Write-Output "Already assigned. Skipping."
        continue
    }

    Write-Output "Assigning '$($role.RoleName)'..."
    # Generate deterministic GUID for role assignment name.
    # Note: This uses SHA-256, which differs from ARM's guid() (RFC 4122 v5/MD5).
    # The pre-check above (Get-AzRoleAssignment) prevents duplicate assignments.
    $guidInput = "$($role.Scope)$ServicePrincipalObjectId$($role.RoleId)"
    $guidBytes = [System.Text.Encoding]::UTF8.GetBytes($guidInput)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($guidBytes)
    $guid = [guid]::new([byte[]]$hash[0..15]).ToString()
    $roleDefinitionId = "/subscriptions/$LogAnalyticsSubscription/providers/Microsoft.Authorization/roleDefinitions/$($role.RoleId)"
    $roleUrl = "$ArmEndpoint$($role.Scope)/providers/Microsoft.Authorization/roleAssignments/$guid`?api-version=2022-04-01"

    $roleBody = @{
        properties = @{
            roleDefinitionId = $roleDefinitionId
            principalId      = $ServicePrincipalObjectId
            principalType    = "ServicePrincipal"
            scope            = $role.Scope
        }
    }
    $jsonRoleBody = $roleBody | ConvertTo-Json -Depth 6

    try {
        $result = Invoke-WithRetry -OperationName "Assign $($role.RoleName)" -MaxRetries 6 -InitialDelaySeconds 10 -ScriptBlock {
            Invoke-RestMethod -Uri $roleUrl -Method PUT -Body $jsonRoleBody -Headers $Headers -ErrorAction Stop
        }
        Write-Output "SUCCESS: $($role.RoleName) assigned."
    } catch {
        $errorMessage = $_.Exception.Message
        $statusCode = $_.Exception.Response.StatusCode

        if ($errorMessage -match "RoleAssignmentExists" -or $statusCode -eq 409) {
            Write-Output "Role assignment already exists."
        } else {
            Exit-WithError "Failed to assign '$($role.RoleName)': $errorMessage. Please ensure you have 'User Access Administrator' or 'Owner' role."
        }
    }
}

Write-Output ""
Write-Output "RBAC permissions configured successfully."
Write-Output "  NOTE: Role assignments can take 5-10 minutes to propagate." 
Write-Output ""
Write-Output "=============================================="

# SIG # Begin signature block
# MIIncQYJKoZIhvcNAQcCoIInYjCCJ14CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCJrKUmvHDwAyty
# lnz9rbxIW2vxO/lo9d4MxiJQy5NHXKCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
# xZvoL37EAAAAAAIcMA0GCSqGSIb3DQEBCwUAMFcxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBD
# b2RlIFNpZ25pbmcgUENBIDIwMjQwHhcNMjYwNDE2MTg1OTQxWhcNMjcwNDE1MTg1
# OTQxWjB0MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYD
# VQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQDVsZfgOKmM31HPfoWOoNEiw0SlCiIxUMC0I9NMWbucKOw/e9lP
# oAoehQVu6SG65V4EPzrYsnBnFPNoi4/HoOdjhz1qkrEt4I6tEcxXU6oOeY9zGveC
# /3iBeuhLYxM3M/PkcUoebF+Nednm8OkdSPoDu8imViHPQq/8CQUu0WRR4rE+dMRf
# rpVqfmNi2qWCX94T4MsepijGVkwE//tJg0ryAiYdHT34LSnlG/RSBZmQRGWZ5g8j
# qnKjRParSqMft1gvjuUTVgtWNZfgcLFSK5Wa0myrq8OPcgTGGsRgun+tnSS+IxDT
# xVsAPH1OzvPjwomguByhUe/OcvUN0D5Wmp7xAgMBAAGjggGqMIIBpjAOBgNVHQ8B
# Af8EBAMCB4AwHwYDVR0lBBgwFgYKKwYBBAGCN0wIAQYIKwYBBQUHAwMwHQYDVR0O
# BBYEFNoH7a2YDjOSwpkp6DHcmUS7J+0yMFQGA1UdEQRNMEukSTBHMS0wKwYDVQQL
# EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxFjAUBgNVBAUT
# DTIzMDAxMis1MDc1NjkwHwYDVR0jBBgwFoAUf1k/VCHarU/vBeXmo9ctBpQSCDEw
# YAYDVR0fBFkwVzBVoFOgUYZPaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNy
# bDBtBggrBgEFBQcBAQRhMF8wXQYIKwYBBQUHMAKGUWh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmcl
# MjBQQ0ElMjAyMDI0LmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4IC
# AQAUnEqhaRXe0T3hIJjvdQErEkrA/7bByjn6t5IArODkkRjzkYwtKMc2yYj2quaN
# rLutWw2YZcngKPy1b71YyDJQTy4NDRwaSh9Tw5thrk3NmcPrAHia5vtcBJ1CgtKK
# 7mQbIcQ22d/N3813ayCDDFewu1+jsZmX+r/aTEqaOM4TVxVtRSkuCy8nAXKuChOK
# Li/zA4XuH8iEYqIsj2YoNaeSxVmeGiERXpKdo3dDmYi0kO5w2D8VS4c3+9h6gElY
# BaAAg/dYErBg27qT3vv0zRDJhJufvCNylA8S7/+8H5E/PV5cng6na9VV/w9OV3qu
# uND6zdGa2EX38Glp50F9AIQk3p2xXmcvorDeM4XJ7UlWYBi6g80J1SSOQnInCYFE
# msfUNn3+1AaTJKSJL83quKArTac2pKhu0Yzzzrzo6HrsRiQKzpnRBb1/dMa6P3hz
# 75XbMRBctNsFhZC07WCmjExdLg2eHW5uV0TY8D5+6wozJf7vF3+WHkYPO85Z+BC6
# U4FkNbYNycZ9cE4j1tXRdyDCfml6c0HWPHjNVDObrv9lKt3qUqFpX38VCqVCyNOO
# 1UcXfQiVjJw32U2WUKZjt/neJKHEBsm9kFsLuWzkQ53+qcaSaytmsCnk2gOglrlD
# 5d3kKyvvAw+rzm0lT8K38P6PLxfZQHhu4W8dV7Av8N2ZmDCCBr0wggSloAMCAQIC
# EzMAAAA5O7Y3Gb8GHWcAAAAAADkwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBS
# b290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDExMB4XDTI0MDgwODIwNTQxOFoX
# DTM2MDMyMjIyMTMwNFowVzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQ
# Q0EgMjAyNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANgBnB7jOMeq
# lRYHNa265v4IY9fH8TKhemHfPINe1gpLaV3dhg324WwH06LcHbpnsBukCDNitryo
# 0dtS/EW6I/yEL/bLSY8hKpbfQuWusBPr9qazYcDxCW/qnjb5JsI1s8bNOg3bVATv
# QVL4tcf03aTycsz8QeCdM0l/yHRObJ9QqazM1r6VPEOJ7LL+uEEb73w6QCuhs89a
# 1uv1zerOYMnsneRRwCbpyW11IcggU0cRKDDq1pjVJzIbIF6+oiXXbReOsgeI8zu1
# FyQfK0fVkaya8SmVHQ/tOf23mZ4W9k0Ri22QW9p3UgSC5OUDktKxxcCmGL6tXLfO
# GSWHIIV4YrTJTT6PNty5REojHJuZHArkF9VnHTERWoTjAzfI3kP+5b4alUdhgAZ7
# ttOu1bVnXfHaqPYl2rPs20ji03LOVWsh/radgE17es5hL+t6lV0eVHrVhsssROWJ
# uz2MXMCt7iw7lFPG9LXKGjsmonn2gotGdHIuEg5JnJMJVmixd5LRlkmgYRZKzhxS
# CwyoGIq0PhaA7Y+VPct5pCHkijcIIDm0nlkK+0KyepolcqGm0T/GYQRMhHJlGOOm
# VQop36wUVUYklUy++vDWeEgEo4s7hxN6mIbf2MSIQ/iIfMZgJxC69oukMUXCrOC3
# SkE/xIkgpfl22MM1itkZ35nNXkMolU1lAgMBAAGjggFOMIIBSjAOBgNVHQ8BAf8E
# BAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFH9ZP1Qh2q1P7wXl5qPX
# LQaUEggxMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAUci06AjGQQ7kUBU7h6qfHMdEjiTQwWgYDVR0fBFMwUTBP
# oE2gS4ZJaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMv
# TWljUm9vQ2VyQXV0MjAxMV8yMDExXzAzXzIyLmNybDBeBggrBgEFBQcBAQRSMFAw
# TgYIKwYBBQUHMAKGQmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMv
# TWljUm9vQ2VyQXV0MjAxMV8yMDExXzAzXzIyLmNydDANBgkqhkiG9w0BAQwFAAOC
# AgEAFJQfOChP7onn6fLIMKrSlN1WYKwDFgAddymOUO3FrM8d7B/W/iQ6DxXsDn7D
# 5W4wMwYeLystcEqfkjz4NURRgazyMu5yRzQh4LqjA4tStTcJh1opExo7nn5PuPBY
# nbu0+THSuVHTe0VTTPVhily/piFrDo3axQ9P4C+Ol5yet+2gTfekICS5xS+cYfSI
# vgn0JksVBVMYVI5QFu/qhnLhsEFEUzG8fvv0hjgkO+lkpV9ty6GkN4vdnd7ya6Q6
# aR9y34aiM1qmxaxBi6OUnyNl6fkuun/diTFnYDLTppOkr/mg5WSfCiDVMNCxtj4w
# PKC5OmHm1DQIt/MNokbbH3UGsFP1QbzsLocuSqLCvH09Io3fDPTmscR9Y75G4qX7
# RTX8AdBPo0I6OEojf39zuFZt0qOHm65YWQE69cZM2ueE1MB05dNNgHK9gTE7zKvK
# /fg8B2qjW88MT/WF5V5uvZGtqa9FSL2RazArA+rDPuf6JGYz4HpgMZHB4S6szWSK
# YBv0VisCzfxgeU+dquXW9bd0auYlOB58DPcOYKdc3Se94g+xL4pcEhbB54JOgAkw
# YTu/9dLeH2pDqeJZAABVDWRQCaXfO5LgyKwKCLYXpigrZYCjUSBcr+Ve8PFWMhVT
# Ql0v4q8J/AUmQN5W4n101cY2L4A7GTQG1h32HHAvfQESWP0xghn+MIIZ+gIBATBu
# MFcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# KDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIc
# +s3Fm+gvfsQAAAAAAhwwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZI
# hvcNAQkEMSIEIAB19wqRPFWyo3yVYIBCdPubvV+hGoRIuMq4rQvavJMvMEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAfeKcgSoIdWuCC2s+lV40
# K+VXGyIekuDUiZUyISfilOwvnajueVp+20a2X5QaiJ52M0FKrKrpPryt/ySc4HEj
# BYrLxQ3I/pN+L3ogzzT10oAVsvt7Wl+8m0LFNgSNH9NkYJggMPaSW4BTO1hO4kxU
# W5NkIPmgIIRcuGjxoelFHTVU7IwgWinccH3Z2IQXN+bCF89hx/HW8wznaSBJP3R/
# Asya9WPZXZwLWc6fEjCTublwtYLOa/UMDvdVqYRGPd+UJOxgp/sutEqNWZzSlEq8
# n3Lm2h/FHdbPkEv8/OfRgeKNr5WwlwOZlZ+CHWbQJzx2WiFJceCDDRw3sKtUm8ns
# RKGCF7AwghesBgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheF
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIB
# QQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCgeku18GCPVPArhWqp
# FTMeCFu45dPWYbRAe6rKhW2uIwIGahEGZl42GBMyMDI2MDYwOTE3MjIwMy4xMjNa
# MASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0MzFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKAD
# AgECAhMzAAACHUvAkoc4hX45AAEAAAIdMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDgxNDE4NDgzM1oXDTI2MTExMzE4
# NDgzM1owgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTAr
# BgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUG
# A1UECxMeblNoaWVsZCBUU1MgRVNOOjQzMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEAorSgaAA8oOl4ph574zw29egUN8DDepRHLX8FM1zHNJmXG6Kr
# SqUKwzcKafopuYdPTETTCvb9aJfESuAU0iGNUFI/D6R0kvdfpe2oPX+E3sbTQvGi
# 4JPH5qdIYUaJ45V/4bqe8eNvbWzpC+ZKjH193DeiI1XAI918JoQmBhlEXo/Ton17
# 21luZJgincsf5LjMY3jX84WyXUSX3dsS7h/7xVI+w1yjg7pa+0y3o/me2Tsv6UJU
# dSTQap5ORGSfCnclnP1z3IiiWIWr3Vo7aIPWsgJzq3m5GxpxUHCQk8qzUhk50y/u
# B+LGE3WIK2C77iy9iFsSfSLUnyMEzGRDW9mXHT4PH7Ozz6CHqQEiNvwcHqlvlCh1
# pHQh1NXQSAqOoVBs5mi6easf6yxWTfe5DrR79503r8pU6VqC2Y9XMRU4wH9QbYXY
# sIUZ33Jmndy22W1LBDAbxBPQHCBlncGDU3BgdhVUVLe80mggFO98FdkWho67w4kP
# dCTRkvdvkY8PrQYE/nQjHXCa0g7LcMttZb6ejMHfQ+tUWXv6+nZ4Ynkr2OkaxclF
# Cw4RIYNMWD26AWbQj/WEdzga18fKtw66L5gzXPza6jFBfPJeKE3H8QAuwpirmH4m
# s+5nUjNNQOmNgqJn0U1+3Yn7ClswD79YN0r3fdbYBMDApBZJpNlK7q7HXRsCAwEA
# AaOCAUkwggFFMB0GA1UdDgQWBBSEWfBxNEamZtXm8gl92Yq80jfxXTAfBgNVHSME
# GDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1l
# LVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsG
# AQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMB
# Af8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDAN
# BgkqhkiG9w0BAQsFAAOCAgEAkdweB4yxvLspLKq0D+miyD4Q0EcxVFpNZuJxiR54
# gWRkeTDDuymNeB03JhlsBpbwSYJ5uZSgDBCvwHED2VL8lJpFlOprJzxsXWC2NTfA
# +O+PO5Fk5jw6LHh6jeBADDEdQAx3Hqi7Zm0JwvQ93z5f6dtxkm29WqOcHYXRXfAQ
# wy1hSrLXyfeblqR66jpP/9n0fCkWU4ggsUjQpQ2Ngj1DV09J4Y3y7p9Nd81+Xs6q
# Yo++7RKm8qiB/5NDeigOLjlAeFgiEXIRUJW+mJyqpQw+OORlaqcFjR8Hu0G+/7bM
# dek68YX+kPpDBk7Ue+I/xgiYJ1xcDRBn/vczLtN72+RIlD4UgXYLuBSCk//pDEPX
# 5z39Cr+rkc6E4Y28FPk4BhloAyvp628P4xfElQY8TcxraUbZShypocE6ny95D1K1
# BkltZmrHVKCxmglnuOlM15NKIrXFlXCzdqpCtIwQ417wNAVF/QDPvzzbumPdTi6f
# b0tLbScYobV6zvbBsMsKEME4Tj1b9oIXC8dybJq4nbboEXYpRwi1QAbpSNrn+PxG
# W9uf1q63FnMJu4gm3Oh63njW/iVf723quzyHrSijWMgY0HiRiHQi0Jyu0h8MdhRU
# p7mxbmLQckPiOFwAlIaUN/k725y/aLWpkRU6fqmLlEOyH5WpyLd23AYy9r8v+Qob
# a6swggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEB
# CwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYD
# VQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAe
# Fw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGm
# TOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/H
# ZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDc
# wUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62A
# W36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1w
# jjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCG
# MFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ
# 1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP
# 8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFz
# ymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHz
# NgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3
# xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsG
# AQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/
# LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEG
# DCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYB
# BQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8G
# A1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQw
# VgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9j
# cmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUF
# BwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
# aS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQEL
# BQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfC
# cTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AF
# vonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l
# 9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn
# 8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5m
# O0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyx
# TkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4
# S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9
# y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM
# +Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhw
# RNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDWTCCAkEC
# AQEwggEBoYHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0MzFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIa
# AxUAuoO+BKbfXzqyfi9GLEdWHkCLeT+ggYMwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO3SlZ0wIhgPMjAyNjA2MDkx
# MzM3MzNaGA8yMDI2MDYxMDEzMzczM1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA
# 7dKVnQIBADAKAgEAAgIK0wIB/zAHAgEAAgISNTAKAgUA7dPnHQIBADA2BgorBgEE
# AYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYag
# MA0GCSqGSIb3DQEBCwUAA4IBAQDSp2gJHKTfrJMVad11kZel603DSBu1Vyb8CU/V
# BxoaKIDq+GIXywIUjs/dLtrQuLBOdpcJWx4bJw8LihwSipsd5tLMddHw/sDj3Ic/
# 3QbjNm5C91VXGxlsYD2hMgtHQARxZCX0+PHRNPvu1JDeJKnqjnOUuKpar0AnTI0w
# /9X0ZZd1B9692s+xQ9/1lZXsTsV82Ua64/uZQSONKP7aMkzqCcG1NtxDzFjUh9T1
# AdbZ04gvWthaTnYpgHJYR8QJv2I0Kmju0hugn4XmEiIHLM9XCLE0qnEcFBbRtAKh
# +c+G8VYhziJrUnYeDkvpiKCJZf8phPK3mbnB9gABfaP+6vuZMYIEDTCCBAkCAQEw
# gZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIdS8CShziFfjkA
# AQAAAh0wDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0B
# CRABBDAvBgkqhkiG9w0BCQQxIgQgAuGYChg0lcAvk0iNCe/d++1BMzzuRqs6eiTx
# eAeov9UwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCCxtpXMXEiLJzrqM77e
# p4rTNwrMOj6gpWN9hZvpj5QFUTCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAACHUvAkoc4hX45AAEAAAIdMCIEIOjYA4/7ucdklY9Gnu9e
# +LhZcSYWrRJ/dQiBWAmSpQImMA0GCSqGSIb3DQEBCwUABIICAJB8L84pLVJpge/K
# qiUnqKB7EUzbVc33txfH5HCMMCS0Yuvu/ciO+hjbz8ZoIgbKqObK/Jfs80dgvs/Z
# oWR2zwDWYReoNNXW42jYiL4NyyanWn0Ep9zSDc15S1fEkv0OEqBK1iNTNzxukxXA
# S7kRCfqQQKZoJpqThwnGlC8S0c+vF4Gyk1hOkpsknAUJR1DLyF0QfsUa/l419o2I
# ypX5b/NNTrX7aTINsV4Cc8O+ddOWbu4mjqmxrrsUI3R7qWxefyHfTZAQk47KXfMy
# y+2fau2v/4JZWlSrpdw326f37YLHG69jpXyqAOLZ7XzS6gfEYJxmWkyzKvQWtuue
# Ij877aTgZM0dHy7CF+dvC9Z0firTOBYInXmYUUWdX+IfGeznuz4ZcfYq7MumBqHb
# jYcxiZuSrjkDb+0A5oPrudpViAb9a3WOQiDC8DJ9aDojSh7Rx1y3NoIJq92bXGDX
# HxfsxVcVRebYXJByjWrxiT7FaVHgmW7bo18QFkirm5IFsj31Q8Ep/m0upjLejUN/
# r6n78lG8Y6A7CUtWwV6jjqwak3MN3qAJtQgiBykbPd80cnmLHhxRiDQ44IMoTd2z
# XOARAsagnJvGw3mzSimhqF0aoOiKRn1zZb7nEipEkZrEwXXKycLsEZogn0361FAa
# SpqpHXuFO06Nd48o1++vZfJmAZyJ
# SIG # End signature block
