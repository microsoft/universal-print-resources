//-----------------------------------------------------------------------
// <copyright file="IPPDatatypes.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>
//-----------------------------------------------------------------------

// These are all types/strings/etc defined in the IPP RFCs. Look there for info.
#pragma warning disable SA1602 // Enumeration items should be documented
#pragma warning disable SA1600 // elements should be documented

namespace BadgeReleaseDemo.IppLibrary
{
    /// <summary>
    /// From RFC 2911:
    ///
    /// 0x0000              reserved, not used
    /// 0x0001              reserved, not used
    /// 0x0002              Print-Job
    /// 0x0003              Print-URI
    /// 0x0004              Validate-Job
    /// 0x0005              Create-Job
    /// 0x0006              Send-Document
    /// 0x0007              Send-URI
    /// 0x0008              Cancel-Job
    /// 0x0009              Get-Job-Attributes
    /// 0x000A              Get-Jobs
    /// 0x000B              Get-Printer-Attributes
    /// 0x000C              Hold-Job
    /// 0x000D              Release-Job
    /// 0x000E              Restart-Job
    /// 0x000F              reserved for a future operation
    /// 0x0010              Pause-Printer
    /// 0x0011              Resume-Printer
    /// 0x0012              Purge-Jobs
    ///
    /// For IPP INFRA
    /// From: http://ftp.pwg.org/pub/pwg/candidates/cs-ippinfra10-20150619-5100.18.pdf (section 14.4)
    ///
    /// 0x003f              Acknowledge-Document
    /// 0x0040              Acknowledge-Identity-Printer
    /// 0x0041              Acknowledge-Job
    /// 0x0042              Fetch-Document
    /// 0x0043              Fetch-Job
    /// 0x0044              Get-Output-Device-Attributes
    /// 0x0045              Update-Active-Jobs
    /// 0x0046              Deregister-Output-Device
    /// 0x0047              Update-Document-Status
    /// 0x0048              Update-Job-Status
    /// 0x0049              Update-Output-Device-Attributes
    ///
    /// For IPP Job Extensions v2.0
    /// From: https://ftp.pwg.org/pub/pwg/candidates/cs-ippjobext20-20190816-5100.7.pdf (section 4)
    ///
    /// 0x003A              CloseJob
    ///
    /// 0x0013-0x3FFF       reserved for future IETF standards track
    ///                      operations (see section 6.4)
    /// 0x4000-0x8FFF       reserved for vendor extensions (see section 6.4)
    /// </summary>
    public enum Operation
    {
        // IPP
        PrintJob = 0x2,
        PrintUri = 0x3,
        ValidateJob = 0x4,
        CreateJob = 0x5,
        SendDocument = 0x6,
        SendUri = 0x7,
        CancelJob = 0x8,
        GetJobAttributes = 0x9,
        GetJobs = 0xA,
        GetPrinterAttributes = 0xB,
        HoldJob = 0xC,
        ReleaseJob = 0xD,
        RestartJob = 0xE,
        PausePrinter = 0x10,
        ResumePrinter = 0x11,
        PurgeJobs = 0x12,

        // Job/Printer Set operations https://tools.ietf.org/html/rfc3380#section-4
        SetPrinterAttributes = 0x13,
        SetJobAttributes = 0x14,
        GetPrinterSupportedValues = 0x15,

        // IPP INFRA (from: http://ftp.pwg.org/pub/pwg/candidates/cs-ippinfra10-20150619-5100.18.pdf section 14.3).
        CreatePrinterSubscriptions = 0x16,
        CreateJobSubscriptions = 0x17,
        GetSubscriptionAttributes = 0x18,
        GetSubscriptions = 0x19,
        RenewSubscription = 0x1A,
        CancelSubscription = 0x1B,
        GetNotifications = 0x1C,
        AcknowledgeDocument = 0x3F,
        AcknowledgeIdentityPrinter = 0x40,  /* not used in IPP Infra */
        AcknowledgeJob = 0x41,
        FetchDocument = 0x42,
        FetchJob = 0x43,
        GetOutputDeviceAttributes = 0x44,
        UpdateActiveJobs = 0x45,
        DeregisterOutputDevice = 0x46,
        UpdateDocumentStatus = 0x47,
        UpdateJobStatus = 0x48,
        UpdateOutputDeviceAttributes = 0x49,

        // IPP Job Extensions v2.0 (from: https://ftp.pwg.org/pub/pwg/candidates/cs-ippjobext20-20190816-5100.7.pdf section 4).
        CloseJob = 0x3A,

        // Custom Windows IPP Extensions for IPP.
        GetPrintDeviceCapabilities = 0x5000,
        GetPrintDeviceResources = 0x5001,

        // Custom Windows IPP Extensions for IPP Infra.
        SetPrintDeviceCapabilities = 0x5100,
        SetPrintCapabilities = 0x5101
    }

    public enum PrinterState
    {
        Idle = 3,
        Processing = 4,
        Stopped = 5,
    }

    public enum Orientation
    {
        Portrait = 3,
        Landscape = 4,
        ReverseLandscape = 5,
        ReversePortrait = 6,
        None = 7
    }

    public enum JobState
    {
        Pending = 3,
        PendingHeld = 4,
        Processing = 5,
        ProcessingStopped = 6,
        Canceled = 7,
        Aborted = 8,
        Completed = 9
    }

    // RFC 8011 section 5.2.13.
    public enum PrintQuality
    {
        Draft = 3,
        Normal = 4,
        High = 5
    }

    // https://tools.ietf.org/html/rfc8011#page-115 and PWG5100.1.
    public enum Finishings
    {
        None = 3,
        Staple = 4,
        Punch = 5,
        Cover = 6,
        Bind = 7,
        SaddleStitch = 8,
        EdgeStitch = 9,
        Fold = 10,
        Trim = 11,
        Bale = 12,
        BookletMaker = 13,
        JogOffset = 14,
        Coat = 15,
        Laminate = 16,
        StapleTopLeft = 20,
        StapleBottomLeft = 21,
        StapleTopRight = 22,
        StapleBottomRight = 23,
        EdgeStitchLeft = 24,
        EdgeStitchTop = 25,
        EdgeStitchRight = 26,
        EdgeStitchBottom = 27,
        StapleDualLeft = 28,
        StapleDualTop = 29,
        StapleDualRight = 30,
        StapleDualBottom = 31,
        StapleTripleLeft = 32,
        StapleTripleTop = 33,
        StapleTripleRight = 34,
        StapleTripleBottom = 35,
        BindLeft = 50,
        BindTop = 51,
        BindRight = 52,
        BindBottom = 53,
        TrimAfterPages = 60,
        TrimAfterDocuments = 61,
        TrimAfterCopies = 62,
        TrimAfterJob = 63,
        PunchTopLeft = 70,
        PunchBottomLeft = 71,
        PunchTopRight = 72,
        PunchBottomRight = 73,
        PunchDualLeft = 74,
        PunchDualTop = 75,
        PunchDualRight = 76,
        PunchDualBottom = 77,
        PunchTripleLeft = 78,
        PunchTripleTop = 79,
        PunchTripleRight = 80,
        PunchTripleBottom = 81,
        PunchQuadLeft = 82,
        PunchQuadTop = 83,
        PunchQuadRight = 84,
        PunchQuadBottom = 85,
        PunchMultipleLeft = 86,
        PunchMultipleTop = 87,
        PunchMultipleRight = 88,
        PunchMultipleBottom = 89,
        FoldAccordion = 90,
        FoldDoubleGate = 91,
        FoldGate = 92,
        FoldHalf = 93,
        FoldHalfZ = 94,
        FoldLeftGate = 95,
        FoldLetter = 96,
        FoldParallel = 97,
        FoldPoster = 98,
        FoldRightGate = 99,
        FoldZ = 100,
        FoldEngineeringZ = 101,
    }

