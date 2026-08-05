# Badge Release Demo

An interactive console application that demonstrates the full [Universal Print](https://learn.microsoft.com/universal-print/) badge release lifecycle — from printer registration and badge setup to badge-swipe-triggered job release.

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
| 8. **Resolve badge** | Simulate a badge tap — resolve the badge ID to a user via Universal Print | `GET print.print.microsoft.com/api/v1.0/badges/{badgeId}` |
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

Edit `appsettings.json`:

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

The remaining settings point to commercial production Universal Print endpoints.

### Government Cloud

Government cloud is not supported by this demo today. Badge Release APIs in this demo target commercial Universal Print endpoints only.

## Build & Run

1. Update `appsettings.json` with your Entra ID **Tenant** and **AppId** (from the app registration above).
2. Build and run:

```powershell
dotnet build
dotnet run
```

The app will walk you through each step interactively, prompting for a badge ID and PDF file path. At the end, all created cloud resources (printer, share, badge) are automatically cleaned up.

## Project Structure

```
BadgeReleaseDemo/
├── Program.cs                          # Main orchestration — runs the 14-step flow
├── appsettings.json                    # App ID, tenant, and service endpoints
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

The Badge API is a REST endpoint on the Universal Print IPP Service:

```
GET https://print.print.microsoft.com/api/v1.0/badges/{badgeId}
Authorization: Bearer {printer-device-token}
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
| No fetchable jobs found | Job not yet processed by the service | Wait a few seconds and retry; in production, printers poll |
| `ServerErrorInternalError` on Update-Job-Status | Job may already be in a terminal state | Check the correlation headers in the console output and investigate server-side |
| Cleanup fails to delete PDF | File locked by PDF viewer (e.g., Adobe) | Close the viewer, then delete manually |

## License

Copyright (c) Microsoft Corporation. All rights reserved.
