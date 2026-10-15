#
# Version 1.1
#
# Changes in version 1.1:
#  - Can be run after the connector software has already been uninstalled.
#  - Continues with the local cleanup when the connector or a printer no longer exists in Universal Print.
#  - Adds -LocalCleanupOnly to clean up this machine without signing in to Universal Print.
#  - Removes the local registration data regardless of what is found in Universal Print.
#  - Validates the environment and signs in to Universal Print before making any changes.
#  - Keeps the data needed to run the script again if the local cleanup doesn't complete.
#
#========================== IMPORTANT DISCLAIMER ==========================
# This script is provided as a sample for reference purposes.
# Please read it and adapt it for your specific needs.
#==========================================================================

# This script cleans up the connector from both local machine and Universal Print service.
# All printers registered via this connector will be unshared, unregistered
# and removed from the locally cached registration data.
# All associated printer certificates will also be deleted. The connector will be
# unregistered and associated data will also be deleted from the local machine.
#
# Locally installed print queues are NOT deleted. Only the Universal Print data that the
# connector stores for them (the CloudData registry key of each print queue) is removed.
#
# Run this on the same machine as that has the connector (to be cleaned up) installed.
# The script can also be run after the connector software has been uninstalled.
#
# If the connector or a printer no longer exists in Universal Print, the script skips that
# Universal Print operation and still cleans up the local data.
#
# Use -LocalCleanupOnly to skip all Universal Print operations (no sign-in is needed).
# Any printers or connector still registered in Universal Print must then be unregistered
# from the Azure portal.
#
# Examples:
#   .\SampleConnectorCleanupScript.ps1 -ConnectorName "My Connector"
#   .\SampleConnectorCleanupScript.ps1 -ConnectorName "My Connector" -LocalCleanupOnly
#
#========================== IMPORTANT DISCLAIMER ==========================
# THE CHANGES THIS SCRIPT MAKES CANNOT BE ROLLED BACK!
# THE DATA THIS SCRIPT REMOVES IS NOT RECOVERABLE!
#==========================================================================


param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$ConnectorName,

    # Skip all Universal Print operations and only clean up the local machine.
    [switch]$LocalCleanupOnly
)

# Cleaning up Universal Print (without -LocalCleanupOnly) requires the UniversalPrintManagement module.
# Install the module by running Install-Module "UniversalPrintManagement"

$PrintersRegistryPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers'
$UniversalPrintRegistryPath = 'HKLM:\SOFTWARE\Microsoft\UniversalPrint'
$ConnectorRegistryPath = Join-Path $UniversalPrintRegistryPath 'Connector'
$ConnectorCertStorePath = 'Cert:\LocalMachine\PrintProxyStore'
$ConnectorAppDataPath = Join-Path $env:ProgramData 'Microsoft\UniversalPrintConnector'
$ConnectorServiceNames = @('Print Connector service', 'PrintConnectorSvc', 'PrintConnectorUpdaterSvc')

# Values the connector writes to a print queue's CloudData key when the printer is registered
$RegistrationValueNames = @('CloudDeviceId', 'device_id', 'connector_id', 'certificate_thumbprint')

function Get-ExceptionDetails {
    Param(
        [System.Exception] $Exception,
        [int] $Depth = 0
    )

    if ($null -eq $Exception -or $Depth -gt 5) {
        return
    }

    ('  ' * $Depth) + "$($Exception.GetType().FullName): $($Exception.Message)"

    if ($Exception -is [System.AggregateException]) {
        $innerExceptions = $Exception.InnerExceptions
    }
    else {
        $innerExceptions = @($Exception.InnerException)
    }

    foreach ($innerException in $innerExceptions) {
        Get-ExceptionDetails -Exception $innerException -Depth ($Depth + 1)
    }
}