    /// <summary>
    /// Describes the standard IPP status codes
    /// </summary>
    public enum StatusCode
    {
        // Success codes (0x0000-0x00ff)
        SuccessfulOk = 0x0000,
        SuccessfulOkIgnoredOrSubstitutedAttributes = 0x0001,
        SuccessfulOkConflictingAttributes = 0x0002,
        SuccessfulOkIgnoredSubscriptions = 0x0003,
        SuccessfulOkTooManyEvents = 0x0005,
        SuccessfulOkMax = 0x00ff,

        // Client error status codes
        // (used '[when] the client seems to have erred.')
        ClientErrorBadRequest = 0x0400,
        ClientErrorForbidden = 0x0401,
        ClientErrorNotAuthenticated = 0x0402,
        ClientErrorNotAuthorized = 0x0403,
        ClientErrorNotPossible = 0x0404,
        ClientErrorTimeout = 0x0405,
        ClientErrorNotFound = 0x0406,
        ClientErrorGone = 0x0407,
        ClientErrorRequestEntityTooLarge = 0x0408,
        ClientErrorRequestValueTooLong = 0x0409,
        ClientErrorDocumentFormatNotSupported = 0x040a,
        ClientErrorAttributesOrValuesNotSupported = 0x040b,
        ClientErrorUriSchemeNotSupported = 0x040c,
        ClientErrorCharsetNotSupported = 0x040d,
        ClientErrorConflictingAttributes = 0x040e,
        ClientErrorCompressionNotSupported = 0x040f,
        ClientErrorCompressionError = 0x0410,
        ClientErrorDocumentFormatError = 0x0411,
        ClientErrorDocumentAccessError = 0x0412,
        ClientErrorIgnoredAllSubscriptions = 0x0414,
        ClientErrorTooManySubscriptions = 0x0415,

        // Server error status codes
        // (used '[when] the IPP object is aware that it has erred or is incapable of performing the request.')
        ServerErrorInternalError = 0x0500,
        ServerErrorOperationNotSupported = 0x0501,
        ServerErrorServiceUnavailable = 0x0502,
        ServerErrorVersionNotSupported = 0x0503,
        ServerErrorDeviceError = 0x0504,
        ServerErrorTemporaryError = 0x0505,
        ServerErrorNotAcceptingJobs = 0x0506,
        ServerErrorBusy = 0x0507,
        ServerErrorJobCanceled = 0x0508,
        ServerErrorMultipleDocumentJobsNotSupported = 0x0509,

        // Note: this is only for internal consumption when status code is unknown.
        Undefined = 0xffff
    }

    // Section 13.3.1 of AirPrint Specification Version 2.1.1 (not publicly available, see team sharepoint)
    public enum LandscapeOrientationRequestedPreferred
    {
        NinetyDegreesCounterClockwise = 4,
        NinetyDegreesClockwise = 5
    }

    // RFC 8011 section 5.2.8: sides.
    public struct Sides
    {
        public const string OneSided = "one-sided";
        public const string TwoSidedShortEdge = "two-sided-short-edge";
        public const string TwoSidedLongEdge = "two-sided-long-edge";
    }

    // PWG 5100.13 print-color-mode.
    public struct ColorModes
    {
        public const string Auto = "auto";
        public const string BiLevel = "bi-level";
        public const string Color = "color";
        public const string Highlight = "highlight";
        public const string Monochrome = "monochrome";
        public const string ProcessBiLevel = "process-bi-level";
        public const string ProcessMonochrome = "process-monochrome";
        public const string MicrosoftGrayscaleOnly = "microsoft-grayscale-only"; // Custom. Used for grayscale-only Connector printers to show only grayscale option in PDC and print dialog.
        public const string MicrosoftMonochromeOnly = "microsoft-monochrome-only"; // Custom. Used for monochrome-only Connector printers to show only monochrome option in PDC and print dialog.
    }

    // PWG 5100.16 section 6.2.2. print-scaling values.
    public struct PrintScaling
    {
        public const string Auto = "auto";
        public const string AutoFit = "auto-fit";
        public const string Fill = "fill";
        public const string Fit = "fit";
        public const string None = "none";
    }

    // Keywords for media-front-coating and media-back-coating.
    // https://ftp.pwg.org/pub/pwg/candidates/cs-ippprodprint10-20010212-5100.3.pdf. Section 3.13.10.
    public struct MediaCoating
    {
        public const string None = "none";
        public const string Glossy = "glossy";
        public const string HighGloss = "high-gloss";
        public const string SemiGloss = "semi-gloss";
        public const string Satin = "satin";
        public const string Matte = "matte";
    }

    // Keywords for media-color.
    // https://ftp.pwg.org/pub/pwg/candidates/cs-ippprodprint10-20010212-5100.3.pdf. Section 3.13.4.
    public struct MediaColors
    {
        public const string NoColor = "no-color";
        public const string White = "white";
        public const string Pink = "pink";
        public const string Yellow = "yellow";
        public const string Blue = "blue";
        public const string Green = "green";
        public const string Buff = "buff";
        public const string GoldenRod = "goldenrod";
        public const string Red = "red";
        public const string Gray = "gray";
        public const string Ivory = "ivory";
        public const string Orange = "orange";
    }

    // Keywords for multiple-document-handling
    public struct MultipleDocumentHandling
    {
        public const string SeparateDocumentsCollatedCopies = "separate-documents-collated-copies";
        public const string SeparateDocumentsUncollatedCopies = "separate-documents-uncollated-copies";
        public const string SingleDocument = "single-document";
        public const string SingleDocumentNewSheet = "single-document-new-sheet";
    }

    // https://ftp.pwg.org/pub/pwg/candidates/cs-ippprodprint10-20010212-5100.3.pdf Table 13.
    public struct PresentationDirections
    {
        public const string ToRightToBottom = "toright-tobottom";
        public const string ToBottomToRight = "tobottom-toright";
        public const string ToLeftToBottom = "toleft-tobottom";
        public const string ToBottomToLeft = "tobottom-toleft";
        public const string ToRightToTop = "toright-totop";
        public const string ToTopToRight = "totop-toright";
        public const string ToLeftToTop = "toleft-totop";
        public const string ToTopToLeft = "totop-toleft";
    }

