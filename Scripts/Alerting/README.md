# Universal Print — Logs and Alerts Scripts (Alerting)

PowerShell **scripts** that provision and tear down the Azure Monitor resources required by the
**Universal Print Logs and Alerts** feature. Use these when you prefer an imperative, step-by-step
setup (with retry logic and detailed progress output) over the declarative Bicep/ARM templates.

> 📘 **Start here:** For end-to-end, step-by-step guidance (permissions, finding the service
> principal Object ID, portal configuration, and sample alert queries), see the
> **Get-Started guide**: [Set up Logs and Alerts for Universal Print](https://learn.microsoft.com/universal-print/reference/logs-and-alerting/set-up-logs-and-alerting).

> ⚠️ **Required Permissions (Azure RBAC)** — on the target resource group, **either**:
>
> - **Owner**, _or_
> - **Contributor + User Access Administrator**
>
> User Access Administrator (or Owner) is required to assign the RBAC roles to the Universal Print
> service principal. If the resource group does not exist yet, hold the same role at the
> **subscription** scope to create it.

> **These scripts are Authenticode code-signed.** Download the signed copies from this repository
> before running them — using the signed versions ensures they have not been tampered with.

## What's in this folder

| File | What it does | How to use it |
|------|--------------|---------------|
| `Setup-AlertingInfrastructure.ps1` | Creates the Log Analytics workspace, the three custom tables, the Data Collection Rule (with built-in ingestion endpoint), and assigns the RBAC roles for the Universal Print service principal. | Run with the parameters shown in [Quick start](#quick-start). Idempotent — safe to re-run. |
| `Cleanup-AlertingInfrastructure.ps1` | Removes the alerting resources created by setup (optionally the resource group too). | Run when you want to tear everything down. |

> **Schema version:** 0.3.0 — kept in sync with the Bicep/ARM templates. All deployment methods
> (PowerShell, Bicep, ARM) create identical resources with the same table schemas.

## Resources created

- **Log Analytics Workspace** — stores the log data (creates a new workspace or reuses an existing one).
- **Custom Tables** — `UniversalPrintPrinterHealth_CL`, `UniversalPrintJob_CL`, and `UniversalPrintBillingSummary_CL`.
- **Data Collection Rule (DCR)** — routes logs to the workspace (`kind: Direct`, built-in ingestion endpoint).
- **RBAC Role Assignments** for the Universal Print service principal:
  - **Monitoring Metrics Publisher** on the DCR — ingest data.
  - **Monitoring Contributor** on the DCR — update streams, data flows, transforms.
  - **Log Analytics Contributor** on the workspace — manage custom table schemas.

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│ Universal Print │─────▶│ Data Collection │─────▶│  Log Analytics  │
│    Service      │      │   Rule (Direct) │      │   Workspace     │
└─────────────────┘      └─────────────────┘      └─────────────────┘
                                                         │
                                                         ▼
                                          ┌───────────────────────────────────┐
                                          │           Custom Tables           │
                                          │ - UniversalPrintPrinterHealth_CL  │
                                          │ - UniversalPrintJob_CL            │
                                          │ - UniversalPrintBillingSummary_CL │
                                          └───────────────────────────────────┘
```

## Prerequisites

1. **Azure PowerShell** — the `Az` module (the setup script installs it automatically if missing).
2. On the target resource group, **either** **Owner**, **or** **Contributor + User Access
   Administrator** (the latter is required to create the RBAC role assignments). If the resource
   group does not exist yet, hold the same role at the **subscription** scope to create it.
3. The Universal Print service principal **Object ID** (tenant-specific) — **optional**. If omitted,
   the setup script auto-resolves it via Microsoft Graph (requires the `Microsoft.Graph` module and
   `Application.Read.All`). Supplying it explicitly is recommended.

### Get the Universal Print service principal Object ID

> ⚠️ **The Object ID is tenant-specific.** Log into the correct tenant first — running this in the
> wrong tenant returns a different (invalid) value, which results in "Unknown" role assignments.

```powershell
# Step 1: Log into the correct tenant
Connect-AzAccount -TenantId <your-tenant-id>

# Step 2: Get the Object ID (unique per tenant) for App ID da9b70f6-5323-4ce6-ae5c-88dcc5082966
(Get-AzADServicePrincipal -ApplicationId da9b70f6-5323-4ce6-ae5c-88dcc5082966).Id
```

See [Get-Started guide](https://learn.microsoft.com/universal-print/reference/logs-and-alerting/set-up-logs-and-alerting) Step 2 for portal screenshots and CLI alternatives.

## Quick start

### 1. Set up infrastructure and permissions

```powershell
.\Setup-AlertingInfrastructure.ps1 `
    -TenantId "your-tenant-id" `
    -LogAnalyticsSubscription "your-subscription-id" `
    -LogAnalyticsLocation "westus2" `
    -LogAnalyticsResourceGroup "rg-universalprint-alerting" `
    -LogAnalyticsWorkspaceName "law-universalprint" `
    -UniversalPrintServicePrincipalObjectId "<sp-object-id>"  # Optional — auto-resolved via Graph if omitted
```

### 2. Clean up (when done)

```powershell
.\Cleanup-AlertingInfrastructure.ps1 `
    -TenantId "your-tenant-id" `
    -SubscriptionId "your-subscription-id" `
    -ResourceGroupName "rg-universalprint-alerting" `
    -WorkspaceName "law-universalprint" `
    -DeleteResourceGroup  # Optional: also delete the resource group
```

## Parameters

### Setup

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `TenantId` | Yes | — | Microsoft Entra tenant ID. |
| `LogAnalyticsSubscription` | Yes | — | Subscription ID for the workspace. |
| `LogAnalyticsLocation` | Yes | — | Azure region (e.g., `westus2`). |
| `LogAnalyticsResourceGroup` | Yes | — | Resource group name (created if missing). |
| `LogAnalyticsWorkspaceName` | Yes | — | Log Analytics workspace name (created or reused). |
| `UniversalPrintServicePrincipalObjectId` | No | auto-resolved | UP service principal Object ID for RBAC; resolved via Graph if omitted. |
| `PrintJobRetentionInDays` | No | 30 | Interactive retention for the print job table (30–730 days). |
| `PrintJobTotalRetentionInDays` | No | 365 | Total retention including archive (≥ `PrintJobRetentionInDays`, 30–2556 days). |
| `AzureEnvironment` | No | `AzureCloud` | Sovereign cloud (see below). |

### Cleanup

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `TenantId` | Yes | — | Microsoft Entra tenant ID. |
| `SubscriptionId` | Yes | — | Subscription ID of the resources. |
| `ResourceGroupName` | Yes | — | Resource group holding the alerting resources. |
| `WorkspaceName` | Yes | — | Log Analytics workspace to remove. |
| `DeleteResourceGroup` | No | (off) | Also delete the resource group. |
| `AzureEnvironment` | No | `AzureCloud` | Sovereign cloud (see below). |

> Data retention is configurable for the print job table via `-PrintJobRetentionInDays` and
> `-PrintJobTotalRetentionInDays`; other tables use workspace defaults. To customize retention after
> deployment, see [Configure data retention](https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-configure).

## Script features

- **Fail-fast error handling** — scripts stop immediately on errors.
- **Retry logic** — exponential backoff for transient failures.
- **Idempotency** — safe to run multiple times.
- **Detailed output** — clear status messages and progress, including the resource names to select
  in the Universal Print admin center.

## Sovereign cloud support

Both scripts support the `-AzureEnvironment` parameter:

| Value | Clouds |
|-------|--------|
| `AzureCloud` (default) | Public, GCC |
| `AzureUSGovernment` | GCC High, DOD |
| `AzureChinaCloud` | China (21Vianet) |

```powershell
# Example: GCC High
.\Setup-AlertingInfrastructure.ps1 ... -AzureEnvironment AzureUSGovernment
.\Cleanup-AlertingInfrastructure.ps1 ... -AzureEnvironment AzureUSGovernment
```

## Post-deployment configuration

Open the **Logs and alerts** page from the Universal Print blade, choose **Configure & Enable**,
then select the deployed resources from the dropdowns using the names shown in the setup script
output (subscription, Log Analytics workspace, Data Collection Rule). Enable the log categories you
want: **Printer activity**, **Job activity**, **Billing event**.

The full walkthrough — including sample alert queries — is in the
[Get-Started guide](https://learn.microsoft.com/universal-print/reference/logs-and-alerting/set-up-logs-and-alerting).

## See Also

- [Bicep/ARM Templates (Alerting)](../../Templates/Alerting/README.md) — declarative deployment alternative.
- [Universal Print documentation](https://learn.microsoft.com/universal-print/)
