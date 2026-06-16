//-----------------------------------------------------------------------
// <copyright file="Helpers.cs" company="Microsoft">
// Copyright (c) Microsoft. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

namespace BadgeReleaseDemo.IppLibrary
{
    using System;
    using System.Collections.Generic;
    using System.Globalization;
    using System.IO;
    using System.Linq;
    using System.Text;
    using BadgeReleaseDemo.IppLibrary.Common;

    public static class Helpers
    {
        /// <summary>
        /// Used in the job-uri path.
        /// Example: ipps://print.print.microsoft.com/printers/810a8958-13f4-4044-a09b-a372e8990a6b/jobs/388
        /// </summary>
        private const string JobUriSegment = "jobs";

        /// <summary>
        /// Used in the printer-uri and job-uri path.
        /// Example: ipps://print.print.microsoft.com/printers/810a8958-13f4-4044-a09b-a372e8990a6b/jobs/388
        /// </summary>
        private const string PrinterSegment = "printers";

        /// <summary>
        /// URN URI Scheme
        /// </summary>
        private const string UrnScheme = "urn";

        /// <summary>
        /// Prefix for UUID URIs
        /// </summary>
        private const string UuidPrefix = "uuid:";

        public static void WriteNetworkShort(Stream s, short shortValue)
        {
            s.WriteByte((byte)(shortValue >> 8));
            s.WriteByte((byte)shortValue);
        }

        public static void WriteNetworkInteger(Stream s, int intValue)
        {
            s.WriteByte((byte)(intValue >> 24));
            s.WriteByte((byte)((intValue & 0x00ff0000) >> 16));
            s.WriteByte((byte)((intValue & 0x0000ff00) >> 8));
            s.WriteByte((byte)intValue);
        }

        public static void WriteAsciiString(Stream s, string stringValue)
        {
            byte[] arr = Encoding.ASCII.GetBytes(stringValue);
            MemoryStream ms = new MemoryStream(arr);
            ms.CopyTo(s);
        }

        public static byte[] StringToUTF8ByteArray(string stringValue)
        {
            if (stringValue == null)
            {
                stringValue = string.Empty;
            }

            return Encoding.UTF8.GetBytes(stringValue);
        }

        public static string UTF8ByteArrayToString(byte[] byteArray)
        {
            return Encoding.UTF8.GetString(byteArray);
        }

        public static string UTF8ByteArrayToString(byte[] byteArray, int offset, int length)
        {
            if (offset < 0 || length < 0 || offset + length > byteArray.Length)
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, "Buffer overflow reading a string.");
            }