    /// <summary>
    /// Media Size Self-Describing Names
    /// https://ftp.pwg.org/pub/pwg/candidates/cs-pwgmsn10-20020226-5101.1.pdf section 5.
    /// </summary>
    public struct MediaSizeNames
    {
        // ASME sizes
        public const string AsmeF = "asme_f_28x40in";

        // ISO A series
        public const string Iso2A0 = "iso_2a0_1189x1682mm";
        public const string IsoA0 = "iso_a0_841x1189mm";
        public const string IsoA1 = "iso_a1_594x841mm";
        public const string IsoA1x3 = "iso_a1x3_841x1783mm";
        public const string IsoA1x4 = "iso_a1x4_841x2378mm";
        public const string IsoA2 = "iso_a2_420x594mm";
        public const string IsoA2x3 = "iso_a2x3_594x1261mm";
        public const string IsoA2x4 = "iso_a2x4_594x1682mm";
        public const string IsoA2x5 = "iso_a2x5_594x2102mm";
        public const string IsoA3 = "iso_a3_297x420mm";
        public const string IsoA3Extra = "iso_a3-extra_322x445mm";
        public const string IsoA0x3 = "iso_a0x3_1189x2523mm";
        public const string IsoA3x3 = "iso_a3x3_420x891mm";
        public const string IsoA3x4 = "iso_a3x4_420x1189mm";
        public const string IsoA3x5 = "iso_a3x5_420x1486mm";
        public const string IsoA3x6 = "iso_a3x6_420x1783mm";
        public const string IsoA3x7 = "iso_a3x7_420x2080mm";
        public const string IsoA4Extra = "iso_a4-extra_235.5x322.3mm";
        public const string IsoA4Tab = "iso_a4-tab_225x297mm";
        public const string IsoA4 = "iso_a4_210x297mm";
        public const string IsoA4x3 = "iso_a4x3_297x630mm";
        public const string IsoA4x4 = "iso_a4x4_297x841mm";
        public const string IsoA4x5 = "iso_a4x5_297x1051mm";
        public const string IsoA4x6 = "iso_a4x6_297x1261mm";
        public const string IsoA4x7 = "iso_a4x7_297x1471mm";
        public const string IsoA4x8 = "iso_a4x8_297x1682mm";
        public const string IsoA4x9 = "iso_a4x9_297x1892mm";
        public const string IsoA5Extra = "iso_a5-extra_174x235mm";
        public const string IsoA5 = "iso_a5_148x210mm";
        public const string IsoA6 = "iso_a6_105x148mm";
        public const string IsoA7 = "iso_a7_74x105mm";
        public const string IsoA8 = "iso_a8_52x74mm";
        public const string IsoA9 = "iso_a9_37x52mm";
        public const string IsoA10 = "iso_a10_26x37mm";

        // ISO B series
        public const string IsoB0 = "iso_b0_1000x1414mm";
        public const string IsoB1 = "iso_b1_707x1000mm";
        public const string IsoB2 = "iso_b2_500x707mm";
        public const string IsoB3 = "iso_b3_353x500mm";
        public const string IsoB4 = "iso_b4_250x353mm";
        public const string IsoB5Extra = "iso_b5-extra_201x276mm";
        public const string IsoB5 = "iso_b5_176x250mm";
        public const string IsoB6 = "iso_b6_125x176mm";
        public const string IsoB6C4 = "iso_b6c4_125x324mm";
        public const string IsoB7 = "iso_b7_88x125mm";
        public const string IsoB8 = "iso_b8_62x88mm";
        public const string IsoB9 = "iso_b9_44x62mm";
        public const string IsoB10 = "iso_b10_31x44mm";

        // ISO C series (envelopes)
        public const string IsoC0 = "iso_c0_917x1297mm";
        public const string IsoC1LongEdge = "iso_c1-long-edge_917x648mm";
        public const string IsoC1 = "iso_c1_648x917mm";
        public const string IsoC2LongEdge = "iso_c2-long-edge_648x458mm";
        public const string IsoC2 = "iso_c2_458x648mm";
        public const string IsoC3LongEdge = "iso_c3-long-edge_458x324mm";
        public const string IsoC3 = "iso_c3_324x458mm";
        public const string IsoC4LongEdge = "iso_c4-long-edge_324x229mm";
        public const string IsoC4 = "iso_c4_229x324mm";
        public const string IsoC5LongEdge = "iso_c5-long-edge_229x162mm";
        public const string IsoC5 = "iso_c5_162x229mm";
        public const string IsoC6LongEdge = "iso_c6-long-edge_162x114mm";
        public const string IsoC6 = "iso_c6_114x162mm";
        public const string IsoC6C5 = "iso_c6c5_114x229mm";
        public const string IsoC7LongEdge = "iso_c7-long-edge_114x81mm";
        public const string IsoC7 = "iso_c7_81x114mm";
        public const string IsoC7C6 = "iso_c7c6_81x162mm";
        public const string IsoC8LongEdge = "iso_c8-long-edge_81x57mm";
        public const string IsoC8 = "iso_c8_57x81mm";
        public const string IsoC9LongEdge = "iso_c9-long-edge_57x40mm";
        public const string IsoC9 = "iso_c9_40x57mm";
        public const string IsoC10LongEdge = "iso_c10-long-edge_40x28mm";
        public const string IsoC10 = "iso_c10_28x40mm";
        public const string IsoDlLongEdge = "iso_dl-long-edge_220x110mm";
        public const string IsoDl = "iso_dl_110x220mm";

        // ISO RA series
        public const string IsoRa0 = "iso_ra0_860x1220mm";
        public const string IsoRa1 = "iso_ra1_610x860mm";
        public const string IsoRa2 = "iso_ra2_430x610mm";
        public const string IsoRa3 = "iso_ra3_305x430mm";
        public const string IsoRa4 = "iso_ra4_215x305mm";

        // ISO SRA series
        public const string IsoSra0 = "iso_sra0_900x1280mm";
        public const string IsoSra1 = "iso_sra1_640x900mm";
        public const string IsoSra2 = "iso_sra2_450x640mm";
        public const string IsoSra3 = "iso_sra3_320x450mm";
        public const string IsoSra4 = "iso_sra4_225x320mm";

        // ISO ID-1 (credit card size)
        public const string IsoId1 = "iso_id-1_53.98x85.6mm";

        // JIS B series
        public const string JisB0 = "jis_b0_1030x1456mm";
        public const string JisB1 = "jis_b1_728x1030mm";
        public const string JisB2 = "jis_b2_515x728mm";
        public const string JisB3 = "jis_b3_364x515mm";
        public const string JisB4 = "jis_b4_257x364mm";
        public const string JisB5 = "jis_b5_182x257mm";
        public const string JisB6 = "jis_b6_128x182mm";
        public const string JisB7 = "jis_b7_91x128mm";
        public const string JisB8 = "jis_b8_64x91mm";
        public const string JisB9 = "jis_b9_45x64mm";
        public const string JisB10 = "jis_b10_32x45mm";
        public const string JisExec = "jis_exec_216x330mm";

