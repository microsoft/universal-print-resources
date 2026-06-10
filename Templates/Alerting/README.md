# Universal Print — Logs and Alerts Templates (Alerting)

Infrastructure-as-Code **templates** that provision the Azure Monitor resources required by the
**Universal Print Logs and Alerts** feature. Use these when you prefer a declarative, repeatable
deployment (Bicep or ARM) over the imperative PowerShell setup script.

> 📘 **Start here:** For end-to-end, step-by-step guidance (permissions, finding the service
> principal Object ID, portal configuration, and sample alert queries), see the
> **Get-Started guide**: [Set up Logs and Alerts for Universal Print](https://learn.microsoft.com/universal-print/reference/logs-and-alerting/set-up-logs-and-alerting).

## What's in this folder

| File | What it contains | How to use it |
|------|------------------|---------------|
| `main.bicep` | The Bicep template. Declares all resources: Log Analytics workspace (new or existing), the three custom tables, the Data Collection Rule (with built-in ingestion endpoint), and the RBAC role assignments for the Universal Print service principal. | Deploy with `az deployment group create --template-file main.bicep` (see [Deploy](#deploy)). |
| `main.bicepparam` | A Bicep parameter file with documented, ready-to-edit values. Fill in `universalPrintServicePrincipalObjectId` and adjust the workspace name / retention as needed. | Pass with `--parameters main.bicepparam` instead of supplying parameters inline. |
| `azuredeploy.json` | The ARM template, compiled from `main.bicep`. Functionally identical — use it if your toolchain is ARM-based or for **Deploy to Azure** portal flows. | Deploy with `az deployment group create --template-file azuredeploy.json`. |
| `metadata.json` | Azure Quickstart-style metadata (display name, description, services). Used by gallery/quickstart tooling; not required for a manual deployment. | No action needed — informational. |

> **Schema version:** 0.3.0 — kept in sync with the PowerShell setup script. All deployment
> methods (Bicep, ARM, PowerShell) create identical resources with the same table schemas.

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

1. **Azure CLI** with the Bicep extension installed.
2. On the target resource group, **either** **Owner**, **or** **Contributor + User Access
   Administrator** (the latter is required to create the RBAC role assignments). If the resource
   group does not exist yet, hold the same role at the **subscription** scope to create it.
3. The Universal Print service principal **Object ID** (tenant-specific).

### Get the Universal Print service principal Object ID

> ⚠️ **The Object ID is tenant-specific.** Log into the correct tenant first — running this in the
> wrong tenant returns a different (invalid) value, which results in "Unknown" role assignments.

```bash
# Step 1: Log into the correct tenant
az login --tenant <your-tenant-id>

# Step 2: Get the Object ID (unique per tenant)
az ad sp show --id da9b70f6-5323-4ce6-ae5c-88dcc5082966 --query id -o tsv
```

## Deploy

```bash
# Create the resource group (skip if it already exists)
az group create --name rg-universalprint-alerting --location westus2

# Option A — Bicep with inline parameters
az deployment group create \
  --resource-group rg-universalprint-alerting \
  --template-file main.bicep \
  --parameters logAnalyticsWorkspaceName=law-universalprint \
               universalPrintServicePrincipalObjectId=<object-id>

# Option B — Bicep with the parameter file (edit main.bicepparam first)
az deployment group create \
  --resource-group rg-universalprint-alerting \
  --template-file main.bicep \
  --parameters main.bicepparam

# Option C — ARM template
az deployment group create \
  --resource-group rg-universalprint-alerting \
  --template-file azuredeploy.json \
  --parameters logAnalyticsWorkspaceName=law-universalprint \
               universalPrintServicePrincipalObjectId=<object-id>
```

## Resource group

Every resource these templates create — the Log Analytics workspace, the custom tables, the
Data Collection Rule, and the RBAC role assignments — is deployed into the **single resource
group** you pass with `--resource-group`. The deployment is *resource-group-scoped*
(`az deployment group create`), so there is no per-resource resource-group parameter.

> **No separate DCR resource group (by design).** The PowerShell setup script exposes an
> `-AzDcrResourceGroup` parameter that can place the Data Collection Rule in a *different*
> resource group than the workspace. The templates intentionally omit this: keeping every
> resource in one resource group is what makes a resource-group-scoped deployment simple and
> repeatable. Splitting the DCR into another group would require a subscription-scoped
> deployment with nested modules — complexity the templates deliberately avoid. If you need the
> DCR in a separate resource group, use the PowerShell script instead.

The target resource group must exist before you deploy (or create it with
`az group create`, as shown in [Deploy](#deploy)). Its name is surfaced in the
`resourceGroupName` [output](#outputs) for use in the Universal Print Admin Portal dropdowns.

## Sovereign cloud support

The templates have **no cloud parameter** — the target Azure cloud is determined by your Azure
CLI context, not by the template. Set the cloud *before* you log in and deploy:

| Cloud | Set context with |
|-------|------------------|
| **Azure Public** (Commercial, GCC) | `az cloud set --name AzureCloud` *(default — no action needed)* |
| **Azure US Government** (GCC High, DoD) | `az cloud set --name AzureUSGovernment` |
| **Azure China** (21Vianet) | `az cloud set --name AzureChinaCloud` |

```bash
# Example: deploy into Azure US Government
az cloud set --name AzureUSGovernment
az login --tenant <your-tenant-id>
az deployment group create \
  --resource-group rg-universalprint-alerting \
  --template-file main.bicep \
  --parameters logAnalyticsWorkspaceName=law-universalprint \
               universalPrintServicePrincipalObjectId=<object-id>
```

> The PowerShell setup script selects the cloud with its `-AzureEnvironment` parameter instead.
> With the templates, the `az cloud set` context performs the equivalent selection.

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `logAnalyticsWorkspaceName` | string | *required* | Log Analytics workspace name (creates new or reuses existing). |
| `universalPrintServicePrincipalObjectId` | string | *required* | UP service principal Object ID for RBAC. |
| `dataCollectionRuleName` | string | `dcrup-{workspace}` | DCR name (3–30 chars, letters/numbers/hyphens). |
| `printJobRetentionInDays` | int | 30 | Interactive retention for the print job table / hot storage (30–730 days). |
| `printJobTotalRetentionInDays` | int | 365 | Total retention including archive (must be ≥ `printJobRetentionInDays`, 30–2556 days). |
| `tags` | object | `{purpose: 'Universal Print Alerting', deployedBy: 'Bicep'}` | Resource tags. |

## Outputs

After deployment, use these output values in the Universal Print Admin Portal dropdowns.

| Output | Description | Portal selection |
|--------|-------------|------------------|
| `subscriptionName` | Subscription display name | Subscription dropdown |
| `subscriptionId` | Subscription ID | Subscription dropdown (confirmation) |
| `resourceGroupName` | Resource group of the workspace and DCR | Locate the workspace/DCR in the dropdowns |
| `workspaceName` | Log Analytics workspace name | Log Analytics Workspace dropdown |
| `dcrName` | Data Collection Rule name | Data Collection Rule dropdown |
| `printerHealthTableName` | `UniversalPrintPrinterHealth_CL` | — (reference) |
| `printJobTableName` | `UniversalPrintJob_CL` | — (reference) |
| `billingSummaryTableName` | `UniversalPrintBillingSummary_CL` | — (reference) |

## Post-deployment configuration

Open the **Logs and alerts** page from the Universal Print blade, choose **Configure & Enable**,
then select the deployed resources from the dropdowns using the deployment output values above.
Enable the log categories you want: **Printer activity**, **Job activity**, **Billing event**.

The full walkthrough — including sample alert queries — is in the
[Get-Started guide](https://learn.microsoft.com/universal-print/reference/logs-and-alerting/set-up-logs-and-alerting).

## Cleanup

Bicep/ARM templates only **provision** resources — they have no native way to delete them.
Use the PowerShell cleanup script published in the
[`Scripts/`](https://github.com/microsoft/universal-print-resources/tree/main/Scripts) folder
(see the Get-Started guide for details). There is no cleanup template.

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `RoleAssignmentExists` | The role assignment already exists — safe to ignore (a previous deployment succeeded). |
| `AuthorizationFailed` | You need **User Access Administrator** to assign RBAC. Get the role, or deploy without role assignments and assign them manually later. |
| `RequestDisallowedByPolicy` | An Azure Policy with a `Deny` effect blocks workspace creation without required settings (e.g., CMK encryption, Private Link). Request a policy exemption or update the template to comply. |
| Logs not appearing | Wait 5–10 minutes (propagation), verify Universal Print is configured with the correct output values, and check the `DCRLogErrors` table for ingestion errors. |

## Resources

- [Universal Print documentation](https://learn.microsoft.com/universal-print/)
- [Azure Monitor Data Collection Rules](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview)
- [Set up Logs and Alerts for Universal Print (Get-Started)](https://learn.microsoft.com/universal-print/reference/logs-and-alerting/set-up-logs-and-alerting)
