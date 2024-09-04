#
# Version 1.0
#
#========================== IMPORTANT DISCLAIMER ==========================
# PLEASE DO NOT RUN THIS SCRIPT IN A PRODUCTION ENVIRONMENT.
# This script is provided as a sample for reference purposes only.
# Please read it and create your own script.
#==========================================================================

# This script cleans up the connector from both local machine and Universal Print service.
# All printers registered via this connector will be unshared, unregistered
# and removed from the locally cached registration data. 
# All associated printer certificates will also be deleted. The connector will be
# unregistered and associated data will also be deleted from the local machine.
#
# Run this on the same machine as that has the connector (to be cleaned up) installed.
#
#========================== IMPORTANT DISCLAIMER ==========================
# THE CHANGES THIS SCRIPT MAKES CANNOT BE ROLLED BACK!
# THE DATA THIS SCRIPT REMOVES IS NOT RECOVERABLE!
#==========================================================================


param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$ConnectorName
)

# Install the required module by running Install-Module "UniversalPrintManagement"
#Requires -Modules "UniversalPrintManagement"

function CleanupConnector {
    Param(
        [Parameter(Mandatory=$true)]
        [string] $ConnectorName
    )

    Write-Host "Checking for elevated permissions..."
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        throw "Insufficient permissions to run this script. Open the PowerShell console as an administrator and run this script again."
    }

    # Warn the user; these actions are not recoverable
    Write-Warning "This script will unshare/unregister all printers associated with this connector, and unregister the connector. The actions are not recoverable." -WarningAction Inquire

    # Stop services
    net stop "Print Connector service"
    net stop PrintConnectorUpdaterSvc

    $LocalConnector = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\UniversalPrint\Connector'

    # Ensure that the connector name provided is same as the connector installed on this machine
    if ($LocalConnector.Name -ne $ConnectorName) {

    # Format the error message. Avoid whitespace as those will show up in actual message.
    $errorMessage=@"
The locally installed connector $($LocalConnectorName) does not match the name provided to this script $($ConnectorName).
`nYou must run this script on the same machine as the connector that is to be cleaned up.
"@

    throw $errorMessage

    }

    $ConnectorId = $LocalConnector.CloudDeviceId

    # Ensure we are connected to UP
    Connect-UPService | Out-Null

    Write-Warning "Getting the connector object from Universal Print..."

    $Connector = (Get-UPConnector -ConnectorId $ConnectorId).Results

    if (!$Connector) {
        throw "Terminating the script as connector information could not be retrieved from Universal Print."
    }

    Write-Warning "Getting the printers registered with this connector..."

    do
    {
        $resp = Get-UPPrinter -IncludeConnectorDetails -ContinuationToken $resp.ContinuationToken 
        $ConnectorPrinters += $resp.Results | Where-Object {$_.Connectors.Id -eq $Connector.Id}
    }
    while (![string]::IsNullOrEmpty($resp.ContinuationToken))

    Write-Warning "Found $($ConnectorPrinters.Length) printer(s) registered to connector $ConnectorName"

    if ($ConnectorPrinters)
    {
        Write-Warning "Unsharing all the printers..."
        $ConnectorPrinters.Shares | ForEach-Object {Remove-UPPrinterShare -ShareId $_.Id -Confirm | Out-Null}

        Write-Warning "Unregistering all the printers..."
        $ConnectorPrinters | ForEach-Object {Remove-UPPrinter -PrinterId $_.Id -Confirm | Out-Null}

        Write-Warning "Deleting the local registration data for all the printers..."
        Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers' -Rec -EA SilentlyContinue | ForEach-Object {
            $CurrentKey = (Get-ItemProperty -Path $_.PsPath)
            If ($CurrentKey -match 'CloudData'){
                $CurrentKey|Remove-Item -Force
            }
        }
    }

    Write-Warning "Unregistering the connector..."
    $Connector | Remove-UPConnector -Confirm | Out-Null

    Write-Warning "Deleting the local connector registration data..."
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\UniversalPrint' -Rec -EA SilentlyContinue | Remove-Item -Recurse -Force

    Write-Warning "Deleting the local printer/connector certificates..."
    $ConnectorCerts = Get-ChildItem cert:\LocalMachine\PrintProxyStore -recurse  | select *  
    $ConnectorCerts | Remove-Item 

    # Manually uninstall the Connector application 
    $response = read-host "Please uninstall the connector software from Settings -> Apps or Start -> Run -> appwiz.cpl. Once the connector is uninstalled, press any key to continue."
    if ($response)
    {
        Write-warning "Deleting the connector's application data"
        Get-ChildItem -Path $env:ProgramData\Microsoft\UniversalPrintConnector -EA SilentlyContinue | Remove-Item -Recurse -Force
    }
}

## Invoke the main method
CleanupConnector $ConnectorName
