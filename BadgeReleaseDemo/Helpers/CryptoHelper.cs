// <copyright file="CryptoHelper.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

using Org.BouncyCastle.Asn1.X509;
using Org.BouncyCastle.Crypto;
using Org.BouncyCastle.Crypto.Generators;
using Org.BouncyCastle.Crypto.Operators;
using Org.BouncyCastle.OpenSsl;
using Org.BouncyCastle.Pkcs;
using Org.BouncyCastle.Security;
using Org.BouncyCastle.X509;

namespace BadgeReleaseDemo.Helpers;

/// <summary>
/// Generates CSR and keypair for printer registration.
/// Certificate and keys are kept in memory only.
/// </summary>
public static class CryptoHelper
{
    private const int KeySize = 2048;

    public static AsymmetricCipherKeyPair GenerateKeyPair()
    {
        var generator = new RsaKeyPairGenerator();
        generator.Init(new KeyGenerationParameters(new SecureRandom(), KeySize));
        return generator.GenerateKeyPair();
    }

    public static string GenerateCsr(AsymmetricCipherKeyPair keyPair)
    {
        var subject = new X509Name("CN=Universal Print Badge Release Demo");
        var csr = new Pkcs10CertificationRequest(
            new Asn1SignatureFactory("SHA256WithRSA", keyPair.Private),
            subject,
            keyPair.Public,
            null);

        using var writer = new StringWriter();
        var pemWriter = new PemWriter(writer);
        pemWriter.WriteObject(csr);
        pemWriter.Writer.Flush();

        // API expects base64-encoded DER without PEM headers
        var pem = writer.ToString();
        return pem
            .Replace("-----BEGIN CERTIFICATE REQUEST-----", string.Empty)
            .Replace("-----END CERTIFICATE REQUEST-----", string.Empty)
            .Replace("\r", string.Empty)
            .Replace("\n", string.Empty)
            .Trim();
    }

    public static string GetTransportKey(AsymmetricCipherKeyPair keyPair)
    {
        using var writer = new StringWriter();
        var pemWriter = new PemWriter(writer);
        pemWriter.WriteObject(keyPair.Public);
        pemWriter.Writer.Flush();

        var pem = writer.ToString();
        // Remove PEM header/footer for the transport key
        return pem
            .Replace("-----BEGIN PUBLIC KEY-----", string.Empty)
            .Replace("-----END PUBLIC KEY-----", string.Empty)
            .Replace("\r", string.Empty)
            .Replace("\n", string.Empty)
            .Trim();
    }

    /// <summary>
    /// Parses a PEM certificate string into an X509Certificate.
    /// Used to extract the printer certificate from the registration response.
    /// </summary>
    public static X509Certificate ParseCertificate(string pemCertificate)
    {
        using var reader = new StringReader(pemCertificate);
        var pemReader = new PemReader(reader);
        return (X509Certificate)pemReader.ReadObject();
    }
}
