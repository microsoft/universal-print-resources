using System.Text;
using BadgeReleaseDemo.IppOperations;

namespace BadgeReleaseDemo.Tests;

public class MinimalIppTests
{
    [Fact]
    public void BuildBadgeReleaseCapabilitiesRequest_UsesExpectedWireContract()
    {
        var request = MinimalIpp.BuildBadgeReleaseCapabilitiesRequest(
            requestId: 7,
            printerUri: "ipps://print.example/printers/printer-1",
            outputDeviceUuid: "printer-1");

        Assert.Equal(0x00, request[2]);
        Assert.Equal(0x49, request[3]);

        using var stream = new MemoryStream(request);
        using var reader = new BinaryReader(stream, Encoding.UTF8);
        reader.ReadBytes(8);

        Assert.Equal(0x01, reader.ReadByte());
        Assert.Equal(
            (0x47, "attributes-charset", "utf-8"),
            ReadAttribute(reader));
        Assert.Equal(
            (0x48, "attributes-natural-language", "en-us"),
            ReadAttribute(reader));
        Assert.Equal(
            (0x45, "printer-uri", "ipps://print.example/printers/printer-1"),
            ReadAttribute(reader));
        Assert.Equal(
            (0x47, "output-device-uuid", "urn:uuid:printer-1"),
            ReadAttribute(reader));

        Assert.Equal(0x04, reader.ReadByte());
        Assert.Equal(
            (0x44, "job-release-action-supported", "owner-authorized-badge"),
            ReadAttribute(reader));
        Assert.Equal(0x03, reader.ReadByte());
        Assert.Equal(stream.Length, stream.Position);
    }

    [Fact]
    public void ParseGetJobsResponse_DecodesFourByteJobId()
    {
        const int expectedJobId = 14605388;
        var jobUri = $"ipps://print.example/jobs/{expectedJobId}";
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream, Encoding.UTF8, leaveOpen: true);

        writer.Write(new byte[]
        {
            0x02, 0x00,             // IPP 2.0
            0x00, 0x00,             // successful-ok
            0x00, 0x00, 0x00, 0x01, // request-id
            0x02                    // job-attributes-tag
        });
        WriteAttribute(writer, 0x21, "job-id", Int32BigEndian(expectedJobId));
        WriteAttribute(writer, 0x45, "job-uri", Encoding.UTF8.GetBytes(jobUri));
        writer.Write((byte)0x03);

        var (status, jobs) = MinimalIpp.ParseGetJobsResponse(stream.ToArray());

        Assert.Equal(0, status);
        var job = Assert.Single(jobs);
        Assert.Equal(expectedJobId, job["job-id"]);
        Assert.Equal(jobUri, job["job-uri"]);
    }

    private static void WriteAttribute(
        BinaryWriter writer,
        byte tag,
        string name,
        byte[] value)
    {
        writer.Write(tag);
        WriteLength(writer, name.Length);
        writer.Write(Encoding.UTF8.GetBytes(name));
        WriteLength(writer, value.Length);
        writer.Write(value);
    }

    private static void WriteLength(BinaryWriter writer, int length)
    {
        writer.Write((byte)(length >> 8));
        writer.Write((byte)length);
    }

    private static byte[] Int32BigEndian(int value) =>
    [
        (byte)(value >> 24),
        (byte)(value >> 16),
        (byte)(value >> 8),
        (byte)value
    ];

    private static (int Tag, string Name, string Value) ReadAttribute(BinaryReader reader)
    {
        var tag = reader.ReadByte();
        var name = Encoding.UTF8.GetString(reader.ReadBytes(ReadLength(reader)));
        var value = Encoding.UTF8.GetString(reader.ReadBytes(ReadLength(reader)));
        return (tag, name, value);
    }

    private static int ReadLength(BinaryReader reader) =>
        (reader.ReadByte() << 8) | reader.ReadByte();
}
