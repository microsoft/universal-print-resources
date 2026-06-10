<#
.SYNOPSIS
    Removes Azure infrastructure provisioned for the Universal Print Logs and Alerts feature.

.DESCRIPTION
    Customer-facing cleanup script. Removes resources created by Setup-AlertingInfrastructure.ps1
    when the administrator no longer needs the Logs and Alerts feature.
    
    Resources that can be deleted:
    - Data Collection Rule (DCR)
    - Custom tables (UniversalPrintPrinterHealth_CL, UniversalPrintJob_CL, UniversalPrintBillingSummary_CL) - optional
    - Log Analytics Workspace - optional
    - Resource Group - optional

.NOTES
    Version: 0.2.0
    Last Updated: 2026-01-07

.PARAMETER TenantId
    Required. Your Azure Active Directory Tenant ID (GUID format).

.PARAMETER SubscriptionId
    Required. The Azure Subscription ID where resources exist.

.PARAMETER ResourceGroupName
    Required. Name of the resource group containing the resources.

.PARAMETER WorkspaceName
    Required. Name of the Log Analytics workspace.

.PARAMETER DcrName
    Optional. Name of the Data Collection Rule. Defaults to "dcrup-<WorkspaceName>".

.PARAMETER DeleteTables
    Optional. If specified, deletes the custom tables (UniversalPrintPrinterHealth_CL, UniversalPrintJob_CL, UniversalPrintBillingSummary_CL).
    WARNING: This will permanently delete all log data in these tables.

.PARAMETER DeleteWorkspace
    Optional. If specified, deletes the entire Log Analytics workspace.
    WARNING: This will permanently delete all data in the workspace.

.PARAMETER DeleteResourceGroup
    Optional. If specified, deletes the entire resource group and ALL resources within it.
    WARNING: This will delete everything in the resource group, not just alerting resources.

.PARAMETER Force
    Optional. Skip confirmation prompts.

.PARAMETER AzureEnvironment
    Optional. Azure cloud environment. Use 'AzureUSGovernment' for GCC High/DOD,
    'AzureChinaCloud' for China. Defaults to 'AzureCloud' (public/GCC).

.EXAMPLE
    # Delete only DCR (keep workspace and tables with data)
    .\Cleanup-AlertingInfrastructure.ps1 `
        -TenantId "12345678-1234-1234-1234-123456789012" `
        -SubscriptionId "87654321-4321-4321-4321-210987654321" `
        -ResourceGroupName "rg-universalprint-alerting" `
        -WorkspaceName "law-universalprint"

