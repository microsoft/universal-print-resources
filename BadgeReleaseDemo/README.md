# Badge Release Demo

A console application that demonstrates the full [Universal Print](https://learn.microsoft.com/universal-print/) badge release lifecycle and provides focused commands for managing badge collections and mappings.

> **⚠️ IMPORTANT DISCLAIMER:** This demo is provided for **educational purposes only and must not be used as is**. It is intended as a reference to help you build your own scripts and applications. Note that it registers real printers and shares against your tenant; the demo cleans these resources up at the end, but you are responsible for verifying nothing is left behind.

## What Is Badge Release?

Secure Release lets users send print jobs to a cloud queue and release them only after authenticating at the printer. This prevents uncollected printouts and ensures only the intended recipient picks up their documents. Badge Release is a form of Secure Release that is typically done by tapping an NFC badge or RFID card.

Typically, Badge Release requires third-party storage of the mappings from users' badge IDs to their identities. The printer looks up the badge ID in this third-party storage, then uses the user's identity to fetch their jobs. With Universal Print's Badge Management APIs, badge-to-user mappings are managed and stored within the Universal Print service. The printer calls Universal Print to resolve a badge ID to a user identity, then fetches that user's queued jobs.

> **⚠️ Private Preview:** The Badge Release feature is currently in **Private Preview** and is only enabled for specific tenants. If you are an OEM interested in joining the Private Preview, please reach out to the Universal Print team or [Microsoft Support](https://support.microsoft.com).

## What This Demo Does

The app walks through the complete lifecycle interactively:

| Step | What happens | APIs used |
|------|-------------|-----------|
| 1. **Sign in** | Authenticate as a Printer Administrator | MSAL interactive auth |
| 2. **Register printer** | Create a virtual printer with an in-memory certificate | `POST register.print.microsoft.com/api/v1.0/register` |
| 3. **Share printer** | Make the printer available to all users, holding jobs for secure release (`holdJobsForSecureRelease = true`) | `POST graph.microsoft.com/v1.0/print/shares` |
| 4. **Create badge collection** | Provision a badge collection for the tenant (idempotent) | `POST graph.print.microsoft.com/v1.0/print/badgeCollections` |
| 5. **Add badge** | Map a user-provided badge ID to the signed-in user | `POST graph.print.microsoft.com/v1.0/print/badgeCollections/{id}/badges` |
| 6. **Submit print job** | Upload a PDF and start a print job on the shared printer | Graph Print Job APIs |
| 7. **Acquire printer token** | Obtain a device token for the printer via JWT-bearer flow | `POST {deviceTokenUrl}` |
| 8. **Resolve badge** | Simulate a badge tap — resolve the badge ID to a user via Universal Print | `POST print.print.microsoft.com/api/v2.0/badges/lookup` |
| 9. **Get-Jobs** | Find fetchable jobs for the resolved user (IPP) | IPP Get-Jobs |
| 10. **Fetch-Job** | Retrieve job metadata (IPP) | IPP Fetch-Job |
| 11. **Acknowledge-Job** | Confirm receipt of the job (IPP) | IPP Acknowledge-Job |
| 12. **Fetch-Document** | Download the print document (IPP) | IPP Fetch-Document |
| 13. **Complete job** | Mark the job as completed (IPP) | IPP Update-Job-Status |
| 14. **Clean up** | Delete badge, share, printer, and local files | Graph + Badge APIs |

## Prerequisites

- [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) or later
- An Entra ID (Azure AD) app registration — see [App Registration](#app-registration) below
- A user account with the **Printer Administrator** directory role
- A PDF file to print during the demo

## App Registration

Register an application in the [Azure portal](https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationsListBlade) (Entra ID → App registrations → New registration).

### Platform Configuration

Add a **Mobile and desktop applications** platform with redirect URI:

```
http://localhost
```

### Delegated Permissions (Microsoft Graph)

These permissions are consented by the user at sign-in:

| Permission | Used For |
|---|---|
| `PrinterShare.ReadWrite.All` | Creating and deleting printer shares |
| `Printer.FullControl.All` | Deleting the printer during cleanup |
| `PrintJob.ReadWrite.All` | Submitting print jobs and uploading documents |

### Delegated Permissions (Universal Print Service)

| Permission | Used For |
|---|---|
| `Printers.Create` | Registering a virtual printer via the registration service |
| `PrintBadges.ReadWrite` | Creating, updating, and deleting badges and badge collections |

### Application Permissions (Universal Print Service)

These permissions are granted to the app itself (not delegated) and appear as `roles` in the printer's device token. **Admin consent is required** — a Global Administrator or Privileged Role Administrator must grant these.

| Permission | Used For |
|---|---|
| `Printers.Read` | IPP Get-Jobs (required alongside PrintJob scopes) |
| `PrintJob.Read` | Reading fetchable jobs from the printer |
| `PrintJob.ReadWriteBasic` | Fetch-Job, Acknowledge-Job, Fetch-Document |
| `PrintBadges.Read` | Resolving badge IDs to users via the Badges API |

> **Note:** `PrintBadges.Read` is specifically required for the badge resolution step. Without it, the printer will receive a `403 Forbidden` when calling the Badge API. See [Badge API documentation](https://learn.microsoft.com/universal-print/fundamentals/universal-print-badge-release) for details.

## Configuration

Build the app, then edit the generated `appsettings.json` beside the executable
(for example, `bin\Debug\net8.0\appsettings.json`):

```json
{
  "AppId": "YOUR_APP_ID_HERE",
  "Tenant": "YOUR_TENANT_HERE"
}
```

| Setting | Description | Example |
|---------|-------------|---------|
| `AppId` | Your Entra ID app registration client ID (GUID) | `a1b2c3d4-e5f6-7890-abcd-ef1234567890` |
| `Tenant` | Your tenant domain or GUID | `contoso.onmicrosoft.com` or a tenant GUID |

Keep the checked-in `appsettings.json` placeholders unchanged so personal tenant
values are not accidentally committed to this public repository. The generated
configuration is normally preserved across subsequent builds. If the output
directory is deleted or cleaned, configure the newly generated file again.

The remaining settings point to commercial production Universal Print endpoints.
Badge API route versions are maintained by the demo in `badgeapisettings.json`; this
file is copied to the output directory on every build and normally should not be
user-configured.

### Government Cloud

Government cloud is not supported by this demo today. Badge Release APIs in this demo target commercial Universal Print endpoints only.

## Build & Run

1. Build the app:

```powershell
dotnet build
```

2. Update `bin\Debug\net8.0\appsettings.json` with your Entra ID **Tenant** and
   **AppId** (from the app registration above).
3. Run the full interactive demo without rebuilding:

```powershell
dotnet run --no-build
```

Running with no command is equivalent to `dotnet run -- demo`. The app walks through
each step interactively, prompting for a badge ID and PDF file path. At the end, all
created cloud resources (printer, share, badge) are automatically cleaned up.

Use `dotnet run -- --help` to display all available commands.

## Badge Management Commands

Badge management commands acquire the delegated Universal Print token through the
same interactive MSAL sign-in as the demo. You do not need to acquire or pass an
access token separately.

```powershell
# Collections
dotnet run -- badges collections list
dotnet run -- badges collections create
dotnet run -- badges collections delete --collection-id <collection-id>
dotnet run -- badges collections delete --collection-id <collection-id> --force

# Badge mappings
dotnet run -- badges mappings list --collection-id <collection-id>
dotnet run -- badges mappings get --collection-id <collection-id> --badge-id <badge-id>
dotnet run -- badges mappings create --collection-id <collection-id> --badge-id <badge-id> --upn <user-upn>
dotnet run -- badges mappings create --collection-id <collection-id> --badge-id <badge-id> --upn <user-upn> --user-id <user-id>
dotnet run -- badges mappings update --collection-id <collection-id> --badge-id <badge-id> --upn <new-upn>
dotnet run -- badges mappings update --collection-id <collection-id> --badge-id <badge-id> --upn <user-upn> --user-id <new-user-id>
dotnet run -- badges mappings delete --collection-id <collection-id> --badge-id <badge-id>
```

`--collection-id` may be omitted when the tenant has exactly one badge collection.
When zero or multiple collections exist, the command reports the available next step
instead of selecting a collection implicitly. Collection deletion prompts for
confirmation unless `--force` is specified.

Badge collections fit in one service response, so collection listing does not paginate.
Badge mapping listing is not implemented by the service yet. The CLI reports the
resulting `501 Not Implemented` response without treating it as an authentication or
connectivity failure.

Updating a mapping replaces its identity fields rather than merging omitted values.
`--upn` is therefore required when changing `--user-id`; provide the mapping's current
UPN when it is not changing.

CSV import is not currently included.

## Project Structure

```
BadgeReleaseDemo/
├── Program.cs                          # CLI root and full 14-step demo orchestration
├── BadgeManagementCommands.cs         # Badge collection and mapping commands
├── appsettings.json                    # App ID, tenant, and service endpoints
├── badgeapisettings.json               # App-owned V1 and V2 badge API routes
│
├── Auth/
│   └── AuthHelper.cs                   # MSAL interactive auth + JWT-bearer device token flow
│
├── GraphApi/
│   ├── PrinterRegistration.cs          # Printer registration via register.print.microsoft.com
│   ├── PrinterSharing.cs               # Share CRUD (with holdJobsForSecureRelease) + printer delete via Graph
│   ├── BadgeManagement.cs              # Badge collection + badge CRUD via graph.print.microsoft.com
│   └── PrintJobSubmission.cs           # Job creation, document upload, job start via Graph
│
├── IppOperations/
│   ├── MinimalIpp.cs                   # Minimal custom IPP serializer/parser for required operations
│   └── PrinterIppClient.cs             # IPP INFRA operations + Badge REST API call
│
├── Helpers/
│   ├── ConsoleHelper.cs                # Colored console output helpers
│   └── CryptoHelper.cs                 # RSA keypair + CSR generation (BouncyCastle)
│
└── Resources/
    └── SampleDocument.pdf              # Default test PDF (or supply your own)
```

## Authentication Flows

The demo uses three distinct token audiences:

| Token | Audience | How Acquired | Used For |
|-------|----------|-------------|----------|
| **User print token** | `print.print.microsoft.com` | MSAL interactive (delegated) | Printer registration, badge management |
| **User graph token** | `graph.microsoft.com` | MSAL interactive (delegated) | Sharing, job submission, enable badge release |
| **Printer device token** | Dynamic (from registration) | JWT-bearer flow with printer certificate | Badge resolution, all IPP operations |

### Printer Device Token Flow

The printer authenticates using a certificate-based JWT-bearer flow:

1. **`srv_challenge`** — POST to the device token URL to get a nonce
2. **Create JWT** — Sign a JWT with the printer's private key (includes nonce, resource, client_id)
3. **Exchange** — POST `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer` with the signed JWT
4. The returned access token contains the application permissions (`Printers.Read`, `PrintJob.Read`, etc.) as roles

## Badge API Reference

The default V2 Badge API is a REST endpoint on the Universal Print IPP Service. It
keeps the badge ID in the request body instead of the URL:

```
POST https://print.print.microsoft.com/api/v2.0/badges/lookup
Authorization: Bearer {printer-device-token}
```

**Request body:**
```json
{
  "badgeId": "123"
}
```

Run the demo with `demo --use-v1-badge-api` to use the legacy
`GET https://print.print.microsoft.com/api/v1.0/badges/{badgeId}` endpoint instead:

```powershell
dotnet run -- demo --use-v1-badge-api
```

**Success response (200 OK):**
```json
{
  "badgeId": "123",
  "userURI": "mailto:john@contoso.com",
  "userId": "a3f7b0aa-9f48-4f6f-a95f-0123456789ab"
}
```

The `userURI` (a `mailto:` URI) is then passed as the `requesting-user-uri` attribute in subsequent IPP operations (Get-Jobs, Fetch-Job, Fetch-Document) to retrieve that user's queued jobs.

**Error responses:**

| Status | Meaning |
|--------|---------|
| `400` | Missing or empty badge ID |
| `401` | Invalid or expired device token |
| `403` | Missing `PrintBadges.Read` permission, or the Badge Release feature is not enabled for your tenant |
| `404` | Badge ID not found |
| `500` | Server error |

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `403 Forbidden` on badge resolution | Missing `PrintBadges.Read` app permission, or tenant not enrolled in the Badge Release preview | Grant the permission and admin-consent it in the Azure portal. If the feature is not enabled, see the note below. |
| `401 Unauthorized` on IPP operations | Printer device token expired | The demo acquires a fresh token; if it persists, re-run |
| `404 Badge collection not found` when adding a badge after deleting and recreating a collection | Badge collection deletion and recreation can take time to settle across the service, even after the new collection reports that provisioning succeeded | Wait a few minutes, then retry adding the badge. Avoid repeatedly deleting and recreating collections during normal testing. |
| No fetchable jobs found | Job not yet processed by the service | Wait a few seconds and retry; in production, printers poll |
| `ServerErrorInternalError` on Update-Job-Status | Job may already be in a terminal state | Check the correlation headers in the console output and investigate server-side |
| Cleanup fails to delete PDF | File locked by PDF viewer (e.g., Adobe) | Close the viewer, then delete manually |

## License

Copyright (c) Microsoft Corporation. All rights reserved.
