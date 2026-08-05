// <copyright file="MinimalIpp.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

using System.Globalization;
using System.Text;

namespace BadgeReleaseDemo.IppOperations;

/// <summary>
/// Minimal, auditable IPP (Internet Printing Protocol) implementation for Universal Print.
/// Implements only the 5 operations needed: Get-Jobs, Fetch-Job, Acknowledge-Job, Fetch-Document, Update-Job-Status.
/// Based on RFC 8011 (IPP/1.1). The Fetch/Acknowledge/Update operations belong to the IPP INFRA
/// extension family; the operation codes below are the values the Universal Print service expects on
/// the wire, which differ from the codes published in the IANA IPP registry / PWG 5100.18. Where they
/// differ, the constants here are authoritative for talking to Universal Print.
///
/// This is NOT a general-purpose IPP library. It is custom, minimal code with the narrowest possible
/// attack surface for Badge Release Demo operations.
/// </summary>
public static class MinimalIpp
{
    // IPP Protocol Constants (RFC 8011)
    private const byte IPP_VERSION_MAJOR = 2;
    private const byte IPP_VERSION_MINOR = 0;

    // Operation codes. Get-Jobs is the standard RFC 8011 value; the remaining Fetch/Acknowledge/Update
    // codes are the ones Universal Print's INFRA endpoint expects (not the IANA/PWG 5100.18 registry values).
    private const ushort OP_GET_JOBS = 0x000a;
    private const ushort OP_FETCH_JOB = 0x0043;
    private const ushort OP_ACKNOWLEDGE_JOB = 0x0041;
    private const ushort OP_FETCH_DOCUMENT = 0x0042;
    private const ushort OP_UPDATE_JOB_STATUS = 0x0048;

    // Attribute group tags
    private const byte TAG_OPERATION_ATTRIBUTES = 0x01;
    private const byte TAG_PRINTER_ATTRIBUTES = 0x04;
    private const byte TAG_JOB_ATTRIBUTES = 0x02;
    private const byte TAG_END_OF_ATTRIBUTES = 0x03;

    // Attribute value tags
    private const byte TAG_INTEGER = 0x21;
    private const byte TAG_BOOLEAN = 0x22;
    private const byte TAG_ENUM = 0x23;
    private const byte TAG_STRING = 0x30;
    private const byte TAG_KEYWORD = 0x44;
    private const byte TAG_URI = 0x45;
    private const byte TAG_NAME_WITHOUT_LANGUAGE = 0x42;
    private const byte TAG_TEXT_WITHOUT_LANGUAGE = 0x41;

    // Standard IPP value tags for the mandatory operation attributes (RFC 8011 section 5.1).
    private const byte TAG_CHARSET = 0x47;          // attributes-charset
    private const byte TAG_NATURAL_LANGUAGE = 0x48; // attributes-natural-language

    /// <summary>
    /// Builds a Get-Jobs IPP request to query fetchable jobs for a user.
    /// Operation code: 0x000a (Get-Jobs)
    /// Attribute order must match IppLibrary for compatibility with Universal Print service.
    /// </summary>
    public static byte[] BuildGetJobsRequest(
        ushort requestId, string printerUri, string jobType, string requestingUserUri, string outputDeviceUuid = "")
    {
        using var stream = new MemoryStream();
        
        // IPP Header
        WriteIppHeader(stream, requestId, OP_GET_JOBS);
        
        // Operation Attributes Group
        stream.WriteByte(TAG_OPERATION_ATTRIBUTES);
        
        // Must start with charset and language (required by RFC 8011)
        WriteAttributeWithTag(stream, TAG_CHARSET, "attributes-charset", "UTF-8");
        WriteAttributeWithTag(stream, TAG_NATURAL_LANGUAGE, "attributes-natural-language", "en-us");
        
        // Add requesting-user-uri (can be empty but attribute should be present)
        if (!string.IsNullOrEmpty(requestingUserUri))
        {
            WriteAttributeWithTag(stream, TAG_URI, "requesting-user-uri", requestingUserUri);
        }
        
        // Add my-jobs attribute (boolean) AFTER requesting-user-uri when it's provided
        if (!string.IsNullOrEmpty(requestingUserUri))
        {
            WriteAttributeWithTag(stream, TAG_BOOLEAN, "my-jobs", "true");
        }
        
        // Add printer-uri
        WriteAttributeWithTag(stream, TAG_URI, "printer-uri", printerUri);
        
        // Add output-device-uuid if provided
        if (!string.IsNullOrEmpty(outputDeviceUuid))
        {
            WriteAttributeWithTag(stream, TAG_URI, "output-device-uuid", $"urn:uuid:{outputDeviceUuid}");
        }
        
        // Add which-jobs attribute (keyword) AFTER printer-uri/output-device-uuid
        if (!string.IsNullOrEmpty(jobType))
        {
            WriteAttributeWithTag(stream, TAG_KEYWORD, "which-jobs", jobType);
        }
        
        // Requested attributes (always add)
        WriteAttributeWithTag(stream, TAG_KEYWORD, "requested-attributes", "all");
        
        // End of attributes
        stream.WriteByte(TAG_END_OF_ATTRIBUTES);
        
        return stream.ToArray();
    }
    
