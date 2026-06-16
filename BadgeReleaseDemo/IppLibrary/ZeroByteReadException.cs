//-----------------------------------------------------------------------
// <copyright file="ZeroByteReadException.cs" company="Microsoft">
// Copyright (c) Microsoft. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

namespace BadgeReleaseDemo.IppLibrary
{
    using System;

    /// <summary>
    /// ZeroByteReadException is expected to be thrown  when the initial read from the stream returns 0 bytes
    /// </summary>
    public class ZeroByteReadException : Exception
    {
        public ZeroByteReadException(string message)
            : base(message)
        {
        }
    }
}