        // Japanese envelope and postcard sizes
        public const string JpnChou2 = "jpn_chou2_111.1x146mm";
        public const string JpnChou3 = "jpn_chou3_120x235mm";
        public const string JpnChou4 = "jpn_chou4_90x205mm";
        public const string JpnChou40 = "jpn_chou40_90x225mm";
        public const string JpnHagaki = "jpn_hagaki_100x148mm";
        public const string JpnKahu = "jpn_kahu_240x322.1mm";
        public const string JpnKaku1 = "jpn_kaku1_270x382mm";
        public const string JpnKaku2 = "jpn_kaku2_240x332mm";
        public const string JpnKaku3 = "jpn_kaku3_216x277mm";
        public const string JpnKaku4 = "jpn_kaku4_197x267mm";
        public const string JpnKaku5 = "jpn_kaku5_190x240mm";
        public const string JpnKaku7 = "jpn_kaku7_142x205mm";
        public const string JpnKaku8 = "jpn_kaku8_119x197mm";
        public const string JpnOufuku = "jpn_oufuku_148x200mm";
        public const string JpnYou1 = "jpn_you1_120x176mm";
        public const string JpnYou3 = "jpn_you3_98x148mm";
        public const string JpnYou4 = "jpn_you4_105x235mm";
        public const string JpnYou4LongEdge = "jpn_you4_235x105mm";
        public const string JpnYou5 = "jpn_you5_95x217mm";
        public const string JpnYou6 = "jpn_you6_98x190mm";
        public const string JpnYou7 = "jpn_you7_92x165mm";
        public const string JpnYouchou2 = "jpn_youchou2_146x111.1mm";
        public const string JpnYouchou3 = "jpn_youchou3_235x120mm";
        public const string JpnYouchou4 = "jpn_youchou4_205x90mm";

        // North American sizes
        public const string Na5x7 = "na_5x7_5x7in";
        public const string Na6x9 = "na_6x9_6x9in";
        public const string Na7x9 = "na_7x9_7x9in";
        public const string Na9x11 = "na_9x11_9x11in";
        public const string Na10x11 = "na_10x11_10x11in";
        public const string Na10x13 = "na_10x13_10x13in";
        public const string Na10x14 = "na_10x14_10x14in";
        public const string Na10x15 = "na_10x15_10x15in";
        public const string Na11x12 = "na_11x12_11x12in";
        public const string Na11x15 = "na_11x15_11x15in";
        public const string Na12x19 = "na_12x19_12x19in";
        public const string NaA2 = "na_a2_4.375x5.75in";
        public const string NaArchA = "na_arch-a_9x12in";
        public const string NaArchB = "na_arch-b_12x18in";
        public const string NaArchC = "na_arch-c_18x24in";
        public const string NaArchD = "na_arch-d_24x36in";
        public const string NaArchE2 = "na_arch-e2_26x38in";
        public const string NaArchE3 = "na_arch-e3_27x39in";
        public const string NaArchE = "na_arch-e_36x48in";
        public const string NaBPlus = "na_b-plus_12x19.17in";
        public const string NaC5 = "na_c5_6.5x9.5in";
        public const string NaC = "na_c_17x22in";
        public const string NaD = "na_d_22x34in";
        public const string NaE = "na_e_34x44in";
        public const string NaEdp = "na_edp_11x14in";
        public const string NaEurEdp = "na_eur-edp_12x14in";
        public const string NaExecutive = "na_executive_7.25x10.5in";
        public const string NaF = "na_f_44x68in";
        public const string NaFanfoldEur = "na_fanfold-eur_8.5x12in";
        public const string NaFanfoldUs = "na_fanfold-us_11x14.875in";
        public const string NaFoolscap = "na_foolscap_8.5x13in";
        public const string NaGovtLegal = "na_govt-legal_8x13in";
        public const string NaGovtLetter = "na_govt-letter_8x10in";
        public const string NaIndex3x5 = "na_index-3x5_3x5in";
        public const string NaIndex4x6Ext = "na_index-4x6-ext_6x8in";
        public const string NaIndex4x6 = "na_index-4x6_4x6in";
        public const string NaIndex5x8 = "na_index-5x8_5x8in";
        public const string NaInvoice = "na_invoice_5.5x8.5in";
        public const string NaLedger = "na_ledger_11x17in";
        public const string NaLegalExtra = "na_legal-extra_9.5x15in";
        public const string NaLegal = "na_legal_8.5x14in";
        public const string NaLetterExtra = "na_letter-extra_9.5x12in";
        public const string NaLetterPlus = "na_letter-plus_8.5x12.69in";
        public const string NaLetter = "na_letter_8.5x11in";
        public const string NaMonarchLongEdge = "na_monarch-long-edge_7.5x3.875in";
        public const string NaMonarch = "na_monarch_3.875x7.5in";
        public const string NaNumber9LongEdge = "na_number-9-long-edge_8.875x3.875in";
        public const string NaNumber9 = "na_number-9_3.875x8.875in";
        public const string NaNumber10LongEdge = "na_number-10-long-edge_9.5x4.125in";
        public const string NaNumber10 = "na_number-10_4.125x9.5in";
        public const string NaNumber11LongEdge = "na_number-11-long-edge_10.375x4.5in";
        public const string NaNumber11 = "na_number-11_4.5x10.375in";
        public const string NaNumber12LongEdge = "na_number-12-long-edge_11x4.75in";
        public const string NaNumber12 = "na_number-12_4.75x11in";
        public const string NaNumber14LongEdge = "na_number-14-long-edge_11.5x5in";
        public const string NaNumber14 = "na_number-14_5x11.5in";
        public const string NaOficio = "na_oficio_8.5x13.4in";
        public const string NaPersonalLongEdge = "na_personal-long-edge_6.5x3.625in";
        public const string NaPersonal = "na_personal_3.625x6.5in";
        public const string NaQuarto = "na_quarto_8.5x10.83in";
        public const string NaSuperA = "na_super-a_8.94x14in";
        public const string NaSuperB = "na_super-b_13x19in";
        public const string NaWideFormat = "na_wide-format_30x42in";

        // Other sizes (oe_ prefix)
        public const string Oe12x16 = "oe_12x16_12x16in";
        public const string Oe13x22 = "oe_13x22_13x22in";
        public const string Oe14x17 = "oe_14x17_14x17in";
        public const string Oe18x22 = "oe_18x22_18x22in";
        public const string OeA2Plus = "oe_a2plus_17x24in";
        public const string OeBusinessCard = "oe_business-card_2x3.5in";
        public const string OePhoto10r = "oe_photo-10r_10x12in";
        public const string OePhoto12r = "oe_photo-12r_12x15in";
        public const string OePhoto14x18 = "oe_photo-14x18_14x18in";
        public const string OePhoto16r = "oe_photo-16r_16x20in";
        public const string OePhoto20r = "oe_photo-20r_20x24in";
        public const string OePhoto20x30 = "oe_photo-20x30_20x30in";
        public const string OePhoto22r = "oe_photo-22r_22x29.5in";
        public const string OePhoto22x28 = "oe_photo-22x28_22x28in";
        public const string OePhoto24r = "oe_photo-24r_24x31.5in";
        public const string OePhoto24x30 = "oe_photo-24x30_24x30in";
        public const string OePhoto30r = "oe_photo-30r_30x40in";
        public const string OePhotoL = "oe_photo-l_3.5x5in";
        public const string OmPhotoL = "om_photo-l_89x119mm";
        public const string OePhotoS8r = "oe_photo-s8r_8x12in";
        public const string OePhotoS10r = "oe_photo-s10r_10x15in";
        public const string OeSquarePhoto4x4 = "oe_square-photo_4x4in";
        public const string OeSquarePhoto5x5 = "oe_square-photo_5x5in";