    /// <summary>
    /// Writes an attribute with a specific value tag.
    /// </summary>
    private static void WriteAttributeWithTag(MemoryStream stream, byte valueTag, string name, string value)
    {
        // Special handling for boolean values
        if (valueTag == TAG_BOOLEAN)
        {
            WriteBooleanAttribute(stream, name, value == "true" || value == "1");
            return;
        }
        
        stream.WriteByte(valueTag);
        WriteString(stream, name);
        WriteString(stream, value);
    }
    
    private static void WriteBooleanAttribute(MemoryStream stream, string name, bool value)
    {
        stream.WriteByte(TAG_BOOLEAN);
        WriteString(stream, name);
        WriteUInt16BigEndian(stream, 1); // length is always 1 for boolean
        stream.WriteByte(value ? (byte)0x01 : (byte)0x00);
    }

    /// <summary>
    /// Builds a Fetch-Job IPP request to retrieve job metadata.
    /// Operation code: OP_FETCH_JOB (0x0043) — the value Universal Print's INFRA endpoint expects.
    /// </summary>
    public static byte[] BuildFetchJobRequest(
        ushort requestId, string printerUri, int jobId, string outputDeviceUuid = "", string requestingUserUri = "")
    {
        using var stream = new MemoryStream();
        
        WriteIppHeader(stream, requestId, OP_FETCH_JOB);
        
        stream.WriteByte(TAG_OPERATION_ATTRIBUTES);
        
        // Mandatory attributes
        WriteAttributeWithTag(stream, TAG_CHARSET, "attributes-charset", "UTF-8");
        WriteAttributeWithTag(stream, TAG_NATURAL_LANGUAGE, "attributes-natural-language", "en-us");
        
        // Add requesting-user-uri if provided
        if (!string.IsNullOrEmpty(requestingUserUri))
        {
            WriteAttributeWithTag(stream, TAG_URI, "requesting-user-uri", requestingUserUri);
        }
        
        // Printer URI
        WriteAttributeWithTag(stream, TAG_URI, "printer-uri", printerUri);
        
        // Add output-device-uuid if provided
        if (!string.IsNullOrEmpty(outputDeviceUuid))
        {
            WriteAttributeWithTag(stream, TAG_URI, "output-device-uuid", $"urn:uuid:{outputDeviceUuid}");
        }
        
        // Job ID
        WriteIntegerAttribute(stream, "job-id", jobId);
        
        stream.WriteByte(TAG_END_OF_ATTRIBUTES);
        
        return stream.ToArray();
    }

    /// <summary>
    /// Builds an Acknowledge-Job IPP request to confirm job receipt.
    /// Operation code: 0x0041 (AcknowledgeJob)
    /// </summary>
    public static byte[] BuildAcknowledgeJobRequest(
        ushort requestId, string printerUri, int jobId, string statusMessage, string outputDeviceUuid = "", string requestingUserUri = "")
    {
        using var stream = new MemoryStream();
        
        WriteIppHeader(stream, requestId, OP_ACKNOWLEDGE_JOB);
        
        stream.WriteByte(TAG_OPERATION_ATTRIBUTES);
        
        // Mandatory attributes
        WriteAttributeWithTag(stream, TAG_CHARSET, "attributes-charset", "UTF-8");
        WriteAttributeWithTag(stream, TAG_NATURAL_LANGUAGE, "attributes-natural-language", "en-us");
        
        // Add requesting-user-uri if provided
        if (!string.IsNullOrEmpty(requestingUserUri))
        {
            WriteAttributeWithTag(stream, TAG_URI, "requesting-user-uri", requestingUserUri);
        }
        
        // Printer URI
        WriteAttributeWithTag(stream, TAG_URI, "printer-uri", printerUri);
        
        // Add output-device-uuid if provided
        if (!string.IsNullOrEmpty(outputDeviceUuid))
        {
            WriteAttributeWithTag(stream, TAG_URI, "output-device-uuid", $"urn:uuid:{outputDeviceUuid}");
        }
        
        // Job ID
        WriteIntegerAttribute(stream, "job-id", jobId);
        
        // Fetch status message (if provided)
        if (!string.IsNullOrEmpty(statusMessage))
        {
            WriteStringAttribute(stream, "fetch-status-message", statusMessage);
        }
        
        stream.WriteByte(TAG_END_OF_ATTRIBUTES);
        
        return stream.ToArray();
    }

