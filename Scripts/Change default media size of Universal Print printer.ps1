# This script changes the default media size of a printer in Universal Print.
# It will install the Microsoft.Graph Powershell module if not installed.
# Run from an unelevated (i.e. not Admin) Powershell unless blocked by your environment.

param (
    [Parameter(Mandatory = $true, HelpMessage = "Printer ID from Azure Portal > Universal Print > Printers > click on printer > Printer Id")]
    [string]$PrinterId,

    [Parameter(Mandatory = $true, HelpMessage = "New default media size. Valid values are listed on https://learn.microsoft.com/en-us/graph/api/resources/printercapabilities?view=graph-rest-1.0#mediasizes-values")]
    [string]$MediaSize
)

$ErrorActionPreference = 'Stop'

# Ensure Microsoft Graph module is installed
Write-Host "Checking if Microsoft Graph Powershell module is installed..."
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Host "Installing Microsoft Graph Powershell module..."
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

# Connect to Microsoft Graph with required permissions
Write-Host "Logging in..."
Connect-MgGraph -Scopes "Printer.ReadWrite.All"

# Confirm connection
$context = Get-MgContext
if (-not $context) {
    Write-Error "Authentication failed. Please try again."
    exit
}

# Prepare the request body
$body = @{
    defaults = @{
        mediaSize = $MediaSize
    }
} | ConvertTo-Json -Depth 3

# Send PATCH request to update printer defaults
Write-Host "Updating default media size to '$MediaSize' for printer ID: $PrinterId ..."
$response = Invoke-MgGraphRequest -Method PATCH `
    -Uri "https://graph.microsoft.com/v1.0/print/printers/$PrinterId" `
    -Body $body `
    -ContentType "application/json"

Write-Host "Default media size updated to '$MediaSize' for printer ID: $PrinterId"

# Retrieve and display the updated printer defaults
Write-Host "Getting defaults for printer ID: $PrinterId ..."
$printer = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/print/printers/$PrinterId"

Write-Host "Current Printer Defaults for printer ID: $PrinterId :"
$printer.defaults | Format-List
