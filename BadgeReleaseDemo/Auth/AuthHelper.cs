// <copyright file="AuthHelper.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

using System.IdentityModel.Tokens.Jwt;
using System.Security.Cryptography;
using System.Text.Json;
using BadgeReleaseDemo.GraphApi;
using BadgeReleaseDemo.Helpers;
using Microsoft.Identity.Client;
using Microsoft.IdentityModel.Tokens;
using Org.BouncyCastle.Crypto;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Security;

namespace BadgeReleaseDemo.Auth;

/// <summary>
/// Handles authentication for both user (Printer Admin) and printer device flows.
/// Printer certificate and keys are kept in memory only.
/// </summary>
public class AuthHelper
{
    private readonly string appId;
    private readonly string tenantId;
    private readonly string graphBaseUrl;
    private IPublicClientApplication? publicClient;
    private AuthenticationResult? userAuthResult;
    private AuthenticationResult? graphAuthResult;

    // Printer identity (in memory only)
    private PrinterRegistrationResult? registrationResult;
    private AsymmetricCipherKeyPair? printerKeyPair;
    private string? printerToken;

    public string UserUpn => userAuthResult?.Account?.Username ?? "unknown";

    public string UserAccessToken => userAuthResult?.AccessToken ?? throw new InvalidOperationException("User not signed in");

    public string PrinterToken => printerToken ?? throw new InvalidOperationException("Printer token not acquired");

    public AuthHelper(string appId, string tenantId, string graphBaseUrl)
    {
        this.appId = appId;
        this.tenantId = tenantId;
        this.graphBaseUrl = graphBaseUrl;
    }

    /// <summary>
    /// Signs in the user using interactive browser-based authentication.
    /// </summary>
    public async Task<string> SignInUserAsync()
    {
        var builder = PublicClientApplicationBuilder
            .Create(appId)
            .WithRedirectUri("http://localhost");

        if (!string.IsNullOrEmpty(tenantId))
        {
            builder = builder.WithAuthority($"https://login.microsoftonline.com/{tenantId}");
        }

        publicClient = builder.Build();

        var scopes = new[] { "https://print.print.microsoft.com/.default" };

        userAuthResult = await publicClient.AcquireTokenInteractive(scopes)
            .WithPrompt(Prompt.SelectAccount)
            .ExecuteAsync();

        return UserUpn;
    }

    /// <summary>
    /// Gets a fresh user access token, refreshing if needed.
    /// </summary>
    public async Task<string> GetUserTokenAsync()
    {
        if (publicClient == null || userAuthResult == null)
        {
            throw new InvalidOperationException("User not signed in. Call SignInUserAsync first.");
        }

        try
        {
            var accounts = await publicClient.GetAccountsAsync();
            var scopes = new[] { "https://print.print.microsoft.com/.default" };
            userAuthResult = await publicClient.AcquireTokenSilent(scopes, accounts.FirstOrDefault())
                .ExecuteAsync();
        }
        catch (MsalUiRequiredException)
        {
            var scopes = new[] { "https://print.print.microsoft.com/.default" };
            userAuthResult = await publicClient.AcquireTokenInteractive(scopes)
                .ExecuteAsync();
        }

        return UserAccessToken;
    }

    /// <summary>
    /// Gets a Microsoft Graph token for Graph API calls (sharing, badges, jobs).
    /// Uses silent acquisition if possible, otherwise prompts interactively.
    /// </summary>
    public async Task<string> GetGraphTokenAsync()
    {
        if (publicClient == null)
        {
            throw new InvalidOperationException("User not signed in. Call SignInUserAsync first.");
        }

        var scopes = new[] { "https://graph.microsoft.com/.default" };

        try
        {
            var accounts = await publicClient.GetAccountsAsync();
            graphAuthResult = await publicClient.AcquireTokenSilent(scopes, accounts.FirstOrDefault())
                .ExecuteAsync();
        }
        catch (MsalUiRequiredException)
        {
            graphAuthResult = await publicClient.AcquireTokenInteractive(scopes)
                .ExecuteAsync();
        }

        return graphAuthResult.AccessToken;
    }

    /// <summary>
    /// Stores the printer registration result and keypair for device token acquisition.
    /// Certificate and keys are kept in memory only — not saved to disk.
    /// </summary>
    public void SetPrinterCredentials(PrinterRegistrationResult result, AsymmetricCipherKeyPair keyPair)
    {
        registrationResult = result;
        printerKeyPair = keyPair;
    }