.EXAMPLE
    # Delete DCR and tables (but keep workspace)
    .\Cleanup-AlertingInfrastructure.ps1 `
        -TenantId "12345678-1234-1234-1234-123456789012" `
        -SubscriptionId "87654321-4321-4321-4321-210987654321" `
        -ResourceGroupName "rg-universalprint-alerting" `
        -WorkspaceName "law-universalprint" `
        -DeleteTables

.EXAMPLE
    # Delete everything including the resource group (no confirmation)
    .\Cleanup-AlertingInfrastructure.ps1 `
        -TenantId "12345678-1234-1234-1234-123456789012" `
        -SubscriptionId "87654321-4321-4321-4321-210987654321" `
        -ResourceGroupName "rg-universalprint-alerting" `
        -WorkspaceName "law-universalprint" `
        -DeleteResourceGroup `
        -Force

.NOTES
    PERMISSIONS REQUIRED:
    - Contributor (or Owner) on the resource group (for DCR and workspace deletion)
    - User Access Administrator (or Owner) on the workspace scope (for RBAC removal)
    - If -DeleteTables: Contributor on the workspace (for table deletion)
    - If -DeleteResourceGroup: Contributor on the resource group
    
    SOVEREIGN CLOUD SUPPORT:
    Use -AzureEnvironment to target sovereign clouds:
    - AzureCloud (default) — Public / GCC
    - AzureUSGovernment — GCC High / DOD
    - AzureChinaCloud — China (21Vianet)
    
    PREREQUISITES:
    - Azure PowerShell (Az module): Az.Accounts, Az.OperationalInsights, Az.Resources, Az.Monitor
#>

param(
    [Parameter(Mandatory = $true, HelpMessage = "Your Azure AD Tenant ID")]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$TenantId,
    
    [Parameter(Mandatory = $true, HelpMessage = "Azure Subscription ID")]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true, HelpMessage = "Resource group name")]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true, HelpMessage = "Log Analytics workspace name")]
    [string]$WorkspaceName,
    
    [Parameter(Mandatory = $false, HelpMessage = "Resource group for DCR (defaults to ResourceGroupName)")]
    [string]$DcrResourceGroupName = $ResourceGroupName,
    
    [Parameter(Mandatory = $false, HelpMessage = "Data Collection Rule name")]
    [string]$DcrName = "dcrup-$WorkspaceName".Substring(0, [Math]::Min("dcrup-$WorkspaceName".Length, 30)),
    
    [Parameter(Mandatory = $false, HelpMessage = "Delete custom tables (WARNING: deletes all log data)")]
    [switch]$DeleteTables,
    
    [Parameter(Mandatory = $false, HelpMessage = "Delete the entire Log Analytics workspace")]
    [switch]$DeleteWorkspace,
    
    [Parameter(Mandatory = $false, HelpMessage = "Delete the entire resource group")]
    [switch]$DeleteResourceGroup,
    
    [Parameter(Mandatory = $false, HelpMessage = "Skip confirmation prompts")]
    [switch]$Force,

    [Parameter(Mandatory = $false, HelpMessage = "Azure cloud environment. Use 'AzureUSGovernment' for GCC High/DOD, 'AzureChinaCloud' for China.")]
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

Write-Host "=============================================="
Write-Host "Universal Print Alerting - Cleanup Script"
Write-Host "=============================================="
Write-Host ""

#------------------------------------------------------------------------------------------------------------
# Display What Will Be Deleted
#------------------------------------------------------------------------------------------------------------
Write-Host "Resources to be deleted:"
Write-Host "  - Data Collection Rule (DCR): $DcrName"
Write-Host "  - RBAC: DCR-scoped role assignments (removed automatically with DCR)"
Write-Host "  - RBAC: Workspace-scoped Log Analytics Contributor (removed explicitly)"

if ($DeleteTables) {
    Write-Host "  - Table: UniversalPrintPrinterHealth_CL (WITH ALL DATA)" -ForegroundColor Yellow
    Write-Host "  - Table: UniversalPrintJob_CL (WITH ALL DATA)" -ForegroundColor Yellow
    Write-Host "  - Table: UniversalPrintBillingSummary_CL (WITH ALL DATA)" -ForegroundColor Yellow
}

if ($DeleteWorkspace) {
    Write-Host "  - Log Analytics Workspace: $WorkspaceName (WITH ALL DATA)" -ForegroundColor Yellow
}

if ($DeleteResourceGroup) {
    Write-Host "  - Resource Group: $ResourceGroupName (ALL RESOURCES)" -ForegroundColor Red
}

Write-Host ""

if (-not $DeleteTables -and -not $DeleteWorkspace -and -not $DeleteResourceGroup) {
    Write-Host "Resources preserved:" -ForegroundColor Green
    Write-Host "  - Log Analytics Workspace: $WorkspaceName"
    Write-Host "  - Custom Tables (with all log data)"
    Write-Host ""
}

#------------------------------------------------------------------------------------------------------------
# Confirmation
#------------------------------------------------------------------------------------------------------------
if (-not $Force) {
    $confirmation = Read-Host "Are you sure you want to delete these resources? (yes/no)"
    if ($confirmation -ne "yes") {
        Write-Host "Cleanup cancelled."
        exit 0
    }
    Write-Host ""
}

#------------------------------------------------------------------------------------------------------------
# Connect to Azure
#------------------------------------------------------------------------------------------------------------
Write-Host "Connecting to Azure ($AzureEnvironment)..."
$context = Get-AzContext
if (-not $context -or $context.Tenant.Id -ne $TenantId -or $context.Environment.Name -ne $AzureEnvironment) {
    try {
        Connect-AzAccount -Tenant $TenantId -Environment $AzureEnvironment -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
    } catch {
        Exit-WithError "Failed to connect to Azure: $($_.Exception.Message)"
    }
}

if ((Get-AzContext).Subscription.Id -ne $SubscriptionId) {
    try {
        Set-AzContext -Subscription $SubscriptionId -Tenant $TenantId -ErrorAction Stop | Out-Null
    } catch {
        Exit-WithError "Failed to switch subscription context: $($_.Exception.Message)"
    }
}
Write-Host "Connected to subscription: $SubscriptionId"
Write-Host ""

#------------------------------------------------------------------------------------------------------------
# Check if Resource Group Exists
#------------------------------------------------------------------------------------------------------------
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Host "Resource group '$ResourceGroupName' does not exist. Nothing to clean up." -ForegroundColor Yellow
    exit 0
}

#------------------------------------------------------------------------------------------------------------
# Option 1: Delete Entire Resource Group
#------------------------------------------------------------------------------------------------------------
if ($DeleteResourceGroup) {
    Write-Host "Deleting resource group '$ResourceGroupName' and all resources..."
    Write-Host "  This may take several minutes..."
    
    try {
        Remove-AzResourceGroup -Name $ResourceGroupName -Force -ErrorAction Stop | Out-Null
        Write-Host "Resource group deleted successfully." -ForegroundColor Green
    } catch {
        Exit-WithError "Failed to delete resource group: $($_.Exception.Message)"
    }
    
    Write-Host ""
    Write-Host "=============================================="
    Write-Host "CLEANUP COMPLETE"
    Write-Host "=============================================="
    exit 0
}

#------------------------------------------------------------------------------------------------------------
# Delete Data Collection Rule (DCR)
#------------------------------------------------------------------------------------------------------------
Write-Host "Deleting Data Collection Rule '$DcrName'..."
$dcr = Get-AzDataCollectionRule -ResourceGroupName $DcrResourceGroupName -Name $DcrName -ErrorAction SilentlyContinue
if ($dcr) {
    try {
        Remove-AzDataCollectionRule -ResourceGroupName $DcrResourceGroupName -Name $DcrName -ErrorAction Stop | Out-Null
        Write-Host "  DCR deleted." -ForegroundColor Green
    } catch {
        Exit-WithError "Failed to delete DCR: $($_.Exception.Message)"
    }
} else {
    Write-Host "  DCR not found (already deleted or never created)." -ForegroundColor Yellow
}

#------------------------------------------------------------------------------------------------------------
# Remove Workspace-Scoped RBAC (Log Analytics Contributor) for Universal Print
#------------------------------------------------------------------------------------------------------------
Write-Host "Removing workspace-scoped RBAC for Universal Print..."
$LogAnalyticsContributorRoleId = "92aaf0da-9dab-42b6-94a3-d43ce8d16293"
$UniversalPrintAppId = "da9b70f6-5323-4ce6-ae5c-88dcc5082966"
$workspaceScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"

# Look up UP service principal (using Az module, no Graph SDK dependency)
$sp = Get-AzADServicePrincipal -ApplicationId $UniversalPrintAppId -ErrorAction SilentlyContinue
if ($sp) {
    $wsRoleAssignments = Get-AzRoleAssignment -Scope $workspaceScope -ObjectId $sp.Id -ErrorAction SilentlyContinue |
        Where-Object { $_.RoleDefinitionId -match $LogAnalyticsContributorRoleId }
    foreach ($ra in $wsRoleAssignments) {
        try {
            Remove-AzRoleAssignment -InputObject $ra -ErrorAction Stop | Out-Null
            Write-Host "  Removed Log Analytics Contributor role from workspace." -ForegroundColor Green
        } catch {
            Write-Host "  WARNING: Failed to remove workspace RBAC: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    if (-not $wsRoleAssignments) {
        Write-Host "  No workspace-scoped role assignments found." -ForegroundColor Yellow
    }
} else {
    Write-Host "  Could not look up Universal Print service principal. Skipping workspace RBAC cleanup." -ForegroundColor Yellow
    Write-Host "  You may need to manually remove the Log Analytics Contributor role." -ForegroundColor Yellow
}

#------------------------------------------------------------------------------------------------------------
# Delete Custom Tables (Optional)
#------------------------------------------------------------------------------------------------------------
if ($DeleteTables) {
    Write-Host "Deleting custom tables..."
    
    # Verify workspace exists before attempting to delete tables
    $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ErrorAction SilentlyContinue
    if (-not $workspace) {
        Write-Host "  Workspace '$WorkspaceName' not found. Skipping table deletion." -ForegroundColor Yellow
    } else {
        $tables = @("UniversalPrintPrinterHealth_CL", "UniversalPrintJob_CL", "UniversalPrintBillingSummary_CL")
        
        foreach ($tableName in $tables) {
            Write-Host "  Deleting table '$tableName'..."
            $tableUri = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/tables/$tableName"
            
            $result = Invoke-AzRestMethod -Path "$tableUri`?api-version=2022-10-01" -Method DELETE -ErrorAction SilentlyContinue
            if ($result.StatusCode -eq 200 -or $result.StatusCode -eq 202 -or $result.StatusCode -eq 204) {
                Write-Host "    Table '$tableName' deleted." -ForegroundColor Green
            } elseif ($result.StatusCode -eq 404) {
                Write-Host "    Table '$tableName' not found." -ForegroundColor Yellow
            } else {
                Exit-WithError "Failed to delete '$tableName': Status $($result.StatusCode), Response: $($result.Content)"
            }
        }
    }
}

