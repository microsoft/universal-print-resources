# The script generates a list of the form:
#   cloudDeviceId1 => ipAddress1
#   cloudDeviceId2 => ipAddress2
#   cloudDeviceId3 => ipAddress3
#   ...
# This can be passed into "Sample reinstall printers as IPP script.ps1" to reinstall the printers in a Connector using IPP

Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers' | ForEach-Object {
    $CloudDataKey = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Print\Printers\$($_.PSChildName)\CloudData"
    $ClouData = Get-ItemProperty -LiteralPath $CloudDataKey -ErrorAction SilentlyContinue
    if ($ClouData.CloudDeviceId -and $ClouData.ipAddress)
    {
        Write-Host $ClouData.CloudDeviceId " => " $ClouData.ipAddress
    }
}