        // Other metric sizes (om_ prefix)
        public const string Om16k184x260 = "om_16k_184x260mm";
        public const string Om16k195x270 = "om_16k_195x270mm";
        public const string OmBusinessCard55x85 = "om_business-card_55x85mm";
        public const string OmBusinessCard55x91 = "om_business-card_55x91mm";
        public const string OmCard = "om_card_54x86mm";
        public const string OmDaiPaKai = "om_dai-pa-kai_275x395mm";
        public const string OmDscPhoto = "om_dsc-photo_89x119mm";
        public const string OmFolioSp = "om_folio-sp_215x315mm";
        public const string OmFolio = "om_folio_210x330mm";
        public const string OmInvite = "om_invite_220x220mm";
        public const string OmItalian = "om_italian_110x230mm";
        public const string OmJuuroKuKai = "om_juuro-ku-kai_198x275mm";
        public const string OmLargePhoto = "om_large-photo_200x300mm";
        public const string OmMediumPhoto = "om_medium-photo_130x180mm";
        public const string OmPaKai = "om_pa-kai_267x389mm";
        public const string OmPhoto30x40 = "om_photo-30x40_300x400mm";
        public const string OmPhoto30x45 = "om_photo-30x45_300x450mm";
        public const string OmPhoto30x90 = "om_photo-30x90_300x900mm";
        public const string OmPhoto35x46 = "om_photo-35x46_350x460mm";
        public const string OmPhoto40x60 = "om_photo-40x60_400x600mm";
        public const string OmPhoto50x75 = "om_photo-50x75_500x750mm";
        public const string OmPhoto50x76 = "om_photo-50x76_500x760mm";
        public const string OmPhoto60x90 = "om_photo-60x90_600x900mm";
        public const string OmSmallPhoto = "om_small-photo_100x150mm";
        public const string OmSquarePhoto = "om_square-photo_89x89mm";
        public const string OmWidePhoto = "om_wide-photo_100x200mm";

        // PRC (People's Republic of China) sizes
        public const string Prc1 = "prc_1_102x165mm";
        public const string Prc2 = "prc_2_102x176mm";
        public const string Prc4 = "prc_4_110x208mm";
        public const string Prc6 = "prc_6_120x320mm";
        public const string Prc7 = "prc_7_160x230mm";
        public const string Prc8 = "prc_8_120x309mm";
        public const string Prc16k = "prc_16k_146x215mm";
        public const string Prc32k = "prc_32k_97x151mm";

        // ROC (Republic of China/Taiwan) sizes
        public const string Roc8k = "roc_8k_10.75x15.5in";
        public const string Roc16k = "roc_16k_7.75x10.75in";

        // other media sizes
        public const string Universal11x14LexmarkCustomSize = "oe_universal_11x14in";
    }

    /// <summary>
    /// keywords for media-source.
    /// https://ftp.pwg.org/pub/pwg/candidates/cs-ippjobprinterext3v10-20120727-5100.13.pdf section 7.6.5.
    /// </summary>
    public struct MediaSource
    {
        public const string Alternate = "alternate";
        public const string AlternateRoll = "alternate-roll";
        public const string Auto = "auto";
        public const string Bottom = "bottom";
        public const string ByPassTray = "by-pass-tray";
        public const string Center = "center";
        public const string Disc = "disc";
        public const string Envelope = "envelope";
        public const string Hagaki = "hagaki";
        public const string LargeCapacity = "large-capacity";
        public const string Left = "left";
        public const string Main = "main";
        public const string MainRoll = "main-roll";
        public const string Manual = "manual";
        public const string Middle = "middle";
        public const string Photo = "photo";
        public const string Rear = "rear";
        public const string Right = "right";
        public const string Roll1 = "roll-1";
        public const string Roll2 = "roll-2";
        public const string Roll3 = "roll-3";
        public const string Roll4 = "roll-4";
        public const string Roll5 = "roll-5";
        public const string Roll6 = "roll-6";
        public const string Roll7 = "roll-7";
        public const string Roll8 = "roll-8";
        public const string Roll9 = "roll-9";
        public const string Roll10 = "roll-10";
        public const string Side = "side";
        public const string Top = "top";
        public const string Tray1 = "tray-1";
        public const string Tray2 = "tray-2";
        public const string Tray3 = "tray-3";
        public const string Tray4 = "tray-4";
        public const string Tray5 = "tray-5";
        public const string Tray6 = "tray-6";
        public const string Tray7 = "tray-7";
        public const string Tray8 = "tray-8";
        public const string Tray9 = "tray-9";
        public const string Tray10 = "tray-10";
        public const string Tray11 = "tray-11";
        public const string Tray12 = "tray-12";
        public const string Tray13 = "tray-13";
        public const string Tray14 = "tray-14";
        public const string Tray15 = "tray-15";
        public const string Tray16 = "tray-16";
        public const string Tray17 = "tray-17";
        public const string Tray18 = "tray-18";
        public const string Tray19 = "tray-19";
        public const string Tray20 = "tray-20";
    }

