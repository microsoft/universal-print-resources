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

.PARAMETER UniversalPrintServicePrincipalObjectId
    Optional. Object ID of the Universal Print enterprise application (service principal)
    in your tenant. When provided, the script assigns the required roles to this principal
    directly and skips the Microsoft Graph lookup — no 'Application.Read.All' consent and no
    Microsoft.Graph PowerShell module are required. When omitted, the script connects to
    Microsoft Graph and resolves the service principal automatically.
    Example: "abcd1234-5678-90ab-cdef-1234567890ab"

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

.EXAMPLE
    # Provide the Universal Print service principal Object ID directly (no Microsoft Graph permission needed)
    .\Setup-AlertingInfrastructure.ps1 `
        -TenantId "12345678-1234-1234-1234-123456789012" `
        -LogAnalyticsSubscription "87654321-4321-4321-4321-210987654321" `
        -LogAnalyticsLocation "West US 2" `
        -LogAnalyticsResourceGroup "rg-universalprint-alerting" `
        -LogAnalyticsWorkspaceName "law-universalprint" `
        -UniversalPrintServicePrincipalObjectId "abcd1234-5678-90ab-cdef-1234567890ab"

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
    - Microsoft Graph PowerShell SDK (for service principal lookup) — installed automatically if missing,
      and not required at all when -UniversalPrintServicePrincipalObjectId is provided
    
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
    [string]$AzureEnvironment = 'AzureCloud',

    [Parameter(Mandatory=$false, HelpMessage="Object ID of the Universal Print service principal. If provided, the script assigns roles to this principal directly and skips the Microsoft Graph lookup (no Application.Read.All or Microsoft.Graph module required).")]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$UniversalPrintServicePrincipalObjectId
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