    /// <summary>
    /// Builds a Fetch-Document IPP request to download the print document.
    /// Operation code: 0x0042 (Fetch-Document)
    /// </summary>
    public static byte[] BuildFetchDocumentRequest(
        ushort requestId, string printerUri, int jobId, int documentNumber, string outputDeviceUuid = "", string requestingUserUri = "", string jobUri = "")
    {
        using var stream = new MemoryStream();
        
        WriteIppHeader(stream, requestId, OP_FETCH_DOCUMENT);
        
        stream.WriteByte(TAG_OPERATION_ATTRIBUTES);
        
        // Mandatory attributes
        WriteAttributeWithTag(stream, TAG_CHARSET, "attributes-charset", "UTF-8");
        WriteAttributeWithTag(stream, TAG_NATURAL_LANGUAGE, "attributes-natural-language", "en-us");
        
        // Requesting user URI (matches other working operations)
        if (!string.IsNullOrEmpty(requestingUserUri))
        {
            WriteAttributeWithTag(stream, TAG_URI, "requesting-user-uri", requestingUserUri);
        }
        
        // Printer URI
        WriteAttributeWithTag(stream, TAG_URI, "printer-uri", printerUri);
        
        // Output device UUID (matches other working operations)
        if (!string.IsNullOrEmpty(outputDeviceUuid))
        {
            WriteAttributeWithTag(stream, TAG_URI, "output-device-uuid", $"urn:uuid:{outputDeviceUuid}");
        }
        
        // Job URI (some services require it explicitly for Fetch-Document)
        if (!string.IsNullOrEmpty(jobUri))
        {
            WriteAttributeWithTag(stream, TAG_URI, "job-uri", jobUri);
        }
        
        // Job ID and document number
        WriteIntegerAttribute(stream, "job-id", jobId);
        WriteIntegerAttribute(stream, "document-number", documentNumber);
        
        stream.WriteByte(TAG_END_OF_ATTRIBUTES);
        
        return stream.ToArray();
    }

    /// <summary>
    /// Builds an Update-Job-Status IPP request to mark a job as completed.
    /// Operation code: OP_UPDATE_JOB_STATUS (0x0048) — the value Universal Print's INFRA endpoint expects.
    /// </summary>
    public static byte[] BuildUpdateJobStatusRequest(
        ushort requestId, string printerUri, int jobId, int jobState, string outputDeviceUuid = "", string requestingUserUri = "")
    {
        using var stream = new MemoryStream();
        
        WriteIppHeader(stream, requestId, OP_UPDATE_JOB_STATUS);
        
        stream.WriteByte(TAG_OPERATION_ATTRIBUTES);
        
        // Mandatory attributes
        WriteAttributeWithTag(stream, TAG_CHARSET, "attributes-charset", "UTF-8");
        WriteAttributeWithTag(stream, TAG_NATURAL_LANGUAGE, "attributes-natural-language", "en-us");
        
        // Requesting user URI (matches other working operations)
        if (!string.IsNullOrEmpty(requestingUserUri))
        {
            WriteAttributeWithTag(stream, TAG_URI, "requesting-user-uri", requestingUserUri);
        }
        
        // Printer URI
        WriteAttributeWithTag(stream, TAG_URI, "printer-uri", printerUri);
        
        // Output device UUID (matches other working operations)
        if (!string.IsNullOrEmpty(outputDeviceUuid))
        {
            WriteAttributeWithTag(stream, TAG_URI, "output-device-uuid", $"urn:uuid:{outputDeviceUuid}");
        }
        
        // Job ID in operation attributes
        WriteIntegerAttribute(stream, "job-id", jobId);

        // Job state in job attributes group
        stream.WriteByte(TAG_JOB_ATTRIBUTES);
        WriteEnumAttribute(stream, "output-device-job-state", jobState);
        
        stream.WriteByte(TAG_END_OF_ATTRIBUTES);
        
        return stream.ToArray();
    }