    // keywords for media-type
    // https://ftp.pwg.org/pub/pwg/candidates/cs-ippprodprint10-20010212-5100.3.pdf section 3.13.2
    // https://ftp.pwg.org/pub/pwg/candidates/cs-pwgmsn10-20020226-5101.1.pdf section 3
    // https://ftp.pwg.org/pub/pwg/ipp/registrations/xerox-mediatypes-20201202.txt
    // https://www.iana.org/assignments/ipp-registrations/ipp-registrations.xhtml
    public struct MediaTypes
    {
        public const string Aluminum = "aluminum";
        public const string Auto = "auto";
        public const string BackPrintFilm = "back-print-film";
        public const string Cardboard = "cardboard";
        public const string Cardstock = "cardstock";
        public const string CardstockCoated = "cardstock-coated";
        public const string CardstockHeavyweight = "cardstock-heavyweight";
        public const string CardstockHeavyweightCoated = "cardstock-heavyweight-coated";
        public const string CardstockLightweight = "cardstock-lightweight";
        public const string CardstockLightweightCoated = "cardstock-lightweight-coated";
        public const string Cd = "cd";
        public const string Continuous = "continuous";
        public const string ContinuousLong = "continuous-long";
        public const string ContinuousShort = "continuous-short";
        public const string CorrugatedBoard = "corrugated-board";
        public const string Disc = "disc";
        public const string DiscGlossy = "disc-glossy";
        public const string DiscHighGloss = "disc-high-gloss";
        public const string DiscMatte = "disc-matte";
        public const string DiscSatin = "disc-satin";
        public const string DiscSemiGloss = "disc-semi-gloss";
        public const string DoubleWall = "double-wall";
        public const string DryFilm = "dry-film";
        public const string Dvd = "dvd";
        public const string EmbossingFoil = "embossing-foil";
        public const string EndBoard = "end-board";
        public const string Envelope = "envelope";
        public const string EnvelopeArchival = "envelope-archival";
        public const string EnvelopeBond = "envelope-bond";
        public const string EnvelopeCoated = "envelope-coated";
        public const string EnvelopeCotton = "envelope-cotton";
        public const string EnvelopeFine = "envelope-fine";
        public const string EnvelopeHeavyweight = "envelope-heavyweight";
        public const string EnvelopeInkjet = "envelope-inkjet";
        public const string EnvelopeLightweight = "envelope-lightweight";
        public const string EnvelopePlain = "envelope-plain";
        public const string EnvelopePreprinted = "envelope-preprinted";
        public const string EnvelopeWindow = "envelope-window";
        public const string Fabric = "fabric";
        public const string FabricArchival = "fabric-archival";
        public const string FabricGlossy = "fabric-glossy";
        public const string FabricHighGloss = "fabric-high-gloss";
        public const string FabricMatte = "fabric-matte";
        public const string FabricSemiGloss = "fabric-semi-gloss";
        public const string FabricWaterproof = "fabric-waterproof";
        public const string Film = "film";
        public const string FlexoBase = "flexo-base";
        public const string FlexoPhotoPolymer = "flexo-photo-polymer";
        public const string Flute = "flute";
        public const string Foil = "foil";
        public const string FullCutTabs = "full-cut-tabs";
        public const string Glass = "glass";
        public const string GlassColored = "glass-colored";
        public const string GlassOpaque = "glass-opaque";
        public const string GlassSurfaced = "glass-surfaced";
        public const string GlassTextured = "glass-textured";
        public const string GravureCylinder = "gravure-cylinder";
        public const string ImageSetterPaper = "image-setter-paper";
        public const string ImagingCylinder = "imaging-cylinder";
        public const string Labels = "labels";
        public const string LabelsColored = "labels-colored";
        public const string LabelsContinuous = "labels-continuous";
        public const string LabelsGlossy = "labels-glossy";
        public const string LabelsHeavyweight = "labels-heavyweight";
        public const string LabelsHighGloss = "labels-high-gloss";
        public const string LabelsInkjet = "labels-inkjet";
        public const string LabelsLightweight = "labels-lightweight";
        public const string LabelsMatte = "labels-matte";
        public const string LabelsPermanent = "labels-permanent";
        public const string LabelsSatin = "labels-satin";
        public const string LabelsSecurity = "labels-security";
        public const string LabelsSemiGloss = "labels-semi-gloss";
        public const string LaminatingFoil = "laminating-foil";
        public const string Letterhead = "letterhead";
        public const string Metal = "metal";
        public const string MetalGlossy = "metal-glossy";
        public const string MetalHighGloss = "metal-high-gloss";
        public const string MetalMatte = "metal-matte";
        public const string MetalSatin = "metal-satin";
        public const string MetalSemiGloss = "metal-semi-gloss";
        public const string MountingTape = "mounting-tape";
        public const string MultiLayer = "multi-layer";
        public const string MultiPartForm = "multi-part-form";
        public const string Other = "other";
        public const string Paper = "paper";
        public const string Photographic = "photographic";
        public const string PhotographicArchival = "photographic-archival";
        public const string PhotographicFilm = "photographic-film";
        public const string PhotographicGlossy = "photographic-glossy";
        public const string PhotographicHighGloss = "photographic-high-gloss";
        public const string PhotographicMatte = "photographic-matte";
        public const string PhotographicSatin = "photographic-satin";
        public const string PhotographicSemiGloss = "photographic-semi-gloss";
        public const string Plastic = "plastic";
        public const string PlasticArchival = "plastic-archival";
        public const string PlasticColored = "plastic-colored";
        public const string PlasticGlossy = "plastic-glossy";
        public const string PlasticHighGloss = "plastic-high-gloss";
        public const string PlasticMatte = "plastic-matte";
        public const string PlasticSatin = "plastic-satin";
        public const string PlasticSemiGloss = "plastic-semi-gloss";
        public const string Plate = "plate";
        public const string Polyester = "polyester";
        public const string PreCutTabs = "pre-cut-tabs";
        public const string Roll = "roll";
        public const string Screen = "screen";
        public const string ScreenPaged = "screen-paged";
        public const string SelfAdhesive = "self-adhesive";
        public const string SelfAdhesiveFilm = "self-adhesive-film";
        public const string ShrinkFoil = "shrink-foil";
        public const string SingleFace = "single-face";
        public const string SingleWall = "single-wall";
        public const string Sleeve = "sleeve";
        public const string Stationery = "stationery";
        public const string StationeryArchival = "stationery-archival";
        public const string StationeryBond = "stationery-bond";
        public const string StationeryCoated = "stationery-coated";
        public const string StationeryColored = "stationery-colored";
        public const string StationeryCotton = "stationery-cotton";
        public const string StationeryFine = "stationery-fine";
        public const string StationeryHeavyweight = "stationery-heavyweight";
        public const string StationeryHeavyweightCoated = "stationery-heavyweight-coated";
        public const string StationeryInkjet = "stationery-inkjet";
        public const string StationeryLetterhead = "stationery-letterhead";
        public const string StationeryLightweight = "stationery-lightweight";
        public const string StationeryPreprinted = "stationery-preprinted";
        public const string StationeryPrepunched = "stationery-prepunched";
        public const string StationeryRecycled = "stationery-recycled";
        public const string TabStock = "tab-stock";
        public const string Tractor = "tractor";
        public const string Transfer = "transfer";
        public const string Transparency = "transparency";
        public const string TripleWall = "triple-wall";
        public const string WetFilm = "wet-film";
    }

    // keywords for presentation-direction-number-up
    // https://ftp.pwg.org/pub/pwg/candidates/cs-ippprodprint10-20010212-5100.3.pdf
    public struct PresentationDirectionNumberUp
    {
        public const string BottomLeft = "tobottom-toleft";
        public const string BottomRight = "tobottom-toright";
        public const string LeftBottom = "toleft-tobottom";
        public const string LeftTop = "toleft-totop";
        public const string RightBottom = "toright-tobottom";
        public const string RightTop = "toright-totop";
        public const string TopLeft = "totop-toleft";
        public const string TopRight = "totop-toright";
    }

    // keywords for page-order-received
    // https://ftp.pwg.org/pub/pwg/candidates/cs-ippprodprint10-20010212-5100.3.pdf
    public struct PageOrderReceived
    {
        public const string OnetoNOrder = "1-to-n-order";
        public const string NtoOneOrder = "n-to-1-order";
    }

    // keywords for media-source-feed-direction.
    // https://ftp.pwg.org/pub/pwg/candidates/cs-ippjobprinterext3v10-20120727-5100.13.pdf section 7.6.6.1
    public struct MediaSourceFeedDirections
    {
        public const string LongEdgeFirst = "long-edge-first";
        public const string ShortEdgeFirst = "short-edge-first";
    }