function Format-ErrorDetails {
    Param(
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    return (Get-ExceptionDetails -Exception $ErrorRecord.Exception) -join [Environment]::NewLine
}

function Test-NotFoundError {
    Param(
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $errorRecords = @($ErrorRecord)
    if ($ErrorRecord.Exception -is [System.Management.Automation.ActionPreferenceStopException]) {
        $errorRecords += $ErrorRecord.Exception.ErrorRecord
    }

    return [bool]($errorRecords | Where-Object {
        $_ -and $_.CategoryInfo.Category -eq [System.Management.Automation.ErrorCategory]::ObjectNotFound
    })
}

function Get-ConnectorService {
    Get-Service -ErrorAction SilentlyContinue | Where-Object {
        ($ConnectorServiceNames -contains $_.Name) -or ($ConnectorServiceNames -contains $_.DisplayName)
    }
}

function Get-PrintQueueCloudData {
    Param(
        [string] $ConnectorId
    )

    foreach ($queueKey in @(Get-ChildItem -LiteralPath $PrintersRegistryPath -ErrorAction Stop)) {
        # GetSubKeyNames throws if the print queue can't be read, instead of silently skipping it
        if ($queueKey.GetSubKeyNames() -notcontains 'CloudData') {
            continue
        }

        # A CloudData key without values produces no output, while a read failure throws
        $cloudDataPath = "$($queueKey.PSPath)\CloudData"
        $cloudData = Get-ItemProperty -LiteralPath $cloudDataPath -ErrorAction Stop
        $queue = [pscustomobject]@{
            QueueName             = $queueKey.PSChildName
            CloudDataPath         = $cloudDataPath
            CloudDeviceId         = [string]$cloudData.CloudDeviceId
            ConnectorId           = [string]$cloudData.connector_id
            DeviceId              = [string]$cloudData.device_id
            CertificateThumbprint = [string]$cloudData.certificate_thumbprint
            Owner                 = $null
        }

        $registrationValues = @($RegistrationValueNames | Where-Object { -not [string]::IsNullOrEmpty([string]$cloudData.$_) })

        if ($registrationValues.Count -eq 0) {
            # The connector also stores data (e.g. ippSupport) for print queues that were never registered
            $queue.Owner = 'NotRegistered'
        }
        elseif ($ConnectorId -and
                (($queue.ConnectorId -eq $ConnectorId) -or
                 $queue.DeviceId.StartsWith("$ConnectorId.", [System.StringComparison]::OrdinalIgnoreCase))) {
            $queue.Owner = 'ThisConnector'
        }
        else {
            $queue.Owner = 'OtherConnector'
        }

        $queue
    }
}

function CleanupConnector {
    Param(
        [Parameter(Mandatory=$true)]
        [string] $ConnectorName,

        [switch] $LocalCleanupOnly
    )

    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $psISE) {
        Write-Error "This script must be run in Windows PowerShell console only (not ISE or Core)."
        exit 1
    }

    Write-Host "Checking for elevated permissions..."
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        throw "Insufficient permissions to run this script. Open the PowerShell console as an administrator and run this script again."
    }

    # Ensure that the connector name provided is same as the connector installed on this machine
    $localConnector = Get-ItemProperty -LiteralPath $ConnectorRegistryPath -ErrorAction SilentlyContinue
    if (-not $localConnector) {
        throw "Connector data wasn't found in the registry ($ConnectorRegistryPath). You must run this script on the same machine as the connector that is to be cleaned up."
    }

    if ($localConnector.Name -ne $ConnectorName) {
        throw "The locally installed connector '$($localConnector.Name)' does not match the name provided to this script '$ConnectorName'. You must run this script on the same machine as the connector that is to be cleaned up."
    }

    $connectorId = [string]$localConnector.CloudDeviceId
    if ([string]::IsNullOrEmpty($connectorId)) {
        Write-Warning "The local connector data doesn't contain a connector ID, so the connector was likely never registered. Universal Print cleanup will be skipped."
        $LocalCleanupOnly = $true
    }

    Write-Host "Finding local print queues with Universal Print data..."
    try {
        $printQueues = @(Get-PrintQueueCloudData -ConnectorId $connectorId)
    }
    catch {
        throw "Reading the local print queues failed. No changes have been made.`n$(Format-ErrorDetails $_)"
    }

    $queuesToClean = @($printQueues | Where-Object { $_.Owner -ne 'OtherConnector' })
    $queuesToKeep = @($printQueues | Where-Object { $_.Owner -eq 'OtherConnector' })
    $connectorQueues = @($printQueues | Where-Object { $_.Owner -eq 'ThisConnector' })

    # Get everything needed from Universal Print before making any changes
    $cloudConnector = $null
    $cloudPrinters = @()

    if (-not $LocalCleanupOnly) {
        if (-not (Get-Command -Name 'Connect-UPService' -ErrorAction SilentlyContinue)) {
            throw "The UniversalPrintManagement module is required to clean up Universal Print. Install it by running Install-Module ""UniversalPrintManagement"", or run this script with -LocalCleanupOnly and unregister the printers and connector from the Azure portal."
        }

        Write-Host "Signing in to Universal Print..."
        try {
            Connect-UPService -ErrorAction Stop | Out-Null
        }
        catch {
            throw "Signing in to Universal Print failed. No changes have been made.`n$(Format-ErrorDetails $_)`nResolve the sign-in error and run this script again, or run it with -LocalCleanupOnly and unregister the printers and connector from the Azure portal."
        }

        Write-Host "Getting connector $connectorId from Universal Print..."
        try {
            $cloudConnector = @((Get-UPConnector -ConnectorId $connectorId -ErrorAction Stop).Results) | Select-Object -First 1
        }
        catch {
            if (-not (Test-NotFoundError $_)) {
                throw "Getting the connector from Universal Print failed. No changes have been made.`n$(Format-ErrorDetails $_)"
            }

            Write-Warning "Connector $connectorId wasn't found in Universal Print. It might have already been unregistered, so its unregistration will be skipped."
        }

        Write-Host "Getting the printers registered with this connector..."
        $printersById = @{}
        try {
            $continuationToken = $null
            do {
                $getPrinterParameters = @{ IncludeConnectorDetails = $true; ErrorAction = 'Stop' }
                if ($continuationToken) {
                    $getPrinterParameters['ContinuationToken'] = $continuationToken
                }

                $response = Get-UPPrinter @getPrinterParameters
                foreach ($printer in @($response.Results)) {
                    if ($printer -and (@($printer.Connectors | ForEach-Object { $_.Id }) -contains $connectorId)) {
                        $printersById[$printer.Id] = $printer
                    }
                }

                $continuationToken = $response.ContinuationToken
            }
            while (-not [string]::IsNullOrEmpty($continuationToken))
        }
        catch {
            throw "Getting the printers from Universal Print failed. No changes have been made.`n$(Format-ErrorDetails $_)"
        }

        # Printers registered from this machine might no longer be linked to the connector in Universal Print
        foreach ($queue in $connectorQueues) {
            $printerId = $queue.CloudDeviceId
            if ([string]::IsNullOrEmpty($printerId) -or $printersById.ContainsKey($printerId)) {
                continue
            }

            try {
                $printer = @((Get-UPPrinter -PrinterId $printerId -ErrorAction Stop).Results) | Select-Object -First 1
            }
            catch {
                if (-not (Test-NotFoundError $_)) {
                    throw "Getting printer $printerId from Universal Print failed. No changes have been made.`n$(Format-ErrorDetails $_)"
                }

                Write-Host "Printer $printerId (print queue '$($queue.QueueName)') is no longer registered in Universal Print. Only its local data will be removed."
                continue
            }

            if (-not $printer) {
                continue
            }

            $printerConnectorIds = @($printer.Connectors | ForEach-Object { $_.Id } | Where-Object { $_ })
            if ($printerConnectorIds.Count -gt 0 -and $printerConnectorIds -notcontains $connectorId) {
                Write-Warning "Printer '$($printer.DisplayName)' ($printerId) is registered with a different connector ($($printerConnectorIds -join ', ')), so it won't be unregistered."
                continue
            }

            $printersById[$printer.Id] = $printer
        }

        $cloudPrinters = @($printersById.Values)
    }

    # Show what will be cleaned up and ask for confirmation
    Write-Host ""
    Write-Host "Cleanup plan for connector '$ConnectorName' ($connectorId):"
    if ($LocalCleanupOnly) {
        Write-Host "  Universal Print: skipped. Unregister any remaining printers and the connector from the Azure portal."
    }
    else {
        Write-Host "  Printers to unshare and unregister in Universal Print: $($cloudPrinters.Count)"
        foreach ($printer in $cloudPrinters) {
            Write-Host "    - $($printer.DisplayName) ($($printer.Id)), shares: $(@($printer.Shares | Where-Object { $_ }).Count)"
        }

        if ($cloudConnector) {
            Write-Host "  Connector to unregister in Universal Print: $connectorId"
        }
        else {
            Write-Host "  Connector unregistration: skipped (not found in Universal Print)"
        }
    }

    Write-Host "  Local print queues to remove Universal Print data (CloudData) from: $($queuesToClean.Count)"
    foreach ($queue in $queuesToClean) {
        Write-Host "    - $($queue.QueueName)"
    }

    Write-Host "  Connector certificates ($ConnectorCertStorePath), registry data ($UniversalPrintRegistryPath) and application data ($ConnectorAppDataPath)"
    Write-Host "  The local print queues themselves won't be deleted."
    Write-Host ""

    if ($queuesToKeep.Count -gt 0) {
        Write-Warning "These print queues have Universal Print registration data that doesn't belong to connector $connectorId and will be left unchanged. Review them manually: $(($queuesToKeep | ForEach-Object { $_.QueueName }) -join ', ')"
    }

    # Warn the user; these actions are not recoverable
    Write-Warning "This script will make the changes listed above. The actions are not recoverable." -WarningAction Inquire

    # Stop services
    foreach ($service in @(Get-ConnectorService)) {
        if ($service.Status -ne 'Stopped') {
            Write-Host "Stopping $($service.DisplayName)..."
            Stop-Service -InputObject $service -Force -ErrorAction Stop
        }
    }

    $failures = @()

    if (-not $LocalCleanupOnly) {
        foreach ($printer in $cloudPrinters) {
            foreach ($share in @($printer.Shares | Where-Object { $_ })) {
                Write-Host "Unsharing $($share.DisplayName) ($($share.Id))..."
                try {
                    Remove-UPPrinterShare -ShareId $share.Id -Confirm:$false -ErrorAction Stop | Out-Null
                }
                catch {
                    if (-not (Test-NotFoundError $_)) {
                        $failures += "Unsharing $($share.Id) failed: $(Format-ErrorDetails $_)"
                    }
                }
            }

            Write-Host "Unregistering printer $($printer.DisplayName) ($($printer.Id))..."
            try {
                Remove-UPPrinter -PrinterId $printer.Id -Confirm:$false -ErrorAction Stop | Out-Null
            }
            catch {
                if (-not (Test-NotFoundError $_)) {
                    $failures += "Unregistering printer $($printer.Id) failed: $(Format-ErrorDetails $_)"
                }
            }
        }

        if ($cloudConnector) {
            Write-Host "Unregistering the connector..."
            try {
                Remove-UPConnector -ConnectorId $connectorId -Confirm:$false -ErrorAction Stop | Out-Null
            }
            catch {
                if (-not (Test-NotFoundError $_)) {
                    $failures += "Unregistering connector $connectorId failed: $(Format-ErrorDetails $_)"
                }
            }
        }

        if ($failures.Count -gt 0) {
            Write-Warning "Some Universal Print operations failed:`n$($failures -join "`n")"
            Write-Warning "If you continue, the local data will still be removed, and any printers or connector that are still registered must be unregistered from the Azure portal." -WarningAction Inquire
        }
    }

    $failedQueues = @()
    foreach ($queue in $queuesToClean) {
        Write-Host "Deleting the Universal Print data of print queue '$($queue.QueueName)'..."
        try {
            Remove-Item -LiteralPath $queue.CloudDataPath -Recurse -Force -ErrorAction Stop
        }
        catch {
            $failedQueues += $queue
            $failures += "Deleting $($queue.CloudDataPath) failed: $(Format-ErrorDetails $_)"
        }
    }

    if (Test-Path -LiteralPath $ConnectorCertStorePath) {
        # Keep the certificates of registrations that remain on this machine
        $thumbprintsToKeep = @(@($queuesToKeep) + @($failedQueues) | ForEach-Object { $_.CertificateThumbprint } | Where-Object { $_ })
        try {
            $certificates = @(Get-ChildItem -LiteralPath $ConnectorCertStorePath -ErrorAction Stop | Where-Object { $thumbprintsToKeep -notcontains $_.Thumbprint })
        }
        catch {
            $certificates = @()
            $failures += "Reading the certificates in $ConnectorCertStorePath failed: $(Format-ErrorDetails $_)"
        }

        Write-Host "Deleting $($certificates.Count) local printer/connector certificate(s)..."
        foreach ($certificate in $certificates) {
            try {
                Remove-Item -LiteralPath $certificate.PSPath -Force -ErrorAction Stop
            }
            catch {
                $failures += "Deleting certificate $($certificate.Thumbprint) failed: $(Format-ErrorDetails $_)"
            }
        }
    }

    if ($failedQueues.Count -gt 0) {
        # The connector ID is needed to run this script again and finish cleaning up these print queues
        $failures += "The local connector registration data ($UniversalPrintRegistryPath) was kept so this script can be run again to finish cleaning up the print queues."
    }
    elseif (Test-Path -LiteralPath $UniversalPrintRegistryPath) {
        Write-Host "Deleting the local connector registration data..."
        try {
            $registryKeys = @(Get-ChildItem -LiteralPath $UniversalPrintRegistryPath -ErrorAction Stop)
        }
        catch {
            $registryKeys = @()
            $failures += "Reading $UniversalPrintRegistryPath failed: $(Format-ErrorDetails $_)"
        }

        foreach ($registryKey in $registryKeys) {
            try {
                Remove-Item -LiteralPath $registryKey.PSPath -Recurse -Force -ErrorAction Stop
            }
            catch {
                $failures += "Deleting $($registryKey.Name) failed: $(Format-ErrorDetails $_)"
            }
        }
    }

    # Manually uninstall the Connector application
    if (@(Get-ConnectorService).Count -gt 0) {
        Read-Host "Please uninstall the connector software from Settings -> Apps or Start -> Run -> appwiz.cpl. Once the connector is uninstalled, press Enter to continue" | Out-Null
    }

    if (@(Get-ConnectorService).Count -gt 0) {
        $failures += "The connector software is still installed, so its application data ($ConnectorAppDataPath) wasn't deleted. Uninstall the connector and then delete the contents of that folder."
    }
    elseif (Test-Path -LiteralPath $ConnectorAppDataPath) {
        Write-Host "Deleting the connector's application data..."
        try {
            $appDataItems = @(Get-ChildItem -LiteralPath $ConnectorAppDataPath -Force -ErrorAction Stop)
        }
        catch {
            $appDataItems = @()
            $failures += "Reading $ConnectorAppDataPath failed: $(Format-ErrorDetails $_)"
        }

        foreach ($item in $appDataItems) {
            try {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            }
            catch {
                $failures += "Deleting $($item.FullName) failed: $(Format-ErrorDetails $_)"
            }
        }
    }

    Write-Host ""
    if ($failures.Count -gt 0) {
        Write-Warning "The cleanup didn't fully complete. Resolve the following issues and run this script again if needed:`n$($failures -join "`n")"
    }
    else {
        Write-Host "The cleanup finished successfully."
    }

    Write-Host "To use a connector on this machine again, install and register the connector, and then register and share the printers again."
}

## Invoke the main method
CleanupConnector -ConnectorName $ConnectorName -LocalCleanupOnly:$LocalCleanupOnly