    /// <summary>
    /// Acquires a device token for the printer using the JWT-bearer flow:
    /// 1. POST grant_type=srv_challenge to get a nonce
    /// 2. Create a JWT signed with the printer's private key
    /// 3. POST grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer with the JWT
    /// </summary>
    public async Task<string> GetPrinterTokenAsync()
    {
        if (registrationResult == null || printerKeyPair == null)
        {
            throw new InvalidOperationException("Printer credentials not set. Register printer first.");
        }

        using var httpClient = new HttpClient();
        var tokenUrl = registrationResult.DeviceTokenUrl;

        // Step 1: Request a nonce (srv_challenge)
        var challengeBody = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "srv_challenge",
            ["windows_api_version"] = "2.0",
        });

        var challengeResp = await httpClient.PostAsync(tokenUrl, challengeBody);
        var challengeContent = await challengeResp.Content.ReadAsStringAsync();

        if (!challengeResp.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Nonce request failed: {challengeResp.StatusCode} - {challengeContent}");
        }

        var challengeDoc = JsonSerializer.Deserialize<JsonElement>(challengeContent);
        var nonce = challengeDoc.GetProperty("Nonce").GetString()
            ?? throw new InvalidOperationException("No Nonce in srv_challenge response.");

        // Step 2: Create JWT signed with printer's private key
        var jwt = CreateDeviceJwt(nonce);

        // Step 3: Exchange JWT for access token
        var tokenBody = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "urn:ietf:params:oauth:grant-type:jwt-bearer",
            ["request"] = jwt,
        });

        var tokenResp = await httpClient.PostAsync(tokenUrl, tokenBody);
        var tokenContent = await tokenResp.Content.ReadAsStringAsync();

        if (!tokenResp.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Device token request failed: {tokenResp.StatusCode} - {tokenContent}");
        }

        var tokenDoc = JsonSerializer.Deserialize<JsonElement>(tokenContent);
        printerToken = tokenDoc.GetProperty("access_token").GetString()
            ?? throw new InvalidOperationException("No access_token in device token response.");

        return printerToken;
    }

    /// <summary>
    /// Refreshes the printer device token if needed.
    /// </summary>
    public async Task<string> RefreshPrinterTokenAsync()
    {
        return await GetPrinterTokenAsync();
    }

    /// <summary>
    /// Creates a JWT signed with the printer's private key for the device token flow.
    /// </summary>
    private string CreateDeviceJwt(string nonce)
    {
        var privateKeyParams = (RsaPrivateCrtKeyParameters)printerKeyPair!.Private;
        var rsaParams = DotNetUtilities.ToRSAParameters(privateKeyParams);
        var securityKey = new RsaSecurityKey(rsaParams);
        var signingCredentials = new SigningCredentials(securityKey, SecurityAlgorithms.RsaSha256);

        // x5c must be the base64 DER of the public cert (no PEM headers)
        var certBase64 = registrationResult!.CertificatePem
            .Replace("-----BEGIN CERTIFICATE-----", string.Empty)
            .Replace("-----END CERTIFICATE-----", string.Empty)
            .Replace("\r", string.Empty)
            .Replace("\n", string.Empty)
            .Trim();

        var header = new JwtHeader(signingCredentials)
        {
            { "x5c", new[] { certBase64 } },
        };

        // Use the app's client_id and the standard native client redirect URI
        var clientId = string.IsNullOrEmpty(registrationResult!.PrinterClientId)
            ? appId
            : registrationResult.PrinterClientId;
        var redirectUri = string.IsNullOrEmpty(registrationResult.PrinterRedirectUri)
            ? "https://login.microsoftonline.com/common/oauth2/nativeclient"
            : registrationResult.PrinterRedirectUri;

        var claims = new[]
        {
            new System.Security.Claims.Claim("request_nonce", nonce),
            new System.Security.Claims.Claim("grant_type", "device_token"),
            new System.Security.Claims.Claim("resource", registrationResult.PrintServiceResourceId),
            new System.Security.Claims.Claim("client_id", clientId),
            new System.Security.Claims.Claim("redirect_uri", redirectUri),
            new System.Security.Claims.Claim("iss", registrationResult.PrinterId),
        };

        var payload = new JwtPayload(claims);
        var jwt = new JwtSecurityToken(header, payload);
        var handler = new JwtSecurityTokenHandler();
        return handler.WriteToken(jwt);
    }
}