    // keywords for output-bin-supported, etc.
    // https://ftp.pwg.org/pub/pwg/candidates/cs-ippoutputbin10-20010207-5100.2.pdf section 2.1.
    public struct OutputBins
    {
        public const string Auto = "auto";
        public const string Top = "top";
        public const string Middle = "middle";
        public const string Bottom = "bottom";
        public const string Side = "side";
        public const string Left = "left";
        public const string Right = "right";
        public const string Center = "center";
        public const string Rear = "rear";
        public const string FaceUp = "face-up";
        public const string FaceDown = "face-down";
        public const string LargeCapacity = "large-capacity";
        public const string Stacker1 = "stacker-1";
        public const string Stacker2 = "stacker-2";
        public const string Stacker3 = "stacker-3";
        public const string Stacker4 = "stacker-4";
        public const string Stacker5 = "stacker-5";
        public const string Stacker6 = "stacker-6";
        public const string Stacker7 = "stacker-7";
        public const string Stacker8 = "stacker-8";
        public const string Stacker9 = "stacker-9";
        public const string Stacker10 = "stacker-10";
        public const string Mailbox1 = "mailbox-1";
        public const string Mailbox2 = "mailbox-2";
        public const string Mailbox3 = "mailbox-3";
        public const string Mailbox4 = "mailbox-4";
        public const string Mailbox5 = "mailbox-5";
        public const string Mailbox6 = "mailbox-6";
        public const string Mailbox7 = "mailbox-7";
        public const string Mailbox8 = "mailbox-8";
        public const string Mailbox9 = "mailbox-9";
        public const string Mailbox10 = "mailbox-10";
        public const string Mailbox11 = "mailbox-11";
        public const string Mailbox12 = "mailbox-12";
        public const string Mailbox13 = "mailbox-13";
        public const string Mailbox14 = "mailbox-14";
        public const string Mailbox15 = "mailbox-15";
        public const string Mailbox16 = "mailbox-16";
        public const string Mailbox17 = "mailbox-17";
        public const string Mailbox18 = "mailbox-18";
        public const string Mailbox19 = "mailbox-19";
        public const string Mailbox20 = "mailbox-20";
        public const string Mailbox21 = "mailbox-21";
        public const string Mailbox22 = "mailbox-22";
        public const string Mailbox23 = "mailbox-23";
        public const string Mailbox24 = "mailbox-24";
        public const string Mailbox25 = "mailbox-25";
        public const string MyMailbox = "my-mailbox";
        public const string Tray1 = "tray-1";
        public const string Tray2 = "tray-2";
        public const string Tray3 = "tray-3";
        public const string Tray4 = "tray-4";
        public const string Tray5 = "tray-5";
        public const string Tray6 = "tray-6";
        public const string Tray7 = "tray-7";
        public const string Tray8 = "tray-8";
        public const string Tray9 = "tray-9";
        public const string Tray10 = "tray-10";
        public const string Tray11 = "tray-11";
        public const string Tray12 = "tray-12";
        public const string Tray13 = "tray-13";
        public const string Tray14 = "tray-14";
        public const string Tray15 = "tray-15";
        public const string Tray16 = "tray-16";
        public const string Tray17 = "tray-17";
        public const string Tray18 = "tray-18";
        public const string Tray19 = "tray-19";
        public const string Tray20 = "tray-20";
    }

    // keywords for printer-state-reasons
    // https://www.iana.org/assignments/ipp-registrations/ipp-registrations.xhtml
    // we currently accept any non-empty values of printer-state-reasons
    // the list below only includes some values from the entire list to be used during testing
    public struct PrinterStateReasons
    {
        public const string None = "none";
        public const string Other = "other";
        public const string MediaNeeded = "media-needed";
        public const string MediaJam = "media-jam";
        public const string MovingToPaused = "moving-to-paused";
        public const string Paused = "paused";
        public const string Shutdown = "shutdown";
        public const string ConnectingToDevice = "connecting-to-device";
        public const string TimedOut = "timed-out";
        public const string Stopping = "stopping";
        public const string StoppedPartly = "stopped-partly";
        public const string TonerLow = "toner-low";
        public const string TonerEmpty = "toner-empty";
        public const string SpoolAreaFull = "spool-area-full";
        public const string CoverOpen = "cover-open";
        public const string InterlockOpen = "interlock-open";
        public const string DoorOpen = "door-open";
        public const string InputTrayMissing = "input-tray-missing";
        public const string MediaLow = "media-low";
        public const string MediaEmpty = "media-empty";
        public const string OutputTrayMissing = "output-tray-missing";
        public const string OutputAreaAlmostFull = "output-area-almost-full";
        public const string OutputAreaFull = "output-area-full";
        public const string MarkerSupplyLow = "marker-supply-low";
        public const string MarkerSupplyEmpty = "marker-supply-empty";
        public const string MarkerWasteAlmostFull = "marker-waste-almost-full";
        public const string MarkerWasteFull = "marker-waste-full";
        public const string FuserOverTemp = "fuser-over-temp";
        public const string FuserUnderTemp = "fuser-under-temp";
        public const string OpcNearEol = "opc-near-eol";
        public const string OpcLifeOver = "opc-life-over";
        public const string DeveloperLow = "developer-low";
        public const string DeveloperEmpty = "developer-empty";
        public const string InterpreterResourceUnavailable = "interpreter-resource-unavailable";
    }

    public struct PrinterStateReasonSuffix
    {
        public const string Report = "-report";
        public const string Warning = "-warning";
        public const string Error = "-error";
    }

    public struct JobStateReasons
    {
        public const string None = "none";
        public const string JobIncoming = "job-incoming";
        public const string JobDataInsufficient = "job-data-insufficient";
        public const string DocumentAccessError = "document-access-error";
        public const string SubmissionInterrupted = "submission-interrupted";
        public const string JobOutgoing = "job-outgoing";
        public const string JobHoldUntilSpecified = "job-hold-until-specified";
        public const string ResourcesAreNotReady = "resources-are-not-ready";
        public const string PrinterStoppedPartly = "printer-stopped-partly";
        public const string PrinterStopped = "printer-stopped";
        public const string JobInterpreting = "job-interpreting";
        public const string JobQueued = "job-queued";
        public const string JobTransforming = "job-transforming";
        public const string JobQueuedForMarker = "job-queued-for-marker";
        public const string JobPrinting = "job-printing";
        public const string JobCanceledByUser = "job-canceled-by-user";
        public const string JobCanceledByOperator = "job-canceled-by-operator";
        public const string JobCanceledAtDevice = "job-canceled-at-device";
        public const string AbortedBySystem = "aborted-by-system";
        public const string UnsupportedCompression = "unsupported-compression";
        public const string CompressionError = "compression-error";
        public const string UnsupportedDocumentFormat = "unsupported-document-format";
        public const string DocumentFormatError = "document-format-error";
        public const string ProcessingToStopPoint = "processing-to-stop-point";
        public const string ServiceOffLine = "service-off-line";
        public const string JobCompletedSuccessfully = "job-completed-successfully";
        public const string JobCompletedWithWarnings = "job-completed-with-warnings";
        public const string JobCompletedWithErrors = "job-completed-with-errors";
        public const string QueuedInDevice = "queued-in-device";
        public const string JobFetchable = "job-fetchable";
        public const string JobReleaseWait = "job-release-wait";
        public const string JobHeldForAuthorization = "job-held-for-authorization";
        public const string JobHeldForButtonPress = "job-held-for-button-press";
        public const string JobHeldForRelease = "job-held-for-release";  //Replacement for JobReleaseWait
        public const string JobPasswordWait = "job-password-wait";
        public const string OtherError = "other-error";
        public const string JobFetchableByUser = "job-fetchable-by-user";
    }