#------------------------------------------------------------------------------------------------------------
# Delete Log Analytics Workspace (Optional)
#------------------------------------------------------------------------------------------------------------
if ($DeleteWorkspace) {
    Write-Host "Deleting Log Analytics Workspace '$WorkspaceName'..."
    
    $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ErrorAction SilentlyContinue
    if ($workspace) {
        try {
            # Force delete to skip soft-delete (30 day retention)
            Remove-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ForceDelete -Force -ErrorAction Stop | Out-Null
            Write-Host "  Workspace deleted (permanently, skipped soft-delete)." -ForegroundColor Green
        } catch {
            Exit-WithError "Failed to delete workspace: $($_.Exception.Message)"
        }
    } else {
        Write-Host "  Workspace not found (already deleted or never created)." -ForegroundColor Yellow
    }
}

#------------------------------------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------------------------------------
Write-Host ""
Write-Host "=============================================="
Write-Host "CLEANUP COMPLETE"
Write-Host "=============================================="
Write-Host ""
Write-Host "Deleted resources:"
Write-Host "  - DCR: $DcrName"

if ($DeleteTables) {
    Write-Host "  - Tables: UniversalPrintPrinterHealth_CL, UniversalPrintJob_CL, UniversalPrintBillingSummary_CL"
}

if ($DeleteWorkspace) {
    Write-Host "  - Workspace: $WorkspaceName"
}

