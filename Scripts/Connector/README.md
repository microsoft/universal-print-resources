# Universal Print Connector Scripts

This directory contains sample PowerShell scripts to help manage Universal Print Connectors and their associated printers. These scripts provide automation for common connector management tasks including backup, restore, registration, and maintenance operations.

## 🔧 Prerequisites

- **Windows PowerShell**: All scripts must be run in Windows PowerShell console (not PowerShell Core or ISE)
- **Administrator Privileges**: Most scripts require elevated permissions (`#Requires -RunAsAdministrator`)
- **Universal Print Connector**: Must be installed on the local machine
- **PowerShell Modules** (install as needed):
  ```powershell
  Install-Module "UniversalPrintManagement"
  Install-Module "Microsoft.Identity.Client"
  ```

## 📋 Script Overview

### Backup and Restore Operations

#### `Sample connector backup script.ps1`
Creates a comprehensive backup of the Universal Print Connector configuration and data.

**What it backs up:**
- Local printer configurations (using PrintBrm.exe)
- Universal Print certificates from PrintProxyStore
- Connector registry settings
- Cloud data registry entries for all printers
- Connector configuration JSON file
- Custom print ticket mappings

**Output:** Creates `C:\ConnectorBackup` folder with all backup files

**⚠️ Important:** This is not for creating redundant/parallel connectors - only for backup/restore scenarios.

#### `Sample connector restore script.ps1`
Restores a connector from a backup created by the backup script.

**Prerequisites:**
1. Copy the `C:\ConnectorBackup` folder to the target machine
2. Install the latest Universal Print Connector (but do not register it)

**What it restores:**
- All items from the backup (printers, certificates, registry, configurations)
- Starts the connector services after restoration

### Printer Management

#### `Sample register local printers with Universal Print script.ps1`
Automates the registration of local printers with Universal Print service.

**Features:**
- Enumerates all locally installed printers eligible for Universal Print
- Handles Azure AD authentication automatically
- Registers each printer with the Universal Print service
- Equivalent to using the Print Connector App GUI

**Requirements:**
- `Microsoft.Identity.Client` PowerShell module
- Connector must already be registered with Universal Print

#### `Sample list printers for reinstallation script.ps1`
Generates a mapping file of registered printers for reinstallation purposes.

**Output:** Creates `PrintersToMove.txt` with format:
```
cloudDeviceId1 => ipAddress1
cloudDeviceId2 => ipAddress2
```

**Use case:** Preparing data for printer migration using IPP

#### `Sample reinstall printers as IPP script.ps1`
Reinstalls Universal Print printers using IPP (Internet Printing Protocol) Directed Discovery.

**Parameters:**
- `FilePath`: Text file with printer mappings (from list script above)
- `Verify`: Whether to pause and verify capabilities before each swap (y/n)

**Process:**
1. Installs printers via IPP using their IP addresses
2. Registers new IPP printers with Universal Print
3. Swaps the printers under existing Universal Print shares
4. Generates cleanup and revert scripts

**Output Files:**
- `cleanup.ps1`: Script to unregister old UP printers
- `revert.ps1`: Script to swap back to non-IPP printers

### Maintenance and Troubleshooting

#### `Sample reset registered printer script.ps1`
Resets a specific printer that's having issues with Universal Print.

**Parameters:**
- `PrinterName`: Name of the printer to reset

**Use cases:**
- Printer showing incorrect status
- Print jobs failing or stuck
- Alternative to restarting the connector service

#### `Sample connector cleanup script.ps1`
Completely removes a connector and all its associated printers from Universal Print.

**Parameters:**
- `ConnectorName`: Name of the connector to clean up

**⚠️ CRITICAL WARNINGS:**
- **Actions are NOT recoverable**
- **Data removed is NOT recoverable**
- Unshares and unregisters ALL printers
- Deletes ALL certificates and local data
- Must be run on the same machine as the connector

**Process:**
1. Validates connector name matches local installation
2. Retrieves and unshares all printer shares
3. Unregisters all printers from Universal Print
4. Removes local registration data
5. Unregisters the connector itself
6. Deletes certificates and application data
7. Prompts for manual connector software uninstallation

## 🚀 Usage Examples

### Basic Connector Backup
```powershell
# Run as Administrator
.\Sample connector backup script.ps1
```

### Register All Local Printers
```powershell
# Ensure UniversalPrintManagement module is installed
.\Sample register local printers with Universal Print script.ps1
```

### Migrate Printers to IPP
```powershell
# Step 1: Generate printer list on old connector
.\Sample list printers for reinstallation script.ps1

# Step 2: Copy PrintersToMove.txt to new connector machine

# Step 3: Reinstall as IPP with verification prompts
.\Sample reinstall printers as IPP script.ps1 -FilePath "PrintersToMove.txt" -Verify "y"
```

### Reset a Problematic Printer
```powershell
.\Sample reset registered printer script.ps1 -PrinterName "MyPrinter"
```

### Complete Connector Cleanup
```powershell
.\Sample connector cleanup script.ps1 -ConnectorName "MyConnector"
```

## 📝 Important Notes

1. **Testing**: These are sample scripts - test thoroughly in non-production environments first
2. **Customization**: Adapt scripts to your specific environment and requirements
3. **Error Handling**: Check Event Viewer logs for detailed error information
4. **PowerShell Version**: Windows PowerShell Desktop edition only (not Core/ISE)
5. **Authentication**: Some scripts require interactive Azure AD sign-in
6. **Backup**: Always backup before making significant changes

## 🔍 Troubleshooting

### Common Issues
- **Module not found**: Install required PowerShell modules
- **Access denied**: Run PowerShell as Administrator
- **Connector not registered**: Register connector before running printer scripts
- **Authentication failures**: Ensure proper Azure AD permissions

### Event Logs
Check Windows Event Viewer for detailed information:
- **Application and Services Logs** → **Microsoft** → **Windows** → **PrintConnector**

## 📚 Additional Resources

- [Universal Print Documentation](https://docs.microsoft.com/universal-print/)
- [Universal Print Connector Download](https://aka.ms/UPConnector)
- [Universal Print PowerShell Module](https://docs.microsoft.com/powershell/module/universalprintmanagement/)