    /// <summary>
    /// Parses an IPP response and extracts status code and job attributes.
    /// Returns (statusCode, jobAttributes) where jobAttributes is a collection of dictionaries per job.
    /// </summary>
    public static (ushort StatusCode, List<Dictionary<string, object>> JobAttributes) ParseGetJobsResponse(byte[] responseData)
    {
        if (responseData.Length < 8)
        {
            throw new InvalidDataException("Invalid IPP response: expected at least 8 bytes for header.");
        }

        using var stream = new MemoryStream(responseData);
        using var reader = new BinaryReader(stream);

        // IPP Header: version (2 bytes) + status-code (2 bytes) + request-id (4 bytes).
        // Only the status code is needed here; skip the version and request-id.
        reader.ReadBytes(2); // version-major + version-minor
        ushort statusCode = ReadUInt16BigEndian(reader);
        reader.ReadBytes(4); // request-id

        var jobs = new List<Dictionary<string, object>>();

        // Parse attribute groups
        while (stream.Position < stream.Length)
        {
            byte tag = reader.ReadByte();

            if (tag == TAG_END_OF_ATTRIBUTES)
                break;

            if (tag == TAG_JOB_ATTRIBUTES)
            {
                var jobAttrs = ParseAttributeGroup(reader);
                jobs.Add(jobAttrs);
            }
            else
            {
                // Skip unknown attribute group
                SkipAttributeGroup(reader);
            }
        }

        return (statusCode, jobs);
    }

    /// <summary>
    /// Parses an IPP response for Fetch-Job and extracts job attributes.
    /// </summary>
    public static (ushort StatusCode, Dictionary<string, object> JobAttributes, byte[]? DocumentData) ParseFetchJobResponse(byte[] responseData)
    {
        if (responseData.Length < 8)
        {
            throw new InvalidDataException("Invalid IPP response: expected at least 8 bytes for header.");
        }

        using var stream = new MemoryStream(responseData);
        using var reader = new BinaryReader(stream);

        // IPP Header: version (2 bytes) + status-code (2 bytes) + request-id (4 bytes).
        reader.ReadBytes(2); // version-major + version-minor
        ushort statusCode = ReadUInt16BigEndian(reader);
        reader.ReadBytes(4); // request-id

        var jobAttrs = new Dictionary<string, object>();

        // Parse attribute groups
        while (stream.Position < stream.Length)
        {
            byte tag = reader.ReadByte();

            if (tag == TAG_END_OF_ATTRIBUTES)
                break;

            if (tag == TAG_JOB_ATTRIBUTES)
            {
                jobAttrs = ParseAttributeGroup(reader);
            }
            else
            {
                SkipAttributeGroup(reader);
            }
        }

        // Remaining bytes are the document data (if any)
        byte[] documentData = reader.ReadBytes((int)(stream.Length - stream.Position));
        return (statusCode, jobAttrs, documentData.Length > 0 ? documentData : null);
    }

    /// <summary>
    /// Parses an IPP response and extracts status code.
    /// </summary>
    public static ushort ParseStatusCodeResponse(byte[] responseData)
    {
        if (responseData.Length < 8)
        {
            throw new InvalidDataException("Invalid IPP response: expected at least 8 bytes for header.");
        }

        return (ushort)((responseData[2] << 8) | responseData[3]);
    }

    // ---- Private Helpers ----

    private static void WriteIppHeader(MemoryStream stream, ushort requestId, ushort operationCode)
    {
        stream.WriteByte(IPP_VERSION_MAJOR);
        stream.WriteByte(IPP_VERSION_MINOR);
        WriteUInt16BigEndian(stream, operationCode);
        WriteUInt32BigEndian(stream, requestId);
    }

    private static void WriteStringAttribute(MemoryStream stream, string name, string value)
    {
        stream.WriteByte(TAG_TEXT_WITHOUT_LANGUAGE);
        WriteString(stream, name);
        WriteString(stream, value);
    }

    private static void WriteIntegerAttribute(MemoryStream stream, string name, int value)
    {
        stream.WriteByte(TAG_INTEGER);
        WriteString(stream, name);
        WriteUInt16BigEndian(stream, 4); // 4 bytes for integer value
        WriteInt32BigEndian(stream, value);
    }

    private static void WriteEnumAttribute(MemoryStream stream, string name, int value)
    {
        stream.WriteByte(TAG_ENUM);
        WriteString(stream, name);
        WriteUInt16BigEndian(stream, 4); // 4 bytes for enum value
        WriteInt32BigEndian(stream, value);
    }

