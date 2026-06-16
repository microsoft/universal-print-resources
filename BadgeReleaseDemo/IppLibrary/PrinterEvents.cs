// <copyright file="PrinterEvents.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

namespace BadgeReleaseDemo.IppLibrary
{
    public class PrinterEvents
    {
        public const string PrinterStateChanged = "printer-state-changed";
        public const string PrinterRestarted = "printer-restarted";
        public const string PrinterShutdown = "printer-shutdown";
        public const string PrinterStopped = "printer-stopped";
        public const string PrinterConfigChanged = "printer-config-changed";
        public const string PrinterMediaChanged = "printer-media-changed";
        public const string PrinterFinishingsChanged = "printer-finishings-changed";
        public const string PrinterQueueorderChanged = "printer-queue-order-changed";
    }
}