Write-Host ""
Write-Host "Resources preserved:"
if (-not $DeleteTables -and -not $DeleteWorkspace) {
    Write-Host "  - Workspace: $WorkspaceName (with all data)"
    Write-Host "  - Tables: UniversalPrintPrinterHealth_CL, UniversalPrintJob_CL, UniversalPrintBillingSummary_CL (with all data)"
} elseif (-not $DeleteWorkspace -and $DeleteTables) {
    Write-Host "  - Workspace: $WorkspaceName"
}
Write-Host "  - Resource Group: $ResourceGroupName"
Write-Host ""

# SIG # Begin signature block
# MIInRgYJKoZIhvcNAQcCoIInNzCCJzMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAcRlQ2hTfGzvDf
# MMK1Tbh3ImPM1QHf8TpAbil0gzTw7KCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghniMIIZ3gIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIIZZiDAa
# qcv2nGIQ2cMh7Nvmkn3l1IHnkmizPzpNWKhzMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAYTJYlImMSHataRFdRudYCEfceLvmiYea3OWLboqH
# KlCJpTsIiugg4JYgfFjLxTQOiFg3TNd3i/22Y0JM4DqS6Dh4iHQFPd2/VDsKS+BK
# s51+2y185CjMRRBobwWfYb3pS4lBUx92HscGqYRs2DkRosl4wxVhwDqAIU2LEb5C
# ESTIRIWDZw7Z79RyIl7TJWv27450vYkfgpvu14a9PHF3yWA3vI2JiEB1KgkeUovY
# SxsL7fzQ7sXNr6crCC+X5XoKdUaPHJJ8DanpsLvL5GWJkYW4pcvbVgtRiTqP29Yx
# IX3NUfsnP5dtJzgZEDT22e5wLvPpMxhoHvIb0enrviOax6GCF5QwgheQBgorBgEE
# AYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCD3xwlc1hFlz6G/RfyL0eFyiNOWez/YCP0HYHHn
# EIM/sgIGahdSWabVGBMyMDI2MDYwOTE3MjE1OC4yMTRaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046MzcwMy0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIBAgITMwAAAh86cGnkojAulQABAAAC
# HzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTM5NTFaFw0yNzA1MTcxOTM5NTFaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046MzcwMy0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDLO8XFOcfGqAqgiz0+AmQmFl3d
# Z0aTG4UFJkqqNdMHy28DaheCBs6ONufukye5x42CWkzgRIy9kE2VWwEntZ8Zkgyr
# ykC0bIqsID7+6FxguseTXf1Vwvm1D8104VmetoBJlJ4uGbuyJZUvXDx55nVh50yg
# LTzZ24WkQsnPpvRZv2kPc39f3bhLyHVtnHsa/W/86Vrftd+AfFveA+qN/EY+XGj5
# c/DPMXCYECb0arYb92dDJWtwzpyBrp4gfHlgY1UEpc4l4AGELrf2J4wrxTzTW+SM
# 8XhV1dOOPrYjD080IbZqL8B+IF0RCdn269YXrGK6QIHipznKZcCS8jN30YAHnTJV
# N5Zzs6t/2YsqBGDquvDad7934FFTwzvUcO3VoIyd93XWwvP8/SCFVJh21W8oGQTp
# tGHyly+Fl4henVMVZF1v6osOtirX8GFTiEhnf8nRdOg7yZYAJ0xy9CtDfbXaTn/c
# f3Lq3N/GCYKFjC+5mUCE+AJhmxMuMdvSUGmKiAFdiPAjUTqsWWBBZJm0eCwgeGJF
# mmQA+V7/98BKcE+gUL7O9eWRDQwKeAcvo6rxNv2Y4jKrHA6Z/wi3a/fKUhLCNZES
# 8qGdrpDAm7qh+6FjYxytAbkiKM6uTNy/ULPlwtlYZoAJDDQP7eYCywwVbNTbHXRB
# SS+NccC0sSB4W7U67wIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFNk72sGDlH0r5Dwv
# fGR5XwJI8B7bMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQBlbu3IoynnPz0K1iPb
# eNnsej2b15l5sdl2FAFBBGT9lRdc2gNV8LAIusPYHHhUvRDcsx4lbMNhVKPGu4TD
# LaqNt/CI+SFtGuqdRLpVP1XE9cCLyKrKPpcJFJCqPpV+efoAtYBmIUQcxxwT7WIQ
# 7gag8+rkKvrMkCoRqKS0mKv8J1sKfi85+G2uhZ/1RteSVdYZOZOj+Sb4wzonTCTj
# 7EtgMN/BX35W5dTzd7wJdGepYkVi871dSrC2Tr1ZFzAR7S44drCWZpJ6phJabVNO
# sNxFJKgSykugOGWzQ318Rr3MTPg2s3Bns+pUPVgMijd4bUOH2BlEsLMMwOcolTTZ
# qg1HYrdY1jxpUAI9ipjBQRINL/O705Z+/f2LjNmJQooCVJVX24adpZ519SsfazGo
# qXGt91bmqKo0fI09Il4sUHh4ih6rpiQDBlyL7vmvCejwVxYevY4qVwTZ/o3gvl+R
# 0lFxYS9feIM4NeG0+WsDZ7jLci5MFeuNwosQY3z26Xg1oj0U9u+ncR9uTU+xBmJ8
# BtlCdhQ13RNMX5P+krRYPB3XCp9Jm6XaO1995q32AIZm1mzBGI6yHlviXaEC5TzG
# iO1LXuPtXZU2X93oQJbMoe3v8+5CPKrQalGWyYuh2a3V1pwbj+W0FEmEFPpu8TI+
# qYO1IIQWUSRvFjXth5Ob02hMMjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
# AAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVow
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX
# 9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1q
# UoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8d
# q6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byN
# pOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2k
# rnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4d
# Pf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgS
# Uei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8
# QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6Cm
# gyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzF
# ER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQID
# AQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQU
# KqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1
# GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0
# bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMA
# QTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbL
# j+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1p
# Y3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0w
# Ni0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIz
# LmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwU
# tj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN
# 3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU
# 5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5
# KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGy
# qVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB6
# 2FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltE
# AY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFp
# AUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcd
# FYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRb
# atGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQd
# VTNYs6FwZvKhggNNMIICNQIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjM3MDMtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQBLIMg1P7sNuCXpmbH2IXT2tXeEEKCBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7dJJ1DAiGA8y
# MDI2MDYwOTA4MTQxMloYDzIwMjYwNjEwMDgxNDEyWjB0MDoGCisGAQQBhFkKBAEx
# LDAqMAoCBQDt0knUAgEAMAcCAQACAj1lMAcCAQACAhSfMAoCBQDt05tUAgEAMDYG
# CisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEA
# AgMBhqAwDQYJKoZIhvcNAQELBQADggEBALK+xz2OK9FE8zaKSnHYP0e83nrbVTmP
# gOWaHkwoWcP8ypr0X2wdpxTQ4RnnalTUB8xT3Kjrnq6TOqJBePSmUBCyqxSllLQB
# JGwK7uK92OKnb262QG3ExFeKN0S3XH2Fj27ZXLWit/Tcs3jBDxI6DqpluG6xbUiZ
# pjr2mF8lx6ORyWD9W0zD1y5/opgR7pDDpyt7z1ILZFWqTsgKMRW5wMHnScBOa7Aj
# igXzTErlLOyGY/UHGmIJye90LcbnXSG87FC/nWtznWQPK1QZl2slN1EkrzUPkyMe
# TxtZuPjrDqP2Lx1DS2wq8oqthPNrF2VJCOewaaOolLVh3xpqyILPzzwxggQNMIIE
# CQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
# JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAh86cGnk
# ojAulQABAAACHzANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqG
# SIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCA79RqgB+txk2f5Rq9Hh8RiVu6axO1E
# PU0hlNF390PCdjCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EILAkCt9WkCsM
# tURkFu6TY0P3UXdRnCiYuPZhe3ykLfwUMIGYMIGApH4wfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTACEzMAAAIfOnBp5KIwLpUAAQAAAh8wIgQgtTFo/XfEJIya
# KfrLfvKGWTmZ5Pau2poPgCls6JJ9VEIwDQYJKoZIhvcNAQELBQAEggIAhhVS739L
# FJU+Ox0vmI1Q5a7fD4bzvzt/rDEqJUHivXxTppOFRrNVDO2fJVrRTCSAnjqx4peI
# GoFlbctRmgZXuVdvKu3Zuyy+msMdXGP33jB/edAT2OXS0bvx15YdhX7OEv2Yvlby
# cbiPJ37opAS4LAK6ylR0yjxHefCYx2L4xkU76GoyS2n73MiViaIptInx/WFrmYGM
# SUepIHMRSCLJHhonU7jF53kXD0819pfcETsM1YRfH1TEt5+ABgFGkLxqJXVUDzoN
# Z4ZB7mWw068+7C0w63kGWhgWcUdm9WNH1uAVdNO9s0H+fKunzbt/T+HOCSow+v1e
# 0CUUhWrHjrBe29EKgho4wtanL0W72lLs90A59DGDRblr7LwCsNhhmIHDFWtN/AVA
# n7Ci4b/8Ewp4bXzef1JEZHPIQ+XV5G7Cgott7ttas6wPomoQNboQLrP+4ZSsEnbh
# BxdtN1ldg+bH714vcauE5BrDiGEBphvYERzNGQP7dUVZ8uUFN0PGNu/q/TxlJZ4q
# uXauok2UFvvyCymMTZGGtzxYSs8ocqDuLkXbUeyrFTT+TH6jZNfKhlaB7tbFxvME
# TIDgySre+SKse7rrxoMZ6lX0ce8qH/uctIvjrGy0qdqH5YhikjsKhXCmThFTmeg/
# RqpqlRg8PzjyAr1WbdSyZLj6b179bE4SD8Q=
# SIG # End signature block