    private static void WriteString(MemoryStream stream, string value)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(value);
        WriteUInt16BigEndian(stream, (ushort)bytes.Length);
        stream.Write(bytes, 0, bytes.Length);
    }

    private static Dictionary<string, object> ParseAttributeGroup(BinaryReader reader)
    {
        var attrs = new Dictionary<string, object>();
        string? lastAttributeName = null;

        while (reader.BaseStream.Position < reader.BaseStream.Length)
        {
            byte tag = reader.ReadByte();

            if (IsDelimiterTag(tag))
            {
                reader.BaseStream.Seek(-1, SeekOrigin.Current);
                break;
            }

            string name = ReadString(reader);
            object value = ReadValue(reader, tag);

            var attributeName = string.IsNullOrEmpty(name) ? lastAttributeName : name;
            if (string.IsNullOrEmpty(attributeName))
            {
                throw new InvalidDataException("Malformed IPP attribute group: encountered empty attribute name without a previous name.");
            }

            if (!string.IsNullOrEmpty(name))
            {
                lastAttributeName = name;
            }

            if (attrs.TryGetValue(attributeName, out var existingValue))
            {
                if (existingValue is List<object> existingList)
                {
                    existingList.Add(value);
                }
                else
                {
                    attrs[attributeName] = new List<object> { existingValue, value };
                }
            }
            else
            {
                attrs[attributeName] = value;
            }
        }

        return attrs;
    }

    private static void SkipAttributeGroup(BinaryReader reader)
    {
        while (reader.BaseStream.Position < reader.BaseStream.Length)
        {
            byte tag = reader.ReadByte();

            if (IsDelimiterTag(tag))
            {
                reader.BaseStream.Seek(-1, SeekOrigin.Current);
                break;
            }

            string name = ReadString(reader);
            SkipValue(reader);
        }
    }

    private static string ReadString(BinaryReader reader)
    {
        ushort length = ReadUInt16BigEndian(reader);
        byte[] bytes = reader.ReadBytes(length);
        return Encoding.UTF8.GetString(bytes);
    }

    private static object ReadValue(BinaryReader reader, byte tag)
    {
        ushort length = ReadUInt16BigEndian(reader);
        byte[] valueBytes = reader.ReadBytes(length);
        if (valueBytes.Length != length)
        {
            throw new InvalidDataException("Malformed IPP value: insufficient bytes for declared length.");
        }

        return tag switch
        {
            TAG_INTEGER => length == 4
                ? (int)((valueBytes[0] << 24) | (valueBytes[1] << 16) | (valueBytes[2] << 8) | valueBytes[3])
                : valueBytes,
            TAG_BOOLEAN => length == 1
                ? valueBytes[0] != 0
                : valueBytes,
            TAG_ENUM => length == 4
                ? (int)((valueBytes[0] << 24) | (valueBytes[1] << 16) | (valueBytes[2] << 8) | valueBytes[3])
                : valueBytes,
            TAG_KEYWORD or TAG_NAME_WITHOUT_LANGUAGE or TAG_TEXT_WITHOUT_LANGUAGE or TAG_URI or TAG_STRING =>
                Encoding.UTF8.GetString(valueBytes),
            _ => valueBytes
        };
    }

    private static void SkipValue(BinaryReader reader)
    {
        ushort length = ReadUInt16BigEndian(reader);
        reader.ReadBytes(length);
    }

    private static bool IsDelimiterTag(byte tag)
    {
        // IPP delimiter tags are in the low range (0x01-0x0F): operation/job/printer/document groups and end tag.
        return tag <= 0x0F;
    }

    private static ushort ReadUInt16BigEndian(BinaryReader reader)
    {
        byte[] bytes = reader.ReadBytes(2);
        return (ushort)((bytes[0] << 8) | bytes[1]);
    }

    private static void WriteUInt16BigEndian(MemoryStream stream, ushort value)
    {
        stream.WriteByte((byte)((value >> 8) & 0xFF));
        stream.WriteByte((byte)(value & 0xFF));
    }

    private static uint ReadUInt32BigEndian(BinaryReader reader)
    {
        byte[] bytes = reader.ReadBytes(4);
        return (uint)((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]);
    }

    private static void WriteUInt32BigEndian(MemoryStream stream, uint value)
    {
        stream.WriteByte((byte)((value >> 24) & 0xFF));
        stream.WriteByte((byte)((value >> 16) & 0xFF));
        stream.WriteByte((byte)((value >> 8) & 0xFF));
        stream.WriteByte((byte)(value & 0xFF));
    }

    private static void WriteInt32BigEndian(MemoryStream stream, int value)
    {
        stream.WriteByte((byte)((value >> 24) & 0xFF));
        stream.WriteByte((byte)((value >> 16) & 0xFF));
        stream.WriteByte((byte)((value >> 8) & 0xFF));
        stream.WriteByte((byte)(value & 0xFF));
    }
}
