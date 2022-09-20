#
# Version 1.0
#
#========================== IMPORTANT DISCLAIMER ==========================
# PLEASE DO NOT RUN THIS SCRIPT IN A PRODUCTION ENVIRONMENT.
# This script is provided as a sample for reference purposes only.
# Please read it and create your own script.
#==========================================================================
#
# Reset a printer that is registered with Universal Print.
# 
# The script can help reset an existing printer that is registered with Universal Print. If the printer
# is having issues printing successfully, or showing the correct printer status, resetting it may help
# clear the issue. This is similar to restarting the Print Connector service or restarting the machine.
#
# Run the script locally using an elevated Powershell window, from the same machine that has the 
# Universal Print Connector installed.

param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$PrinterName
)

function Get-ConnectorServiceUri 
{
    $servicePort = Get-ItemPropertyValue -path HKLM:SOFTWARE\Microsoft\UniversalPrint\Connector -Name ServicePort
    $uri = "http://localhost:$servicePort/WindowsServiceHostedService/PrinterConnectorService?wsdl"
    return $uri;
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

    # Reset the given printer
    $ConnectorService.ResetPrinterAsync($PrinterName);
    
    Write-Host "Check PrintConnector event logs to verify if the printer is reset and initialized successfully."
}

## Invoke the main method
#Invoke-Main
