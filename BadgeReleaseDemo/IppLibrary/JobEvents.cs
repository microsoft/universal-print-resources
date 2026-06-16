// <copyright file="JobEvents.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

namespace BadgeReleaseDemo.IppLibrary
{
    public class JobEvents
    {
        public const string JobStateChanged = "job-state-changed";
        public const string JobCreated = "job-created";
        public const string JobCompleted = "job-completed";
        public const string JobStopped = "job-stopped";
        public const string JobConfigChanged = "job-config-changed";
        public const string JobProgress = "job-progress";
        public const string JobFetchable = "job-fetchable";
    }
}