            return Encoding.UTF8.GetString(byteArray, offset, length);
        }

        /// <summary>
        /// Unlike the above, this is more or less correct, though we may want to check for non-ASCII chars in the incoming string.
        /// </summary>
        /// <param name="stringValue">The string to convert to byte array.</param>
        /// <returns>Byte array representation of the string.</returns>
        public static byte[] StringToASCIIByteArray(string stringValue)
        {
            return Encoding.ASCII.GetBytes(stringValue);
        }

        /// <summary>
        /// See comments above
        /// </summary>
        /// <param name="byteArray">The byte array.</param>
        /// <returns>String of byte array.</returns>
        public static string ASCIIByteArrayToString(byte[] byteArray)
        {
            return Encoding.ASCII.GetString(byteArray);
        }

        /// <summary>
        /// Recover a string from a byte array.
        /// </summary>
        /// <param name="byteArray">The byte array.</param>
        /// <param name="offset">Offset to the beginning of the string.</param>
        /// <param name="length">Length of string.</param>
        /// <returns>ASCII string of the byte array.</returns>
        public static string ASCIIByteArrayToString(byte[] byteArray, int offset, int length)
        {
            if (offset < 0 || length < 0 || offset + length > byteArray.Length)
            {
                throw new IPPException(StatusCode.ClientErrorNotPossible, "Buffer overflow reading a string.");
            }

            var sb = new StringBuilder();
            for (var i = 0; i < length; i++)
            {
                sb.Append((char)byteArray[i + offset]);
            }

            return sb.ToString();
        }

        public static bool ByteArrayToBool(byte[] b)
        {
            return b[0] != 0;
        }

        public static short ByteArrayToShort(byte[] b)
        {
            return (short)(ushort)((b[0] << 8) | b[1]);
        }

        public static byte[] ShortToByteArray(short x)
        {
            var b = new byte[2];
            b[0] = (byte)(x >> 8);
            b[1] = (byte)x;
            return b;
        }

        public static int ByteArrayToInteger(byte[] byteArray)
        {
            return (byteArray[0] << 24) | (byteArray[1] << 16) | (byteArray[2] << 8) | byteArray[3];
        }

        public static Tuple<int, int> ByteArrayToIntegerRange(byte[] byteArray)
        {
            var lower = (byteArray[0] << 24) | (byteArray[1] << 16) | (byteArray[2] << 8) | byteArray[3];
            var upper = (byteArray[4] << 24) | (byteArray[5] << 16) | (byteArray[6] << 8) | byteArray[7];
            return new Tuple<int, int>(lower, upper);
        }

        /// <summary>
        /// Converts an integer to a byte array
        /// </summary>
        /// <param name="intValue">The integer value.</param>
        /// <returns>Byte array representation of an integer.</returns>
        public static byte[] IntegerToByteArray(int intValue)
        {
            byte[] b = new byte[4];
            b[0] = (byte)(intValue >> 24);
            b[1] = (byte)((intValue & 0x00ff0000) >> 16);
            b[2] = (byte)((intValue & 0x0000ff00) >> 8);
            b[3] = (byte)intValue;

            return b;
        }

        /// <summary>
        /// Converts a range of integer to a byte array.
        /// </summary>
        /// <param name="lower">Lower bound of the integer values.</param>
        /// <param name="upper">Upper bound of the integer values.</param>
        /// <returns>Byte array representation of an integer range.</returns>
        public static byte[] IntegerRangeToByteArray(int lower, int upper)
        {
            if (lower > upper)
            {
                throw new IPPException(StatusCode.ClientErrorNotPossible, "Incorrect integer range.");
            }

            var lowerBound = IntegerToByteArray(lower);
            var upperBound = IntegerToByteArray(upper);
            return lowerBound.Concat(upperBound).ToArray();
        }

        /// <summary>
        /// Converts .Net DateTime to a byte array according to https://tools.ietf.org/html/rfc2579 page 18.
        /// </summary>
        /// <param name="dateTime">DateTime value, always in UTC.</param>
        /// <returns>Byte array representation of a date time object.</returns>
        public static byte[] DateTimeToByteArray(DateTime dateTime)
        {
            var byteArray = new[]
                            {
                                (byte)(dateTime.Year >> 8),
                                (byte)dateTime.Year,
                                (byte)dateTime.Month,
                                (byte)dateTime.Day,
                                (byte)dateTime.Hour,
                                (byte)dateTime.Minute,
                                (byte)dateTime.Second,
                                (byte)(dateTime.Millisecond / 100),
                                (byte)'+',
                                (byte)0,
                                (byte)0
                            };

            return byteArray;
        }

        /// <summary>
        /// Converts IPP resolution (https://tools.ietf.org/html/rfc8011#section-5.1.16) to byte array.
        /// </summary>
        /// <param name="x">The x dimension.</param>
        /// <param name="y">The y dimension.</param>
        /// <param name="units">The unit of the dimensions.</param>
        /// <returns>Byte array representation of resolution dimensions.</returns>
        public static byte[] ResolutionToByteArray(int x, int y, sbyte units)
        {
            var xStream = IntegerToByteArray(x);
            var yStream = IntegerToByteArray(y);
            var unitStream = new byte[] { (byte)units };
            return xStream.Concat(yStream).Concat(unitStream).ToArray();
        }

        /// <summary>
        /// Converts a byte array IPP resolution (https://tools.ietf.org/html/rfc8011#section-5.1.16).
        /// </summary>
        /// <param name="b">IPP resolution.</param>
        /// <returns>Resolution dimension of the byte array.</returns>
        public static Tuple<int, int, sbyte> ByteArrayToResolution(byte[] b)
        {
            var x = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
            var y = (b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7];
            var units = (sbyte)b[8];
            return new Tuple<int, int, sbyte>(x, y, units);
        }

        /// <summary>
        /// Converts a string to IPP string with natural language (e.g., TextWithNaturalLanguage and NameWithNaturalLanguage).
        /// </summary>
        /// <param name="theString">The plain string.</param>
        /// <param name="naturalLanguage">The natural language</param>
        /// <returns>Byte array of the string.</returns>
        public static byte[] StringWithNaturalLanguageToByteArray(string theString, string naturalLanguage)
        {
            // Note:  from the RFC:
            //    a. a SIGNED-SHORT which is the number of
            //         octets in the following field
            //    b. a value of type natural-language,
            //    c. a SIGNED-SHORT which is the number of
            //         octets in the following field,
            //    d. a value of type textWithoutLanguage.
            var langLength = ShortToByteArray((short)naturalLanguage.Length);
            var langValue = StringToASCIIByteArray(naturalLanguage);
            var stringValue = StringToUTF8ByteArray(theString);
            /*
             * https://tools.ietf.org/html/rfc8010#section-3
             * 3.9. (Attribute) "value"
               +----------------------+--------------------------------------------+
               | Syntax of Attribute  | Encoding                                   |
               | Value                |                                            |
               +----------------------+--------------------------------------------+
               | textWithoutLanguage, | LOCALIZED-STRING                           |
               | nameWithoutLanguage  |                                            |
               +----------------------+--------------------------------------------+
               | textWithLanguage     | OCTET-STRING consisting of four fields: a  |
               |                      | SIGNED-SHORT, which is the number of       |
               |                      | octets in the following field; a value of  |
               |                      | type natural-language; a SIGNED-SHORT,     |
               |                      | which is the number of octets in the       |
               |                      | following field; and a value of type       |
               |                      | textWithoutLanguage.  The length of a      |
               |                      | textWithLanguage value MUST be 4 + the     |
               |                      | value of field a + the value of field c.   |
               +----------------------+--------------------------------------------+
               */

            // NOTE: the SIGNED-SHORT of field c is the number of octets which is LOCALIZED-STRING
            var stringLength = ShortToByteArray((short)stringValue.Length);
            return langLength.Concat(langValue).Concat(stringLength).Concat(stringValue).ToArray();
        }

        /// <summary>
        /// Converts a byte array of IPP string with natural language to string and the natural language parts.
        /// </summary>
        /// <param name="b">The IPP stream.</param>
        /// <returns>String of the byte array.</returns>
        public static Tuple<string, string> ByteArrayToStringWithNaturalLanguage(byte[] b)
        {
            // Note:  from the RFC:
            //    a. a SIGNED-SHORT which is the number of
            //         octets in the following field
            //    b. a value of type natural-language,
            //    c. a SIGNED-SHORT which is the number of
            //         octets in the following field,
            //    d. a value of type textWithoutLanguage.
            var langLength = (short)(ushort)((b[0] << 8) | b[1]);
            var langValue = ASCIIByteArrayToString(b, 2, langLength);

            var languageByteCount = 2 + langLength;
            var stringLength = (short)(ushort)(b[languageByteCount] << 8 | b[languageByteCount + 1]);
            var stringValue = UTF8ByteArrayToString(b, languageByteCount + 2, stringLength);

            return new Tuple<string, string>(stringValue, langValue);
        }

        /// <summary>
        /// Converts a byte array to .Net DateTime according to https://tools.ietf.org/html/rfc2579 page 18.
        /// </summary>
        /// <param name="dateTimeArray">IPP DateTime array.</param>
        /// <returns>Date time object from a byte array.</returns>
        public static DateTime ByteArrayToDateTime(byte[] dateTimeArray)
        {
            var year = (dateTimeArray[0] << 8) | dateTimeArray[1];
            var month = dateTimeArray[2];
            var day = dateTimeArray[3];
            var hour = dateTimeArray[4];
            var minute = dateTimeArray[5];
            var second = dateTimeArray[6];

            // Before version 4.0.1, the 8th octet (dateTimeArray[7]) was used to store centisecond instead of deci second.
            // To support the clients sending centiseconds in place of deciseconds, a modulo 1000 is added.
            var milliSecond = (dateTimeArray[7] * 100) % 1000;

            return new System.DateTime(year, month, day, hour, minute, second, milliSecond, DateTimeKind.Local);
        }

        /// <summary>
        /// Converts a boolValue to a byte array
        /// </summary>
        /// <param name="boolValue">The boolean value.</param>
        /// <returns>Byte array of a boolean.</returns>
        public static byte[] BoolToByteArray(bool boolValue)
        {
            byte[] b = new byte[1];
            b[0] = (byte)(boolValue ? 1 : 0);

            return b;
        }

        /// <summary>
        /// Example jobUri: ipps://localhost:44336/printers/810a8958-13f4-4044-a09b-a372e8990a6b/jobs/388
        /// Returned value: ipps://localhost:44336/printers/810a8958-13f4-4044-a09b-a372e8990a6b
        /// </summary>
        /// <param name="jobUri">The uri of a job.</param>
        /// <returns>The uri of the printer.</returns>
        public static Uri GetPrinterUriFromJobUri(Uri jobUri)
        {
            // Example: ipps://localhost:44336/printers/810a8958-13f4-4044-a09b-a372e8990a6b/jobs/388
            // Authority: "localhost:44336"
            // Segments:  [0] "/"
            //            [1] "printers/"
            //            [2] "810a8958-13f4-4044-a09b-a372e8990a6b/"
            //            [3] "jobs/"
            //            [4] "388"
            var printerUri = Helpers.CreateUri(jobUri.GetLeftPart(UriPartial.Authority));
            printerUri = Helpers.CreateUri(printerUri, jobUri.Segments[1] + jobUri.Segments[2]);
            return printerUri;
        }

        /// <summary>
        /// Example:
        /// baseUrl:  https://print.print.microsoft.com
        /// printerId: 810a8958-13f4-4044-a09b-a372e8990a6b.
        /// jobId: 388
        /// Returned value: ipps://print.print.microsoft.com/printers/810a8958-13f4-4044-a09b-a372e8990a6b/Jobs/388
        /// </summary>
        /// <param name="baseUrl">The base url.</param>
        /// <param name="printerId">The printer id.</param>
        /// <param name="jobId">The job id.</param>
        /// <returns>A uri of a job.</returns>
        public static Uri CreateJobUri(Uri baseUrl, string printerId, int jobId)
        {
            // Job uri must be "ipps".
            var jobUriBuilder = new UriBuilder(baseUrl) { Scheme = "ipps" };
            jobUriBuilder.Path += PrinterSegment + '/' + printerId + '/' + JobUriSegment + '/' + jobId.ToString(CultureInfo.InvariantCulture);
            return jobUriBuilder.Uri;
        }

        /// <summary>
        /// Example:
        /// baseUrl: https://print.print.microsoft.com
        /// printerId: 810a8958-13f4-4044-a09b-a372e8990a6b
        /// Returned value: ipps://print.print.microsoft.com/printers/810a8958-13f4-4044-a09b-a372e8990a6b
        /// </summary>
        /// <param name="baseUrl">The base url.</param>
        /// <param name="printerId">The printer id.</param>
        /// <returns>Uri of the printer.</returns>
        public static Uri CreatePrinterUri(Uri baseUrl, string printerId)
        {
            // Printer uri must be "ipps".
            var printerUriBuilder = new UriBuilder(baseUrl) { Scheme = "ipps" };
            printerUriBuilder.Path += PrinterSegment + '/' + printerId;
            return printerUriBuilder.Uri;
        }

        /// <summary>
        /// Returns the Printer UUID as a URN URI string given the printerId.
        /// For example, urn:uuid:810a8958-13f4-4044-a09b-a372e8990a6b
        /// </summary>
        /// <param name="printerId">The printer id.</param>
        /// <returns>UUID URN URI string</returns>
        public static string CreatePrinterUuidUri(string printerId)
        {
            return $"{UrnScheme}:{UuidPrefix}{printerId}";
        }

        /// <summary>
        /// Example:
        /// jobUri: ipps://localhost:44336/printers/810a8958-13f4-4044-a09b-a372e8990a6b/jobs/388
        /// returned value: 388
        /// To avoid returning an invalid job ID (e.g., -1), caller must have jobUri to call this function.
        /// </summary>
        /// <param name="jobUri">Uri of a job.</param>
        /// <returns>Job id</returns>
        public static int GetJobIdFromJobUri(Uri jobUri)
        {
            // Example:  ipps://localhost:44336/printers/8b518e16-2d2b-11e8-b467-0ed5f89f718b/jobs/388
            // Segments: [0] "/"
            //           [1] "printers/"
            //           [2] "8b518e16-2d2b-11e8-b467-0ed5f89f718b"
            //           [3] "jobs/"
            //           [4] "388"
            var jobId = int.Parse(jobUri.Segments[4].TrimEnd('/'), CultureInfo.CurrentCulture);
            return jobId;
        }

        /// <summary>
        /// Return the output-device-uuid from its uri format.
        /// Example:
        /// outputDeviceUuidUri: urn:uuid:01234567-89AB-CDEF-FEDC-BA9876543210
        /// Return: 01234567-89AB-CDEF-FEDC-BA9876543210
        /// </summary>
        /// <param name="outputDeviceUuidUri">The uuid URN.</param>
        /// <returns>The uuid string.</returns>
        public static string GetOutputDeviceUuidFromUri(string outputDeviceUuidUri)
        {
            Uri uuidUri;

            try
            {
                uuidUri = new Uri(outputDeviceUuidUri);
            }
            catch
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, "The output-device-uuid must be a uri.");
            }

            if (string.Compare(uuidUri.Scheme, UrnScheme, StringComparison.OrdinalIgnoreCase) != 0)
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, "The output-device-uuid must be of URN scheme.");
            }

            if (!CultureInfo.InvariantCulture.CompareInfo.IsPrefix(uuidUri.LocalPath, UuidPrefix, CompareOptions.IgnoreCase))
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, "The output-device-uuid must be of format urn:uuid:<value>.");
            }

            return uuidUri.LocalPath.Substring(UuidPrefix.Length);
        }

        /// <summary>
        /// Example printer URL:  ipps://localhost:44336/printers/8b518e16-2d2b-11e8-b467-0ed5f89f718b
        /// This function returns: "8b518e16-2d2b-11e8-b467-0ed5f89f718b".
        /// </summary>
        /// <param name="printerUri">Printer URL. This is typically obtained from printer-uri attribute.</param>
        /// <returns>The printer id that is extracted from printerUrl.</returns>
        public static string GetPrinterIdFromPrinterUri(Uri printerUri)
        {
            // Example:  ipps://localhost:44336/printers/8b518e16-2d2b-11e8-b467-0ed5f89f718b
            // Segments: [0] "/"
            //           [1] "printers/"
            //           [2] "8b518e16-2d2b-11e8-b467-0ed5f89f718b"
            // printer ID is in segment 2 and may have trailing '/'.
            if (printerUri == null)
            {
                return string.Empty;
            }

            Helpers.IsValidPrinterUri(printerUri);
            return printerUri.Segments[2].TrimEnd('/');
        }

        /// <summary>
        /// Example of job uri: ipps://localhost:44336/printers/810a8958-13f4-4044-a09b-a372e8990a6b/jobs/388.
        /// This function returns: 810a8958-13f4-4044-a09b-a372e8990a6b
        /// </summary>
        /// <param name="jobUri">Valid job uri.  This is typically obtained from job-uri attribute.</param>
        /// <returns>The printer id that is extracted from the jobUri.</returns>
        public static string GetPrinterIdFromJobUri(Uri jobUri)
        {
            // Example: ipps://localhost:44336/printers/810a8958-13f4-4044-a09b-a372e8990a6b/jobs/388
            // Segments: [0] "/"
            //           [1] "printers"
            //           [2] "810a8958-13f4-4044-a09b-a372e8990a6b/"
            //           [3] "jobs/"
            //           [4] "388"
            // Printer id is segment 2 and may have trailing '/'.
            if (jobUri == null)
            {
                return string.Empty;
            }

            Helpers.IsValidJobUri(jobUri);
            return jobUri.Segments[2].TrimEnd('/');
        }

        /// <summary>
        /// Retrieve the system uptime.  RFC2911 4.3.14.4 specifies job-printer-up-time as an integer (giving us 68 years of resolution)
        /// </summary>
        /// <returns>System up time in integer.</returns>
        public static int GetSystemUptime(DateTime printerCreationTimeUtc)
        {
            var nowTime = DateTime.UtcNow;
            var upTime = nowTime - printerCreationTimeUtc;
            return (int)upTime.TotalSeconds;    // double to int, max printer life time is 68 years.
        }

        /// <summary>
        /// Retrieve the culture installed on the print server.  This returns GetSystemDefaultUILanguage()
        /// </summary>
        /// <returns>Natural language string.</returns>
        public static string GetNaturalLanguage()
        {
            return CultureInfo.InstalledUICulture.Name.ToLower(CultureInfo.CurrentCulture);
        }

        /// <summary>
        /// Copy attribute value from either group 1, 2 or 3 to the target attribute group.
        /// </summary>
        /// <param name="attributeName">The name of the attribute.</param>
        /// <param name="destinationGroup">The destination to copy the attribute to.</param>
        /// <param name="group1">Attribute group 1.</param>
        /// <param name="group2">Attribute group 2.</param>
        /// <param name="group3">Attribute group 3.</param>
        /// <returns>True if the attribute already exists in or is inserted to destinationGroup.</returns>
        public static bool CopyAttribute(
            string attributeName,
            IppAttributeGroup destinationGroup,
            IppAttributeGroup group1,
            IppAttributeGroup group2 = null,
            IppAttributeGroup group3 = null)
        {
            // No duplicate needed.
            if (destinationGroup.Attributes.ContainsKey(attributeName))
            {
                return true;
            }

            if (group1 != null && group1.Attributes.ContainsKey(attributeName))
            {
                destinationGroup.AddAttribute(group1.Attributes[attributeName]);
                return true;
            }
            else if (group2 != null && group2.Attributes.ContainsKey(attributeName))
            {
                destinationGroup.AddAttribute(group2.Attributes[attributeName]);
                return true;
            }
            else if (group3 != null && group3.Attributes.ContainsKey(attributeName))
            {
                destinationGroup.AddAttribute(group3.Attributes[attributeName]);
                return true;
            }

            return false;
        }

        /// <summary>
        /// Returns the attribute value from either group 1, 2 or 3 to the target attribute group.
        /// </summary>
        /// <param name="attributeName">The name of the attribute.</param>
        /// <param name="group1">Attribute group 1.</param>
        /// <param name="group2">Attribute group 2.</param>
        /// <param name="group3">Attribute group 3.</param>
        /// <returns>Returns the attribute value if found, null otherwise.</returns>
        public static IppAttribute GetAttribute(
            string attributeName,
            IppAttributeGroup group1,
            IppAttributeGroup group2 = null,
            IppAttributeGroup group3 = null)
        {
            if (group1 != null && group1.Attributes.ContainsKey(attributeName))
            {
                return group1.Attributes[attributeName];
            }
            else if (group2 != null && group2.Attributes.ContainsKey(attributeName))
            {
                return group2.Attributes[attributeName];
            }
            else if (group3 != null && group3.Attributes.ContainsKey(attributeName))
            {
                return group3.Attributes[attributeName];
            }

            return null;
        }

        /// <summary>
        /// Return true if date time is default value.
        /// </summary>
        public static bool IsDefaultDateTime(DateTime dateTime)
        {
            var isDefault = dateTime == DateTime.MinValue.ToUniversalTime();
            return isDefault;
        }

        /// <summary>
        /// Default date time.
        /// </summary>
        public static DateTime GetDefaultDateTime()
        {
            var defaultTime = DateTime.MinValue.ToUniversalTime();
            return defaultTime;
        }

        public static string GetDefaultDateTimeString()
        {
            var defaultTime = DateTime.MinValue.ToUniversalTime().ToString("o", CultureInfo.InvariantCulture);
            return defaultTime;
        }

        /// <summary>
        /// Return current time in UTC.
        /// </summary>
        public static DateTime GetCurrentTimeUtc()
        {
            return DateTime.UtcNow;
        }

        /// <summary>
        /// Return current time in UTC.
        /// </summary>
        public static string GetCurrentTimeUtcString()
        {
            return DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture);
        }

        /// <summary>
        /// Parse dateTimeString to DateTime. Return default time if unsuccessfull (e.g., for older data).
        /// </summary>
        public static DateTime ParseDateTime(string dateTimeString)
        {
            // See https://docs.microsoft.com/en-us/dotnet/standard/base-types/standard-date-and-time-format-strings?view=netframework-4.7.2 for the "o" format.
            // Example dateTimeString: "2018-12-10T06:58:21.0075545Z".
            if (!DateTime.TryParse(dateTimeString, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out DateTime dateTimeToReturn))
            {
                dateTimeToReturn = GetDefaultDateTime();
            }

            return dateTimeToReturn;
        }

        /// <summary>
        /// Calculate the numbers of seconds from time1 to time2.
        /// </summary>
        public static int CalculateSecondsSince(DateTime time1, DateTime time2)
        {
            var timeSpan = time2 - time1;
            return (int)timeSpan.TotalSeconds;
        }

        /// <summary>
        /// Returns true if tag is for an attribute group.
        /// </summary>
        public static bool IsBeginAttributeGroupTag(Tag tag)
        {
            return (tag < Tag.Unsupported && tag >= Tag.Reserved) && tag != Tag.EndOfAttributes;
        }

        /// <summary>
        /// Returns true if tag is for an attribute.
        /// </summary>
        public static bool IsValueTag(Tag tag)
        {
            return tag >= Tag.Unsupported;
        }

        /// <summary>
        /// Returns true if tag is for a begin collection attribute tag.
        /// https://tools.ietf.org/html/rfc8010#section-3.1.6
        /// </summary>
        public static bool IsBeginCollectionValueTag(Tag tag)
        {
            return tag == Tag.BegCollection;
        }

        /// <summary>
        /// Returns true if tag is for member attribute tag.
        /// </summary>
        public static bool IsMemberAttrNameTag(Tag tag)
        {
            return tag == Tag.MemberAttrName;
        }

        /// <summary>
        /// Create a new uri object.
        /// </summary>
        /// <param name="uriString">The string representation of the uri.</param>
        /// <returns>Newly created uri object.</returns>
        public static Uri CreateUri(string uriString)
        {
            try
            {
                return new Uri(uriString);
            }
            catch
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, "Invalid uri: " + uriString);
            }
        }

        /// <summary>
        /// Create a new uri object.
        /// </summary>
        /// <param name="uri">Base uri.</param>
        /// <param name="segments">Additional segments.</param>
        /// <returns>Newly created uri object.</returns>
        public static Uri CreateUri(Uri uri, string segments)
        {
            try
            {
                return new Uri(uri, segments);
            }
            catch
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, "Invalid uri: " + uri.ToString() + ". segments: " + segments);
            }
        }

        /// <summary>
        /// Throw if the printerUri is invalid.
        /// </summary>
        /// <param name="printerUri">Printer uri, usually from printer-uri attribute.</param>
        public static void IsValidPrinterUri(Uri printerUri)
        {
            const string printersSegment = "printers/";

            // Example of correct printer-uri: ipps://localhost:44336/printers/8b518e16-2d2b-11e8-b467-0ed5f89f718b.
            // Segments:  [0] "/"
            //            [1] "printers/"
            //            [2] "810a8958-13f4-4044-a09b-a372e8990a6b/"
            if (printerUri.Segments.Length != 3 ||
                string.Compare(printerUri.Segments[1], printersSegment, StringComparison.OrdinalIgnoreCase) != 0)
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, "Invalid printer-uri: " + printerUri.ToString());
            }
        }

        /// <summary>
        /// Throw if jobUri is not valid.
        /// </summary>
        /// <param name="jobUri">The uri of a job.</param>
        public static void IsValidJobUri(Uri jobUri)
        {
            const string printersSegment = "printers/";
            const string jobUriSegment = "jobs/";

            // Example of correct job-uri: ipps://localhost:44336/printers/810a8958-13f4-4044-a09b-a372e8990a6b/jobs/388
            // Segments:  [0] "/"
            //            [1] "printers/"
            //            [2] "810a8958-13f4-4044-a09b-a372e8990a6b/"
            //            [3] "jobs/"
            //            [4] "388"
            if (jobUri.Segments.Length != 5 ||
                string.Compare(jobUri.Segments[1], printersSegment, StringComparison.OrdinalIgnoreCase) != 0 ||
                string.Compare(jobUri.Segments[3], jobUriSegment, StringComparison.OrdinalIgnoreCase) != 0)
            {
                throw new IPPException(StatusCode.ClientErrorBadRequest, "Invalid job-uri: " + jobUri.ToString());
            }
        }

        /// <summary>
        /// See comments above
        /// </summary>
        /// <param name="array">array</param>
        /// <returns>string representation of b</returns>
        public static string ByteArrayToAsciiString(byte[] array)
        {
            StringBuilder sb = new StringBuilder();

            for (int i = 0; i < array.Length; i++)
            {
                sb.Append((char)array[i]);
            }

            return sb.ToString();
        }

        /// <summary>
        /// Retrieve the system uptime.  RFC2911 4.3.14.4 specifies job-printer-up-time as an integer (giving us 68 years of resolution)
        /// </summary>
        /// <returns>time as integer</returns>
        public static int GetSystemUptime()
        {
            return System.Environment.TickCount;
        }

        public static IppAttributeGroup CreateOperationAttributes()
        {
            var operationAttributes = new IppAttributeGroup(Tag.OperationAttributes);

            // Add required operation attributes
            operationAttributes.AddAttribute(new IppAttribute(OperationAttributes.AttributesCharset, IppValue.CreateCharsetValue(IppEncoding.CharSet)));
            operationAttributes.AddAttribute(new IppAttribute(OperationAttributes.AttributesNaturalLanguage, IppValue.CreateNaturalLanguageValue(Helpers.GetNaturalLanguage())));
            return operationAttributes;
        }

        public static IppAttributeGroup CreateSubscriptionAttributes()
        {
            var subscriptionAttributes = new IppAttributeGroup(Tag.SubscriptionAttributes);

            // Add required operation attributes
            subscriptionAttributes.AddAttribute(new IppAttribute(NotifyAttributes.NotifyCharset, IppValue.CreateCharsetValue(IppEncoding.CharSet)));
            subscriptionAttributes.AddAttribute(new IppAttribute(NotifyAttributes.NotifyNaturalLanguage, IppValue.CreateNaturalLanguageValue(Helpers.GetNaturalLanguage())));
            return subscriptionAttributes;
        }

        public static IppAttributeGroup CreateEventAttributes(int subscriptionId, string notifySubscribedEvent, int sequenceNumber, string notifyText)
        {
            var subscriptionAttributes = new IppAttributeGroup(Tag.EventNotificationAttributes);

            // Add required operation attributes
            subscriptionAttributes.AddAttribute(new IppAttribute(NotifyAttributes.NotifyCharset, IppValue.CreateCharsetValue(IppEncoding.CharSet)));
            subscriptionAttributes.AddAttribute(new IppAttribute(NotifyAttributes.NotifyNaturalLanguage, IppValue.CreateNaturalLanguageValue(Helpers.GetNaturalLanguage())));
            subscriptionAttributes.AddAttribute(new IppAttribute(NotifyAttributes.NotifySubscriptionId, IppValue.CreateIntegerValue(subscriptionId)));
            subscriptionAttributes.AddAttribute(new IppAttribute(NotifyAttributes.NotifySubscribedEvent, IppValue.CreateKeywordValue(notifySubscribedEvent)));
            subscriptionAttributes.AddAttribute(new IppAttribute(NotifyAttributes.NotifySequenceNumber, IppValue.CreateIntegerValue(sequenceNumber)));
            subscriptionAttributes.AddAttribute(new IppAttribute(NotifyAttributes.NotifyText, IppValue.CreateNameWithoutLanguageValue(notifyText)));
            return subscriptionAttributes;
        }

        // See https://ftp.pwg.org/pub/pwg/ipp/registrations/apple-printer-firmware-20190724.txt
        public static byte[] FirmwareStringVersionToFirmwareVersion(string version)
        {
            var versionBytes = new List<byte>() { 0 };
            foreach (var c in version)
            {
                if (byte.TryParse(c.ToString(), out var b))
                {
                    versionBytes.Add(b);
                }
                else
                {
                    versionBytes.Add(0);
                }
            }

            return versionBytes.ToArray();
        }
    }
}