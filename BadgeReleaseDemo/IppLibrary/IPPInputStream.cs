//-----------------------------------------------------------------------
// <copyright file="IPPInputStream.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

namespace BadgeReleaseDemo.IppLibrary
{
    using System;
    using System.IO;
    using System.Text;
    using System.Threading;
    using System.Threading.Tasks;

    public class IPPInputStream : IDisposable
    {
        public IPPInputStream(Stream inputStream)
        {
            this.Stream = inputStream;
            this.BytesRead = 0;
        }

        public long BytesRead { get; private set; }

        // would have preferred to keep Stream as private variable, however, need to keep this as public 'get' because it is assigned to IPPRequest.Data for reading print document payload
        public Stream Stream { get; private set; }

        public void Dispose()
        {
            if (this.Stream != null)
            {
                this.Stream.Dispose();
                this.Stream = null;
            }
        }

        public async Task<short> ReadNetworkShortAsync(CancellationToken cancellationToken)
        {
            var buffer = await this.ReadInternalAsync(sizeof(short), cancellationToken);
            return (short)((buffer[0] << 8) | buffer[1]);
        }

        public async Task<int> ReadNetworkIntegerAsync(CancellationToken cancellationToken)
        {
            byte[] buffer = await this.ReadInternalAsync(sizeof(Int32), cancellationToken);
            return (int)((buffer[0] << 24) | (buffer[1] << 16) | (buffer[2] << 8) | buffer[3]);
        }

        public async Task<Tag> ReadTagAsync(CancellationToken cancellationToken)
        {
            try
            {
                byte[] buffer = await this.ReadInternalAsync(sizeof(byte), cancellationToken);
                return (Tag)buffer[0];
            }
            catch (InvalidDataException)
            {
                // mocking the behavior for (Tag)input.ReadByte() when end of stream is reached
                return (Tag)(-1);
            }
        }

        public async Task<sbyte> ReadSbyteAsync(CancellationToken cancellationToken)
        {
            var buffer = await this.ReadInternalAsync(sizeof(sbyte), cancellationToken);
            return (sbyte)buffer[0];
        }

        /// <summary>
        /// Reads an IPP string (ANSI) from the stream.
        /// </summary>
        /// <param name="length"></param>
        /// <param name="s"></param>
        /// <returns></returns>
        public async Task<string> ReadStringAsync(int length, CancellationToken cancellationToken)
        {
            StringBuilder sb = new StringBuilder();

            byte[] buffer = await this.ReadInternalAsync(length, cancellationToken);

            for (int i = 0; i < length; i++)
            {
                sb.Append((char)buffer[i]);
            }

            return sb.ToString();
        }

        public async Task<byte[]> ReadAsync(int count, CancellationToken cancellationToken)
        {
            return await this.ReadInternalAsync(count, cancellationToken);
        }

        /// <summary>
        /// see: ReadNumberOfBytesOrEndOfStreamInternalAsync()
        /// </summary>
        public async Task<byte[]> ReadNumberOfBytesOrEndOfStreamAsync(int count, CancellationToken cancellationToken)
        {
            byte[] buffer = new byte[count];
            return await this.ReadNumberOfBytesOrEndOfStreamInternalAsync(buffer, cancellationToken);
        }

        /// <summary>
        /// Reads the stream and creates a buffer with a maximum of given number of bytes
        /// </summary>
        /// <param name="buffer">Caller provided buffer.</param>
        /// <param name="cancellationToken">Cancellation token</param>
        /// <returns>Byte array with the content read from buffer</returns>
        public async Task<byte[]> ReadNumberOfBytesOrEndOfStreamAsync(byte[] buffer, CancellationToken cancellationToken)
        {
            return await this.ReadNumberOfBytesOrEndOfStreamInternalAsync(buffer, cancellationToken);
        }

        /// <summary>
        /// Reads a give number of bytes from the stream
        /// </summary>
        /// <param name="count">Number of bytes to be read.</param>
        /// <param name="cancellationToken">Cancellation token</param>
        /// <returns>Byte array with the content read from buffer</returns>
        private async Task<byte[]> ReadInternalAsync(int count, CancellationToken cancellationToken)
        {
            int bytesLeftToRead = count;
            byte[] buffer = new byte[count];
            var bytesRead = 0;
            while (bytesLeftToRead > 0)
            {
                bytesRead = await this.Stream.ReadAsync(buffer, count - bytesLeftToRead, bytesLeftToRead, cancellationToken);

                if (bytesRead == bytesLeftToRead)
                {
                    break;
                }
                else if (bytesRead > 0)
                {
                    bytesLeftToRead -= bytesRead;
                }
                else
                {
                    throw new InvalidDataException("Buffer returned 0 bytes");
                }
            }

            this.BytesRead += count;
            return buffer;
        }

        /// <summary>
        /// Reads the stream and creates a buffer with a maximum of given number of bytes
        /// </summary>
        /// <param name="buffer">Caller provided buffer.</param>
        /// <param name="cancellationToken">Cancellation token</param>
        /// <returns>Byte array with the content read from buffer</returns>
        private async Task<byte[]> ReadNumberOfBytesOrEndOfStreamInternalAsync(byte[] buffer, CancellationToken cancellationToken)
        {
            int count = buffer.Length;
            int bytesLeftToRead = count;
            var bytesRead = 0;
            var totalBytesRead = 0;
            while (bytesLeftToRead > 0)
            {
                bytesRead = await this.Stream.ReadAsync(buffer, count - bytesLeftToRead, bytesLeftToRead, cancellationToken);
                totalBytesRead += bytesRead;

                if (bytesRead == bytesLeftToRead)
                {
                    break;
                }
                else if (bytesRead > 0)
                {
                    bytesLeftToRead -= bytesRead;
                }
                else
                {
                    Array.Resize(ref buffer, totalBytesRead);
                    break;
                }
            }

            this.BytesRead += totalBytesRead;
            return buffer;
        }
    }
}
