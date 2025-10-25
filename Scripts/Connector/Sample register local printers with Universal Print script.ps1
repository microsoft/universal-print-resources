#
# Version 1.0
#
#========================== IMPORTANT DISCLAIMER ==========================
# PLEASE DO NOT RUN THIS SCRIPT IN A PRODUCTION ENVIRONMENT.
# This script is provided as a sample for reference purposes only.
# Please read it and create your own script.
#==========================================================================
#
# Register local printers with Universal Print.
# 
# The script will enumerate locally installed printers that can be registered with Universal Print,
# and call the Universal Print Connector service (running locally) to register the printer with 
# Universal Print service.
# 
# This script automates the process of logging into the PrintConnectorApp, selecting all printers, 
# and clicking the Register button.
#
# Run the script locally using an elevated Windows Powershell window, from the same machine that has
# the Universal Print Connector installed.

# Only Windows Powershell supports calling into the Connector using New-WebServiceProxy
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $psISE) {
    Write-Error "This script must be run in Windows PowerShell console only (not ISE or Core)."
    exit 1
}

# Install the required module by running Install-Module "Microsoft.Identity.Client"
#Requires -Modules "Microsoft.Identity.Client"

Import-Module "Microsoft.Identity.Client"

function Get-ConnectorServiceUri 
{
    $servicePort = Get-ItemPropertyValue -path HKLM:SOFTWARE\Microsoft\UniversalPrint\Connector -Name ServicePort
    $uri = "http://localhost:$servicePort/WindowsServiceHostedService/PrinterConnectorService?wsdl"
    return $uri;
}

function Get-LocalPrintersFromConnector($ConnectorService)
{
    return $ConnectorService.GetLocalUnregisteredPrintersWithDeviceId()
}

function Get-PublicClientApplication
{
    # Universal Print Connector's client id to retrieve an AAD authentication token
    $ClientId = "80331ee5-4436-4815-883e-93bc833a9a15"
    $Authority = "https://login.microsoftonline.com/common"
    $RedirectUri = "https://UniversalPrintConnector"
    $pcaConfig = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($ClientId).WithAuthority($Authority).WithRedirectUri($RedirectUri)
    return $pcaConfig.Build();
}

function Register-LocalPrinterWithUP($ConnectorService, $PrinterName, $PrinterDeviceId, $Token)
{
    Write-Host Registering printer $PrinterName
    $result = $false
    $resultSpecified = $false
    $ConnectorService.RegisterPrinter($printerName, $PrinterDeviceId, "printer", $Token, [ref] $result, [ref] $resultSpecified)
    if ($result)
    {
        Write-Host "Successfully registered printer $PrinterName"
    }
    else
    {
        Write-Error "Failed to register $PrinterName printer. Please check the Event Viewer Log for details."
    }
}

function Invoke-Main
{
    $ConnectorServiceUri = Get-ConnectorServiceUri
    $ConnectorService = New-WebServiceProxy -Uri $ConnectorServiceUri -UseDefaultCredential

    # Ensure Connector is registered
    $isConnectorRegistered = $false;
    $isConnectorRegisteredSpecified = $false;
    $ConnectorService.IsConnectorRegistered([ref] $isConnectorRegistered, [ref] $isConnectorRegisteredSpecified)
    if (!$isConnectorRegistered)
    {
        Write-Error "Connector needs to be registered first. Please use the Print Connector App to register the Connector." -ErrorAction Stop
    }

    # Get local printers (not yet registered with UP) from the Connector service
    Write-Host "Getting list of printers from the Universal Print Connector"
    $localPrinters = Get-LocalPrintersFromConnector -ConnectorService $ConnectorService
    if ($localPrinters -eq $null)
    {
        Write-Host "No local printer available to register. Please see the Event Viewer Log for any printers that were filtered out and unsupported."
        return
    }
    
    $scope = "https://print.print.microsoft.com/.default";
    $scopes = New-Object System.Collections.Generic.List[string]
    $scopes.Add($scope)

    $publicClientApplication = Get-PublicClientApplication
    $account = $null
    foreach ($printer in $localPrinters)
    {
        # Refresh the existing token or get a new AAD auth token.
        Write-Host "Ensuring a valid AAD authentication token exists"

        if ($account -ne $null)
        {
            $authResult = $publicClientApplication.AcquireTokenSilent($scopes, $account).ExecuteAsync().Result
        }
    
        # Else if we don't have a valid account or if the silent call fails, get the token interactively
        if ($authResult -eq $null)
        {
            $authResult = $publicClientApplication.AcquireTokenInteractive($scopes).ExecuteAsync().Result
        }
    
        # Cache the account for subsequent usage
        $account = $authResult.Account

        # Register the given printer with UP
        Register-LocalPrinterWithUP -ConnectorService $ConnectorService -PrinterName $printer.m_Item1 -PrinterDeviceId $printer.m_Item2 -Token $authResult.AccessToken
    }
}

## Invoke the main method
# Invoke-Main