if ([string]::IsNullOrWhiteSpace($UniversalPrintServicePrincipalObjectId)) {
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
} else {
    Write-Output "  -UniversalPrintServicePrincipalObjectId provided; Microsoft.Graph module not required (Graph lookup skipped)."
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

#--- Resolve Universal Print Service Principal ---
if ([string]::IsNullOrWhiteSpace($UniversalPrintServicePrincipalObjectId)) {
    # No Object ID supplied — look it up via Microsoft Graph (requires Application.Read.All).
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
} else {
    # Object ID supplied directly — skip Microsoft Graph entirely.
    $ServicePrincipalObjectId = $UniversalPrintServicePrincipalObjectId
    $ServicePrincipalDisplayName = "Universal Print"
    Write-Output ""
    Write-Output "Using provided Universal Print service principal ObjectId: $ServicePrincipalObjectId (Microsoft Graph lookup skipped)."
}

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
# MIInSAYJKoZIhvcNAQcCoIInOTCCJzUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBmQhewGO12Y9uS
# 7fFx2citdRt54JUFKbWS15E9ahshWaCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
# yE7XD1dIAAAAAAIdMA0GCSqGSIb3DQEBCwUAMFcxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBD
# b2RlIFNpZ25pbmcgUENBIDIwMjQwHhcNMjYwNDE2MTg1OTQzWhcNMjcwNDE1MTg1
# OTQzWjB0MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYD
# VQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQDQvewXxx9gZZFC6Ys1WBay8BJ8kGA4JQnH5CMafqOASlTpK9H8
# o5ZXTXt0caVQTNMUPt445wXYD+dFtaKWTwDn1I52oUSrC9vJin1Gsqt+zyKJL5Dg
# 3eQXbQNR61DmMy20GLTIO3SFed9Rfi/ophgCLGFLDR3r0KvHjwMb/jYWS0celV/4
# Lz27LfAekm8v9E5IXaeiXbAUYZKK090n4CVl3JBtbN+9DtI9SNu/yjvozW52/u7R
# X/Ttpa/KDlpuokZ+Zcbvmtd9ur9gFLvZzh41o9MsE/clQtdaFWGvuo6Jua/ntpgk
# ey3E5/vBFe+MJPG6phdnuo6r57ZudCudiI1bAgMBAAGjggGbMIIBlzAOBgNVHQ8B
# Af8EBAMCB4AwHwYDVR0lBBgwFgYKKwYBBAGCN0wIAQYIKwYBBQUHAwMwHQYDVR0O
# BBYEFH6QuMwqcPG0hQlQ6c5jCtTTLrVeMEUGA1UdEQQ+MDykOjA4MR4wHAYDVQQL
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xFjAUBgNVBAUTDTIzMDAxMis1MDc1NTkw
# HwYDVR0jBBgwFoAUf1k/VCHarU/vBeXmo9ctBpQSCDEwYAYDVR0fBFkwVzBVoFOg
# UYZPaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNybDBtBggrBgEFBQcBAQRh
# MF8wXQYIKwYBBQUHMAKGUWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNy
# dDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4ICAQBKTbYOjzwTG/DXGaz9
# s6+fQeaTtDcFmMY+5UyVFCyj7Pv+5i37qfX8lSL/tBIfYQfWsMuBQlfZurJD6r4H
# VJ2CeH+1fgiq8dcHdVKoZ3Sa2qXoX3cq9iS8cVb06B7+5/XJ7I0OxHH9fDsvJ3T3
# w5V/ZtAIFmLrl+P0CtG+92uzRsn0nTbdFjOkLMLWPLAU3THohKRlSEMgFJpPkm5n
# 5UAZ35xX6FWCrDLsSKb555bTifwa8mJBwdlof0bmfYidH+dxZ1FdDxvLnNl9zeKs
# A4kejaaIqqIPguhwAti5Ql7BlTNoJNwxCvBmqW2MQLnCkYN/VVUsR3V2x/rcTNzo
# Bf/Z/SpROvdaA2ZOOd1uioXJt3tdLQ7vHpqpib0KfWr/FWXW10q38VxfCnRQBqzb
# SuztR7nEMuzX7Ck+B/XaPDXd1qh72+QYyB0Z2VzWmO9zsnb9Uq/dwu8LGeQqnyu6
# 7SDGACvnXii2fb9+US492VTnXSnFKyqwgzUyFMtZK1/sHYTv6bG4TtQUygQxTN+Z
# V+aJIlKO2MqZ7bKrAnOzS9m6NgoTdWOq11bTOZwKlIEV/EhV9SWkDmdpR/hPPT2v
# 6TEj4F8PT/zHjRezIU5c/DGlt/VhY/pK0XkJtEyMmmS1BMtjU/rqBZVMIm3dnxQs
# /TBByr+Cf8Z1r7aifQVQ+WSqzjCCBr0wggSloAMCAQICEzMAAAA5O7Y3Gb8GHWcA
# AAAAADkwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDExMB4XDTI0MDgwODIwNTQxOFoXDTM2MDMyMjIyMTMwNFow
# VzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEo
# MCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAyNDCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBANgBnB7jOMeqlRYHNa265v4IY9fH8TKh
# emHfPINe1gpLaV3dhg324WwH06LcHbpnsBukCDNitryo0dtS/EW6I/yEL/bLSY8h
# KpbfQuWusBPr9qazYcDxCW/qnjb5JsI1s8bNOg3bVATvQVL4tcf03aTycsz8QeCd
# M0l/yHRObJ9QqazM1r6VPEOJ7LL+uEEb73w6QCuhs89a1uv1zerOYMnsneRRwCbp
# yW11IcggU0cRKDDq1pjVJzIbIF6+oiXXbReOsgeI8zu1FyQfK0fVkaya8SmVHQ/t
# Of23mZ4W9k0Ri22QW9p3UgSC5OUDktKxxcCmGL6tXLfOGSWHIIV4YrTJTT6PNty5
# REojHJuZHArkF9VnHTERWoTjAzfI3kP+5b4alUdhgAZ7ttOu1bVnXfHaqPYl2rPs
# 20ji03LOVWsh/radgE17es5hL+t6lV0eVHrVhsssROWJuz2MXMCt7iw7lFPG9LXK
# Gjsmonn2gotGdHIuEg5JnJMJVmixd5LRlkmgYRZKzhxSCwyoGIq0PhaA7Y+VPct5
# pCHkijcIIDm0nlkK+0KyepolcqGm0T/GYQRMhHJlGOOmVQop36wUVUYklUy++vDW
# eEgEo4s7hxN6mIbf2MSIQ/iIfMZgJxC69oukMUXCrOC3SkE/xIkgpfl22MM1itkZ
# 35nNXkMolU1lAgMBAAGjggFOMIIBSjAOBgNVHQ8BAf8EBAMCAYYwEAYJKwYBBAGC
# NxUBBAMCAQAwHQYDVR0OBBYEFH9ZP1Qh2q1P7wXl5qPXLQaUEggxMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU
# ci06AjGQQ7kUBU7h6qfHMdEjiTQwWgYDVR0fBFMwUTBPoE2gS4ZJaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0MjAx
# MV8yMDExXzAzXzIyLmNybDBeBggrBgEFBQcBAQRSMFAwTgYIKwYBBQUHMAKGQmh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0MjAx
# MV8yMDExXzAzXzIyLmNydDANBgkqhkiG9w0BAQwFAAOCAgEAFJQfOChP7onn6fLI
# MKrSlN1WYKwDFgAddymOUO3FrM8d7B/W/iQ6DxXsDn7D5W4wMwYeLystcEqfkjz4
# NURRgazyMu5yRzQh4LqjA4tStTcJh1opExo7nn5PuPBYnbu0+THSuVHTe0VTTPVh
# ily/piFrDo3axQ9P4C+Ol5yet+2gTfekICS5xS+cYfSIvgn0JksVBVMYVI5QFu/q
# hnLhsEFEUzG8fvv0hjgkO+lkpV9ty6GkN4vdnd7ya6Q6aR9y34aiM1qmxaxBi6OU
# nyNl6fkuun/diTFnYDLTppOkr/mg5WSfCiDVMNCxtj4wPKC5OmHm1DQIt/MNokbb
# H3UGsFP1QbzsLocuSqLCvH09Io3fDPTmscR9Y75G4qX7RTX8AdBPo0I6OEojf39z
# uFZt0qOHm65YWQE69cZM2ueE1MB05dNNgHK9gTE7zKvK/fg8B2qjW88MT/WF5V5u
# vZGtqa9FSL2RazArA+rDPuf6JGYz4HpgMZHB4S6szWSKYBv0VisCzfxgeU+dquXW
# 9bd0auYlOB58DPcOYKdc3Se94g+xL4pcEhbB54JOgAkwYTu/9dLeH2pDqeJZAABV
# DWRQCaXfO5LgyKwKCLYXpigrZYCjUSBcr+Ve8PFWMhVTQl0v4q8J/AUmQN5W4n10
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghnkMIIZ4AIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIDnhJ6UZ
# 5CQRfvGWLU5NS7sIfolaQlC4/pPh19WWW2heMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAgQE22hzPUIPH9+DzKmnHeoccL0y/9cRXyrBK0kVa
# GgyddwH5PjfCnWxWmX1ppcyYoFUqtS9V0ab84Xkc5iXH+EBApf4XFyHG+bwI6Nbq
# iioLxdww0exrzCVo97PbLOQvJkBXEP4CtlsLIFhPpxFRhn19ma05t/VW/pMYWVOh
# 4SDsQvRREKU1PbT6SbXzy0bBrmr/SWMOu6mvlmXTXf9NWix38GA6/4+mGSYiNsRi
# F1b4BKRIWgnNNiNBU+aw4m5WHhzc402fbMbzR+LLoOUlLZl/EKPLyxNLVF4hBG71
# j0ZTQXFYoKDLIZ6zwihRuc8/QI0N6LeqYpoAYNomuzv38aGCF5YwgheSBgorBgEE
# AYI3AwMBMYIXgjCCF34GCSqGSIb3DQEHAqCCF28wghdrAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFRBgsqhkiG9w0BCRABBKCCAUAEggE8MIIBOAIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCC93Kru+y16ueZClZeaVnrTDQOdwoSa5wo36pan
# v9lwGAIGahdNWnQzGBIyMDI2MDYxMDAwMjUwNS4wNFowBIACAfSggdGkgc4wgcsx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1p
# Y3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNT
# IEVTTjo5MjAwLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgU2VydmljZaCCEe0wggcgMIIFCKADAgECAhMzAAACI0/ZYCRTz/4rAAEAAAIj
# MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4X
# DTI2MDIxOTE5Mzk1N1oXDTI3MDUxNzE5Mzk1N1owgcsxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNh
# IE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo5MjAwLTA1RTAt
# RDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAIrpDaeTlZR0rNIJJp+n5SNQBGxb
# EcpLresmEUL/NJpsW6ZMG5onRA2uap6+5vkNvt9KPmq3DAqeMg73b4dcXrvX3Z+6
# MvsMWi3lYSP8C0Rn9evMUeKYqU3WHqARDA/kjrvCLNo9blnNIE2losGDmge8BI85
# m3B01Shn4NAoXeEmXUpm6giVUr6qLtwuOBqTqzmg5lxEIysqe4LdqhVrrBENti8p
# S6PuuQXH0o7Q+wcn+T4udkyCBGF6HgBV1rDKH6g7Mo+OVAZQ19J5ZSDKbZT0Itry
# 23SZBfgPEPPr6tqbnSCPWgB/JDpNDuv3o8AMU4oGBpTv5ykedpkbz11N6BDrJ0FE
# YjJw7DV1FfZ4oNFHPOIrdyfRZoib/s54azJAqMjMRC5RMO/QmP/3NDu2u4s46kkP
# 3wElU4ruN7zhLPaFvce9RJPuPWPY3yl4PqiWSkUdH/VnwnPgX6aStQXsyY8CKtgd
# HO6dsiDcesMw3AVg3vIGQMDj9Uyj0JjTL2gZSirbKNsLBOJvP1ViX3ecHdBCJMJP
# 2dbcz5M5YH48ytmkTGrUFIeYo/Mip6EqqtQOgzfc8r50QrClgsRPq5erge5BExdZ
# P/+w+5tSdABppQx9CEBlLLbce3HC03d4r35PjAJq/bBAW3nt5Q7BRbn8MLMwX225
# rkd7WE2+BwBdqIbXAgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQU1sCHz2/b2c9j1vBB
# vVBgLPFWB5cwHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0f
# BFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwv
# TWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsG
# AQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcnQwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAO
# BgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQADggIBAIdDB7vPm2ng1nAB/VwH
# 7hz0niy/Dc/paoYEzG2rOdLoN3NTNK1ccJo9mEzjWDWIoc2eZycuPAu6M4Ro2OFK
# dQOIBmpCNbllqk4HGBzsSCCGH2T6vvypYB7esnhCiEFuFIZ1m0qK9NFp5GqaeHLz
# 5OGsqHMJ4TBpqtcmKZnBKl1BBQNuF5Yd7IDEBKq6W13ko7Sb9QW87Te196moZcDi
# 0KD9YYQLAqo6MnOlEB88gHrLUfJWuT6+YvmukRtPDAs61ftbEUYbz5xguT0eNoOT
# GtoD8diUpBHHWx3Nr7D+C6UvCA6cHJEkoXauvwzsU0iXCiLrLAWlo1zwDsd7BoaO
# DD+19wTbrQjVd6QaW4A0j0ec405haUjsEoFBtYTa16jq+xDVWDwHytNlJ49V2Zcv
# U8+qqzcpV0UozmRihw8IMz7pUvfYhX3qwRJ/ZPsOPFqekKDYPZRiPhnWLtzLxTUs
# sMaDnkpazhp/ZFEGMfYy6UeACZbmhsrGJkINCNFqugnZcSVdSGKAT0HO+EIVtP8c
# Nja+lWmXkedKlwJLGYvmLmUhP/FsBAwjsu6Hvleub4iyV8VY4Y4YyUKn7bioQkSC
# VcQ/vHCyiU10E2d1eKGHIh59UaUjUNHvEYQuImuTyJ9VZij1cRsRe/+Vu+noXZHZ
# SyfB5ZyS+rTLUdacscOofp0+MIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAA
# AAAAFTANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUg
# QXV0aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQAD
# ggIPADCCAgoCggIBAOThpkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2
# AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpS
# g0S3po5GawcU88V29YZQ3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2r
# rPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k
# 45GPsjksUZzpcGkNyjYtcI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSu
# eik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09
# /SDPc31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR
# 6L8FA6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxC
# aC4Q6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaD
# IV1fMHSRlJTYuVD5C4lh8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMUR
# HXLvjflSxIUXk8A8FdsaN8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMB
# AAGjggHdMIIB2TASBgkrBgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQq
# p1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ
# 6XIwXAYDVR0gBFUwUzBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRt
# MBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBB
# MAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP
# 6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWlj
# cm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2
# LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMu
# Y3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2
# Pk5HZHixBpOXPTEztTnXwnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03d
# mLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99qb74py27YP0h1AdkY3m2CDPVtI1Tk
# eFN1JFe53Z/zjj3G82jfZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kp
# icO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKp
# W99Jo3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrY
# UP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QB
# jloZkWsNn6Qo3GcZKCS6OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkB
# RH58oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0V
# iY1w/ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq
# 0Z4+7X6gMTN9vMvpe784cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1V
# M1izoXBm8qGCA1AwggI4AgEBMIH5oYHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046OTIwMC0wNUUwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAH
# BgUrDgMCGgMVADhFYWz6ROJmehmICPUG1iPzMI1qoIGDMIGApH4wfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQELBQACBQDt0u2RMCIYDzIw
# MjYwNjA5MTk1MjQ5WhgPMjAyNjA2MTAxOTUyNDlaMHcwPQYKKwYBBAGEWQoEATEv
# MC0wCgIFAO3S7ZECAQAwCgIBAAICGDoCAf8wBwIBAAICElQwCgIFAO3UPxECAQAw
# NgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgC
# AQACAwGGoDANBgkqhkiG9w0BAQsFAAOCAQEARa/gS1LNe2bMSN3RZfh4Iptnbbis
# gkOjHMlVFsU+IcY1JXbWcPlTpo90Xg4fgvQOH3lVDXGaxqZdIZrr8qsy2L5N9869
# SOh1UwWu73FoZE8fQ4TO+Feo9UBi//hueYi+LIbGr/wyv1f3HGBgnLV3773OuMtb
# IFD1vY37geskSdWldCKyU3QzMdpYpSUGzZBMZIB3fn3dnl9/Aa/2R6H2LLbuM2KR
# uuamJgvPpJuOmxJ7S4TDsanDsWApE3i8V8vNiifD7cBsUngtid5QcEqdBFpWNFxz
# qniifaV2uBuGANuK7oZdF2uSDq1FpuA8Iq1T9F4jjdlyDV2rA3CpbTQn5TGCBA0w
# ggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACI0/Z
# YCRTz/4rAAEAAAIjMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYL
# KoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEICJ0IyE96ZRoNRWjcR+iMTqzCLbd
# RmKma7p2xcsuLJwZMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQglvAzLBFu
# 9waLKeOfCMCpxoPjvJi95splEC+0QBHm7rMwgZgwgYCkfjB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiNP2WAkU8/+KwABAAACIzAiBCCaPO2kZ9hX
# I9oe5wBIsgWdtsH7wgja6EbWE0xqpQIkjTANBgkqhkiG9w0BAQsFAASCAgA2IU2d
# wxyyHjWaZPgei/h8p5HoWsOQDJ8L2KaESK/rK0WnJAt6wAoYaExz0yqoT8TKKpPE
# uem6soVE8pK+AfW6KzTfs4Q75YWRssZsba1wVnoz44N/mVkQJuMcj8cCu4v899Pp
# 1i3dKyLpz/qUxrR76No4ibpkqp7FooR4vEXPaC/8vaWy7rf3BQ6FpDO7Sd/AbTNq
# orGEpIl4mLiHmt2d2U9FXurs+rkm74XQEsyvA3vmXtJUVmdFt7Fhscmh+2bkuMkn
# 9sdouG08aDY+nM//W+DqOV3KrV+4hgc21F6X4HLNXScvbxEjvpcf2akiq0qBn9c4
# EigkfYb21WTYc1xUvgcYPprwqZGtCBPPkP1JoOljoNTBlCrk6OcGqXaiwAV7hf43
# tywUJmUllXpI+Ss1gsNiGUM7vZoKoQ4qzHs+gg+X4W0mvwpbUiENOj2BszuzUsCC
# VEft17Ih7o/+ziwdFLrR/M9sKbZdK85xxi+DcdI40viaVtqRR+S9wrAdxCsUm33B
# D4ZPPH52aqYtWdMxfc2ZXeA4olIVmso8tou+t6s7wHDPhp1n7PLrCoXFsKHSutrH
# bSeh9syivP1UX8ozVGDhNswUJWFfedqwl3y86s12irIerdrz2MWB3veKF/KYxcRY
# G0y+EHO33HeHsRrFGGmDQr/18nvUYEDuMlpR3g==
# SIG # End signature block