    // http://ftp.pwg.org/pub/pwg/candidates/cs-ippjobprinterext3v10-20120727-5100.13.pdf
    public struct IppFeaturesSupported
    {
        public const string AirPrintTwoDotOne = "airprint-2.1";
        public const string DocumentObject = "document-object";
        public const string JobSave = "job-save";
        public const string None = "none";
        public const string PageOverrides = "page-overrides";
        public const string ProofPrint = "proof-print";
        public const string SubscriptionObject = "subscription-object";
    }

    // Mopria 1.3 spec Wi-Fi_Direct_Services_Print_Technical_Specification_v1.0
    // https://microsoft.sharepoint.com/:w:/t/STACKTeam-CoreNetworkingMobileConnectivityPeripheralsStackSe/EQkk8BUSMqxGh1b0wkNLlhIBWqsk28NRk3n3F-jEKB69Gg?e=5iUo4A
    public struct PdfVersionsSupported
    {
        public const string Adobe13 = "adobe-1.3";
        public const string Adobe14 = "adobe-1.4";
        public const string Adobe15 = "adobe-1.5";
        public const string Adobe16 = "adobe-1.6";
        public const string Iso1593012001 = "iso-15930-1_2001";
        public const string Iso1593032002 = "iso-15930-3_2002";
        public const string Iso1593042003 = "iso-15930-4_2003";
        public const string Iso1593062003 = "iso-15930-6_2003";
        public const string Iso1593072010 = "iso-15930-7_2010";
        public const string Iso1593082010 = "iso-15930-8_2010";
        public const string Iso1661222010 = "iso-16612-2_2010";
        public const string Iso1900512005 = "iso-19005-1_2005";
        public const string Iso1900522011 = "iso-19005-2_2011";
        public const string Iso1900532012 = "iso-19005-3_2012";
        public const string Iso3200012008 = "iso-32000-1_2008";
        public const string Pwg51023 = "pwg-5102.3";
        public const string None = "none";
    }

    // RFC 5100.7 Section 7.6 https://ftp.pwg.org/pub/pwg/candidates/cs-ippjobext10-20031031-5100.7.pdf
    public struct DocumentFormatDetailsSupported
    {
        public const string DocumentSourceApplicationName = "document-source-application-name";
        public const string DocumentSourceApplicationVersion = "document-source-application-version";
        public const string DocumentSourceOsName = "document-source-os-name";
        public const string DocumentSourceOsVersion = "document-source-os-version";
        public const string DocumentFormat = "document-format";
        public const string DocumentFormatDeviceId = "document-format-device-id";
        public const string DocumentFormatVersion = "document-format-version";
        public const string DocumentNaturalLanguage = "document-natural-language";
    }

    // Section 6.4.12 of https://ftp.pwg.org/pub/pwg/candidates/cs-ipptrans10-20131108-5100.16.pdf
    public struct PrinterKinds
    {
        public const string Disc = "disc";
        public const string Document = "document";
        public const string Envelope = "envelope";
        public const string Label = "label";
        public const string LargeFormat = "large-format";
        public const string Photo = "photo";
        public const string Postcard = "postcard";
        public const string Receipt = "receipt";
        public const string Roll = "roll";
    }

    // Section 5.3.3 of https://ftp.pwg.org/pub/pwg/candidates/cs-ippjobext20-20190816-5100.7.pdf
    public struct PrintContentOptimize
    {
        public const string Auto = "auto"; // AirPrint specific, see section 9.3.57 of AirPrint Version 2.1.1 specification
        public const string Graphics = "graphics";
        public const string Photo = "photo";
        public const string Text = "text";
        public const string TextAndGraphics = "text-and-graphics";
    }

    // https://www.rfc-editor.org/rfc/rfc8011.html#section-5.4.28
    public struct PdlOverride
    {
        public const string Attempted = "attempted";
        public const string Guaranteed = "guaranteed";
        public const string NotAttempted = "not-attempted";
    }

    // https://www.rfc-editor.org/rfc/rfc8011.html#section-5.4.2
    // Section 9.7 of https://ftp.pwg.org/pub/pwg/candidates/cs-ippinfra10-20150619-5100.18.pdf
    // Section 7.8 of https://ftp.pwg.org/pub/pwg/candidates/cs-ippjobprinterext3v10-20120727-5100.13.pdf
    public struct UriAuthentication
    {
        public const string Basic = "basic";
        public const string Certificate = "certificate";
        public const string Digest = "digest";
        public const string Negotiate = "negotiate";
        public const string None = "none";
        public const string Oauth = "oauth";
        public const string RequestingUserName = "requesting-user-name";
    }

    // https://www.rfc-editor.org/rfc/rfc8011.html#section-5.4.3
    public struct UriSecurity
    {
        public const string None = "none";
        public const string Ssl3 = "ssl3";
        public const string Tls = "tls";
    }

    // https://ftp.pwg.org/pub/pwg/ipp/wd/wd-ippnodriver20-20201029.pdf#section-6.6.17
    public struct MultipleOperationTimeoutAction
    {
        public const string AbortJob = "abort-job";
        public const string HoldJob = "hold-job";
        public const string ProcessJob = "process-job";
    }

    // https://ftp.pwg.org/pub/pwg/ipp/wd/wd-ippepx20-20230206.pdf#section-6.1.3
    // MopriaCloudPrintSpecificationv1.1.027#section 4.10
    public struct JobReleaseAction
    {
        public const string None = "none";
        public const string ButtonPress = "button-press";
        public const string JobPassword = "job-password";
        public const string OwnerAuthorized = "owner-authorized";
        public const string OwnerAuthorizedBadge = "owner-authorized-badge";
        public const string OwnerAuthorizedUsernamePassword = "owner-authorized-username-password";
        public const string OwnerAuthorizedBiometrics = "owner-authorized-biometrics";
        public const string OwnerAuthorizedOther = "owner-authorized-other";
        public const string WorkflowApp = "workflow-app";
    }

    // https://www.rfc-editor.org/rfc/rfc8011.html#section-5.4.32
    public struct Compression
    {
        public const string None = "none";
        public const string Compress = "compress";
        public const string Deflate = "deflate";
        public const string Gzip = "gzip";
    }
}

#pragma warning restore SA1602 // Enumeration items should be documented
#pragma warning restore SA1600 // Elements should be documented
