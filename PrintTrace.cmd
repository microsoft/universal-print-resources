@echo off

REM Collects TraceLogging and WPP print traces. Run in an elevated command prompt.

REM Update PrintTraceTtd.cmd as well for any added trace providers

if exist PrintTrace.zip del PrintTrace.zip
if exist %tmp%\trace rd /s /q %tmp%\trace
md %tmp%\trace
pushd %tmp%\trace

@echo PrintTrace v2.3 > PrintTrace.cfg

REM WPP Providers - Level = 0x7FFFFFFF

REM Spooler WPP Trace Control Guids
REM SPOOLSV
@echo {C9BF4A9E-D547-4d11-8242-E03A18B5BE01} 0x7FFFFFFF 0xFF > providers.cfg
REM SPOOLSS
@echo {C9BF4A9F-D547-4d11-8242-E03A18B5BE01} 0x7FFFFFFF 0xFF >> providers.cfg
REM LOCALSPL
@echo {C9BF4A01-D547-4d11-8242-E03A18B5BE01} 0x7FFFFFFF 0xFF >> providers.cfg
REM PrintPLM
@echo {d2e1bab1-eb9b-4ba7-9123-19c01ddc4f78} 0x7FFFFFFF 0xFF >> providers.cfg
REM WINSPOOL
@echo {C9BF4A02-D547-4d11-8242-E03A18B5BE01} 0x7FFFFFFF 0xFF >> providers.cfg
REM WIN32SPL
@echo {C9BF4A03-D547-4d11-8242-E03A18B5BE01} 0x7FFFFFFF 0xFF >> providers.cfg
REM BIDISPL
@echo {C9BF4A04-D547-4d11-8242-E03A18B5BE01} 0x7FFFFFFF 0xFF >> providers.cfg
REM SPLWOW64
@echo {C9BF4A05-D547-4d11-8242-E03A18B5BE01} 0x7FFFFFFF 0xFF >> providers.cfg
REM SPLLIB
@echo {C9BF4A06-D547-4d11-8242-E03A18B5BE01} 0x7FFFFFFF 0xFF >> providers.cfg
REM PERFLIB
@echo {C9BF4A07-D547-4d11-8242-E03A18B5BE01} 0x7FFFFFFF 0xFF >> providers.cfg
REM ASYNCNTFY
@echo {C9BF4A08-D547-4d11-8242-E03A18B5BE01} 0x7FFFFFFF 0xFF >> providers.cfg
REM REMNTFY
@echo {C9BF4A09-D547-4d11-8242-E03A18B5BE01} 0x7FFFFFFF 0xFF >> providers.cfg
REM GPPRNEXT
@echo {C9BF4A0A-D547-4d11-8242-E03A18B5BE01} 0x7FFFFFFF 0xFF >> providers.cfg
REM SANDBOX
@echo {C9BF4A0B-D547-4d11-8242-E03A18B5BE01} 0x7FFFFFFF 0xFF >> providers.cfg
REM SANDBOXHOST
@echo {C9BF4A0C-D547-4d11-8242-E03A18B5BE01} 0x7FFFFFFF 0xFF >> providers.cfg
REM PIPELINE
@echo {AEFE45F4-8548-42B4-B1C8-25673B07AD8B} 0x7FFFFFFF 0xFF >> providers.cfg
REM NTPRINT
@echo {B795C7DF-07BC-4362-938E-E8ABD81A9A01} 0x7FFFFFFF 0xFF >> providers.cfg
REM LPRHELP
@echo {9e6d0d9b-1ce5-44b5-8b98-f32ed89077ec} 0x7FFFFFFF 0xFF >> providers.cfg
REM LPRMON
@echo {f30fab8e-84bb-48d4-8e80-f8967ef0fe6a} 0x7FFFFFFF 0xFF >> providers.cfg
REM USBJSCRIPT
@echo {B48AE058-218A-4338-9B97-9F5F9E4EB5D2} 0x7FFFFFFF 0xFF >> providers.cfg
REM USBMOn
@echo {99F5F45C-FD1E-439F-A910-20D0DC759D28} 0x7FFFFFFF 0xFF >> providers.cfg
REM TCPMIB
@echo {D3A10B55-1EAD-453d-8FC7-35DA3D6A04D2} 0x7FFFFFFF 0xFF >> providers.cfg
REM TCPMON
@echo {62A0EB6C-3E3E-471d-960C-7C574A72534C} 0x7FFFFFFF 0xFF >> providers.cfg
REM WSDPRINT
@echo {9558985e-3bc8-45ef-a2fd-2e6ff06fb886} 0x7FFFFFFF 0xFF >> providers.cfg
REM WSDMON
@echo {836767A6-AF31-4938-B4C0-EF86749A9AEF} 0x7FFFFFFF 0xFF >> providers.cfg
REM WSDPPROXY
@echo {6D1E0446-6C52-4b85-840D-D2CB10AF5C63} 0x7FFFFFFF 0xFF >> providers.cfg
REM DAFWSD
@echo {4ea56ff9-fc2a-4f0c-8d6e-c345bc452c80} 0x7FFFFFFF 0xFF >> providers.cfg
REM FDWSD
@echo {7e2dbfc7-41e8-4987-bca7-76cadfad765f} 0x7FFFFFFF 0xFF >> providers.cfg
REM FDPrint
@echo {79b3b0b7-f082-4cec-91bc-5e4b9cc3033a} 0x7FFFFFFF 0xFF >> providers.cfg
REM WSDAPI
REM @echo {75454210-b231-4fea-b2b4-2cc66d7ae8aa} 0x7FFFFFFF 0xFF >> providers.cfg
REM FindNetPrinters
@echo {A1607A05-8D8A-4d74-82C7-460DD790648E} 0x7FFFFFFF 0xFF >> providers.cfg
REM XPSPRINT
@echo {CA478AB1-8B38-451D-90E4-8534EB50B9D3} 0x7FFFFFFF 0xFF >> providers.cfg
REM MicrosoftRenderFilter
@echo {A6D25EF4-A3B3-4E5F-A872-24E71103FBDC} 0x7FFFFFFF 0xFF >> providers.cfg
REM BTHPRINT
@echo {eb3b6950-120c-4575-af39-2f713248e8a3} 0x7FFFFFFF 0xFF >> providers.cfg
REM DAFBTH
@echo {8bbe74b4-d9fc-4052-905e-92d01579e3f1} 0x7FFFFFFF 0xFF >> providers.cfg
REM BTHUSER
@echo {afa85d6c-0ea6-4c6a-99b7-5be1c9f3c7a1} 0x7FFFFFFF 0xFF >> providers.cfg
REM BTHPORT
REM @echo {D88ACE07-CAC0-11D8-A4C6-000D560BCBA5} 0x7FFFFFFF 0xFF >> providers.cfg
REM DOXXPS
@echo {0dc96237-bbd4-4bc9-8184-46df83b1f1f0} 0x7FFFFFFF 0xFF >> providers.cfg
REM DOXPKG
REM @echo {0675cf90-f2b8-11db-bb42-0013729b82c4} 0x7FFFFFFF 0xFF >> providers.cfg
REM XpsRchVw
@echo {986de178-ea3f-4e27-bbee-34e0f61535dd} 0x7FFFFFFF 0xFF >> providers.cfg
REM XpsIFilter
@echo {64f02056-afd9-42d9-b221-6c94733b09b1} 0x7FFFFFFF 0xFF >> providers.cfg
REM XpsShellExt
@echo {2beade0b-84cd-44a5-90a7-5b6fb2ff83c8} 0x7FFFFFFF 0xFF >> providers.cfg
REM XpsRender
@echo {aaacb431-6067-4a42-8883-3c01526dd43a} 0x7FFFFFFF 0xFF >> providers.cfg
REM inet3pp
@echo {c9bf4a9e-d547-4d11-8242-e03a18b5beee} 0x7FFFFFFF 0xFF >> providers.cfg

REM PrintUI WPP Trace Control Guids
REM PRINTUI
@echo {A83C80B9-AE01-4981-91C6-94F00C0BB8AA} 0x7FFFFFFF 0xFF >> providers.cfg
REM PRNNTFY
@echo {09737B09-A25E-44D8-AA75-07F7572458E2} 0x7FFFFFFF 0xFF >> providers.cfg
REM PRNCACHE
REM @echo {34F7D4F8-CD95-4b06-8BF6-D929DE4AD9DE} 0x7FFFFFFF 0xFF >> providers.cfg
REM PRNFLDR
REM @echo {883dfb21-94ee-4c9b-9922-d5c42b552e09} 0x7FFFFFFF 0xFF >> providers.cfg

REM PrintDriver WPP Trace Controls
REM PrintExtension
@echo {19E93940-A1BD-497F-BC58-CA333880BAB4} 0x7FFFFFFF 0xFF >> providers.cfg

REM JScriptLib WPP Trace Controls
@echo {C59DA080-9CCE-4415-A77D-08457D7A059F} 0x7FFFFFFF 0xFF >> providers.cfg

REM Roaming WPP Trace Controls
REM DAFPRINT
@echo {3048407B-56AA-4D41-82B2-7d5F4b1CDD39} 0x7FFFFFFF 0xFF >> providers.cfg
REM DAS
@echo {19E464A4-7408-49BD-B960-53446AE47820} 0x7FFFFFFF 0xFF >> providers.cfg

REM Driver WPP Trace Controls
REM MSXpsFilters
@echo {9B4A618C-07B8-4182-BA5A-5B1943A92EA1} 0x7FFFFFFF 0xFF >> providers.cfg

REM MXDC WPP Trace Controls
REM MXDC
@echo {FCA72EBA-CBB3-467c-93BC-1DB4978C398D} 0x7FFFFFFF 0xFF >> providers.cfg

REM PrintDialog WPP Trace Controls
REM PREFDLG
@echo {3FB15E5D-DF1A-46FC-BEFE-27A4B82D75EE} 0x7FFFFFFF 0xFF >> providers.cfg
REM DLGHOST
@echo {02EA8EB9-9811-46d6-AEEE-430ADCC2AA18} 0x7FFFFFFF 0xFF >> providers.cfg

REM Windows.Graphics.Printing WPP Trace Controls
REM MODERNPRINT
@echo {DD6A31CB-C9C6-4EF9-B738-F306C29352F4} 0x7FFFFFFF 0xFF >> providers.cfg
REM PrinterExtensions
@echo {EC08D605-5A20-4ED0-AE54-E8C4BFFF2EEB} 0x7FFFFFFF 0xFF >> providers.cfg
REM AAD Cloud AP
@echo {556045FD-58C5-4A97-9881-B121F68B79C5} 0x7FFFFFFF 0xFF >> providers.cfg

REM PSMWPP
@echo {4a743cbb-3286-435c-a674-b428328940e4} 0x7FFFFFFF 0xFF >> providers.cfg
REM PLMWPP
@echo {9C6FC32A-E17A-11DF-B1C4-4EBADFD72085} 0x7FFFFFFF 0xFF >> providers.cfg
REM SEBWPP
@echo {e8109b99-3a2c-4961-aa83-d1a7a148ada8} 0x7FFFFFFF 0xFF >> providers.cfg

REM Scan
REM ScanRT WPP
@echo {E6F8A5FC-7FCE-4095-8661-B8E0CB7D9410} 0x7FFFFFFF 0xFF >> providers.cfg
REM DeviceEnumeration WPP
@echo {1B42986F-288F-4DD7-B7F9-120297715C1E} 0x7FFFFFFF 0xFF >> providers.cfg

REM PrintBRM (BRMENGINE) WPP
@echo {12DFC189-A85B-4B19-847B-D9AC6B716DB8} 0x7FFFFFFF 0xFF >> providers.cfg

REM TraceLogging Providers - Level = default (0xFFFFFFFFFFFFFFFF for TraceLogging)

REM Workflow and PrintSupport
REM "Microsoft.Windows.Print.Workflow.API"
@echo {744372de-ba26-443b-ba10-712c1a041234} >> providers.cfg
REM "Microsoft.Windows.Print.Workflow.Broker"
@echo {1bf554be-03c5-4f49-9b57-f3c0cbad589a} >> providers.cfg
REM "Microsoft.Windows.Print.Workflow.PrintSupport"
@echo {08fad69b-3394-5632-97ef-ff9c5a842b1f} >> providers.cfg
REM "Microsoft.Windows.Print.Workflow.Source"
@echo {be5f8487-3a5d-4477-b0c2-020679b81e56} >> providers.cfg
REM "Microsoft.Windows.Print.PrintSupport"
@echo {7faee4d5-95c1-5987-54c6-a7c3dfb6e56e} >> providers.cfg
REM "Microsoft.Windows.Print.WorkFlowBroker"
@echo {F69D3E6C-298B-466C-B84F-486E1F21E347} >> providers.cfg
REM "Microsoft.Windows.Print.WorkFlowRT"
@echo {cae6f32b-2553-5c24-f999-e63dde138b9f} >> providers.cfg

REM Microsoft.Windows.PrintCore
@echo {a4f32eea-babb-59b2-3828-ce92e4e20765} >> providers.cfg
REM Microsoft-Windows-Mobile-Print-Plugins
@echo {6de9ba0e-9e72-53d2-229a-dc09205a27ea} >> providers.cfg
REM Microsoft-Windows-Print-Platform
@echo {fd6b6ae4-7563-550d-46a4-da9fe46cad57} >> providers.cfg
REM Microsoft.Windows.Print.PrintConfig
@echo {fdcab703-6402-4959-b618-f5c3c279ef3d} >> providers.cfg
REM Microsoft.Windows.Print.DriverUI
@echo {ffdb1efb-602c-5725-c85c-f3f1a065d72a} >> providers.cfg
REM Microsoft.Windows.Print.DeviceCenter
@echo {4c7e30ea-beaf-5b10-ae30-451fb529c653} >> providers.cfg
REM Microsoft.Windows.Print.PrintDeviceCapabilities
@echo {FD6EC121-DC51-42FD-A559-BA984D345E2B} >> providers.cfg
REM Microsoft.Windows.Print.PrintCoreConfig
@echo {3d9d790d-fb07-539d-b66e-5a2ffb7899ca} >> providers.cfg
REM Microsoft.Windows.Shell.PrintDialog
@echo {b0f40491-9ea6-5fd5-ccb1-0ec63be8b674} >> providers.cfg
REM Microsoft.Windows.Shell.PrintManager
@echo {c6dba857-03f1-5c5b-350c-ef08dbd04572} >> providers.cfg
REM Microsoft-Windows-LifetimeManager
REM @echo {072665fb-8953-5a85-931d-d06aeab3d109} >> providers.cfg
REM Microsoft.Windows.Das
@echo {ab4d9355-341e-435d-b3d2-4b0e46354e2c} >> providers.cfg
REM Microsoft-Windows-WSD-DafProvider
@echo {e4d412ab-4c22-49ef-83ca-eafb90768512} >> providers.cfg
REM Microsoft.Windows.Print.WSDMon
@echo {BC2DAB59-AC78-487A-903E-DB3C343C0BE3} >> providers.cfg
REM Microsoft-Windows-WSD-WSDApi
@echo {29b47072-00ff-4d9d-852d-0eafc181a9a3} >> providers.cfg
REM Microsoft.Windows.Print.PrintScanService
@echo {cb730350-b8b7-56d7-6fa4-90e0ea74a9bb} >> providers.cfg
REM Microsoft.Windows.Shell.ServiceProvider
@echo {15584c9b-7d86-5fe0-a123-4a0f438a82c0} >> providers.cfg
REM Windows.Internal.Shell.ModalExperience
@echo {8BFE6B98-510E-478D-B868-142CD4DEDC1A} >> providers.cfg
REM Microsoft.Windows.Mobile.Shell.ServiceProvider
@echo {97ff6b54-144c-524b-5fec-82b610461390} >> providers.cfg
REM Microsoft.Windows.Print.XpsPrint
@echo {73cf4d38-21a5-41dc-93d5-c8ec31d84b70} >> providers.cfg
REM Microsoft.Windows.Print.XpsDocumentTargetPrint
@echo {095da8da-2182-5c9a-53cd-07eca93a04ef} >> providers.cfg
REM Microsoft.Windows.Print.IppMon
@echo {6fb61ac3-3455-4da4-8313-c1a855ee64c5} >> providers.cfg
REM Microsoft.Windows.Print.APMon
@echo {e73d49d6-9eda-5059-74d1-b879b18cf9ae} >> providers.cfg
REM Microsoft.Windows.Print.WsdAdapter
@echo {40dd7897-9206-5dc5-d21b-2de290ca181a} >> providers.cfg
REM Microsoft.Windows.Print.DafIpp
@echo {6d5ca4bb-df8e-41bc-b554-8aeab241f206} >> providers.cfg
REM Microsoft.Windows.Print.DafIppUsb
@echo {dd212385-31e6-541c-5587-3c469bb6470a} >> providers.cfg
REM Microsoft.Windows.Print.IppCommon
@echo {acf1e4a7-9241-4fbf-9555-c27638434f8d} >> providers.cfg
REM Microsoft.Windows.Print.IppCommonDll
@echo {e9e3a474-c716-56f4-f6f2-5d5f181c46ab} >> providers.cfg
REM Microsoft.Windows.Print.IppOneCore
@echo {a08e69ca-2172-5c18-fe96-a2ac30857b97} >> providers.cfg
REM Microsoft.Windows.Print.IppConfigConverter
@echo {6184BC1F-417E-4443-BCCE-9F65BF844AA7} >> providers.cfg
REM Microsoft.Windows.Print.HttpRest
@echo {49868e3d-77fb-5083-9e09-61e3f37e0309} >> providers.cfg
REM Microsoft.Windows.Print.IppEmulator
@echo {05af8001-5e28-5ebb-0329-a20fab346b76} >> providers.cfg
REM Microsoft.Windows.Print.Mopria.Service
@echo {38ae712f-fad1-528e-9721-6ebefea1ab2b} >> providers.cfg
REM Microsoft.Windows.Print.Ecp.Service
@echo {ec5b420f-d2ec-50b4-5119-083a4da63982} >> providers.cfg
REM Microsoft.Windows.Print.GetPrinterConfig
@echo {7e247d3c-42fa-5e08-6427-f98478081d24} >> providers.cfg
REM Microsoft.Windows.Print.GetIppAttributes
@echo {9594011E-FE68-4D05-9F06-C68A0EBE4822} >> providers.cfg
REM Microsoft.Windows.Print.JScriptLib
@echo {2974da9a-e1f3-5c5f-2abe-f7f20f6448bc} >> providers.cfg
REM Microsoft.Windows.Security.TokenBroker
REM @echo {077b8c4a-e425-578d-f1ac-6fdf1220ff68} >> providers.cfg
REM Microsoft.AAD.TokenBrokerPlugin.Provider
REM @echo {bfed9100-35d7-45d4-bfea-6c1d341d4c6b} >> providers.cfg
REM Microsoft.Windows.Print.PwgRenderFilter
@echo {e98cb748-3d93-4719-8209-95e0bc46eec7} >> providers.cfg
REM Microsoft.Windows.Print.PCLmRenderFilter
@echo {15fc363b-e2b4-5e55-f1d3-3b0ff726203d} >> providers.cfg
REM Microsoft.Windows.Print.PrintToPDF
@echo {63a87ca3-6662-4925-a0a8-f7bb94ef104e} >> providers.cfg
REM Microsoft.Windows.Print.TiffRenderFilter
@echo {7617c8d5-b61c-5f45-dd42-02c19bd5f387} >> providers.cfg
REM Microsoft.Windows.Print.RenderFilterCommon
@echo {ac521649-5ec6-5397-d1c5-749cbf5ea79b} >> providers.cfg
REM Microsoft.Windows.Print.USBMon
@echo {3fc887c9-c23f-59cd-88b5-a6086f4bbc9e} >> providers.cfg
REM Microsoft.Windows.Print.Usbprint
@echo {99d90395-1bb0-5932-720a-21d1be94eba3} >> providers.cfg
REM Microsoft.Windows.Print.DAFMCP
@echo {bf3eac2a-65ca-5ecc-2076-e23c6420a687} >> providers.cfg
REM Microsoft.Windows.Print.CloudPrintHelper
@echo {44050ea2-419d-5526-923b-b038e0f1e715} >> providers.cfg
REM Microsoft.Windows.Print.IppAdapterCore
@echo {48111f99-b3d5-5f69-587d-be4ed8e22647} >> providers.cfg
REM Microsoft.Windows.Print.IppAdapterCommon
@echo {fbfbd628-251d-551d-c4dd-c7820af723e4} >> providers.cfg
REM Microsoft.Windows.Print.PrintScanDiscoveryManagement
@echo {e0d2f15a-3875-5388-2239-23f2538b7636} >> providers.cfg
REM Microsoft.Windows.Print.PDMUtilities
@echo {0aef9116-5ab8-5c05-0eb3-c0721ba93354} >> providers.cfg
REM Microsoft.Windows.Print.WinspoolCore
@echo {81d45b93-a5ff-5459-26ff-c092864200c6} >> providers.cfg
REM Microsoft.Windows.Print.ApMonPortMig
@echo {d758d01c-7402-5923-6a27-44bdcc59a5c5} >> providers.cfg
REM Microsoft.Windows.Print.UsbPortMig
@echo {201eb0f8-12f0-5b34-c99b-75c1541f3479} >> providers.cfg
REM Microsoft.Windows.Print.McpManagement
@echo {7cdc2341-4d44-54aa-2899-ddb05ecf0adb} >> providers.cfg
REM Microsoft.Windows.Print.McpManagementUtil
@echo {402d7aed-ded3-5536-3112-a2ce8baa1fdc} >> providers.cfg
REM Microsoft.Windows.Print.McpIppChannel
@echo {ee8c758e-2e70-574f-8149-266b77c8d56a} >> providers.cfg
REM Microsoft.Windows.Print.McpEvtSrc
@echo {b145b5c6-1a9d-50c5-7f76-39f208ed09c9} >> providers.cfg
REM Microsoft.Windows.Print.McpLppHelper
@echo {0e46cee6-dd9a-5b24-67c6-be3a88c3f894} >> providers.cfg
REM Microsoft.Windows.Print.ProxyApp
@echo {e604ec58-ad08-5a2c-3ecb-704c8c024881} >> providers.cfg
REM Microsoft.Windows.Print.GDI
@echo {bad46242-e75f-541f-c2d2-ab35489f27e4} >> providers.cfg
REM Microsoft.Windows.Print.GpdParser
@echo {c5488b38-f338-51d9-1046-be7b050f3198} >> providers.cfg
REM Microsoft.Windows.Print.UniLib
@echo {24a149d9-e7af-59b9-10c7-b2115913ea92} >> providers.cfg
REM Microsoft.Windows.Print.PrvSpoolss
@echo {8325bcbd-4d99-5255-0722-d4387890d3c3} >> providers.cfg
REM Microsoft.Windows.Print.CSPs.UPPrinterInstalls
@echo {5000d5f2-f6c7-59e0-eda8-c5126f0eefcd} >> providers.cfg
REM Microsoft.Windows.Scan.EsclScan
@echo {2e008da9-e1b6-5cb5-0607-82066afcfff4} >> providers.cfg
REM Microsoft.Windows.Scan.EsclWiaDriver
@echo {93603fbe-a752-550d-b87e-f202b0f27f9e} >> providers.cfg
REM Microsoft.Windows.Scan.EsclProtocol
@echo {27a7ea23-db5c-5487-b775-89c06c43039b} >> providers.cfg
REM Microsoft.Windows.Scan.DafEscl
@echo {f25e0650-deff-5306-ca0d-40abb8b107dd} >> providers.cfg
REM Microsoft.Windows.Scan.EsclEmulator
@echo {3e617461-4ad0-5bb1-ce2d-796bf4794fbf} >> providers.cfg
REM Microsoft.Windows.Scan.Plugins
@echo {4e880362-c4e8-5c62-7a2e-db0ee6a8f9a8} >> providers.cfg
REM Microsoft.Windows.Scan.EsclWiaCore
@echo {c7c2a97e-3d49-5f78-bd33-22d8c22a7cf3} >> providers.cfg
REM Microsoft.Windows.Scan.Runtime
@echo {df6dca70-9918-455f-86fe-983adc74fa0d} >> providers.cfg
REM Microsoft.Windows.Scan.WindowsImageAcquisition
@echo {4a892232-6efc-54c1-1f0a-1b916a719612} >> providers.cfg
REM Microsoft.Windows.Print.DeviceControl
@echo {5fef3144-ec00-5072-ee6b-5d0a02bb656c}  >> providers.cfg
REM Microsoft.Windows.Print.XGC
@echo {0a82e916-4637-4998-83bf-8b0f4792a7c9}  >> providers.cfg
REM Microsoft.Windows.Print.DeviceConfiguration
@echo {d43cc295-539f-5e64-77ce-78ef0e51825c}  >> providers.cfg
REM Microsoft.Windows.Print.PrinterAssociationCommon
@echo {8288e29d-0fc0-56b8-03ed-7fa253155f20}  >> providers.cfg
REM Microsoft.Windows.Print.PrintUtil
@echo {ee6271a2-f93c-566a-b4a1-4eacdbce3ad3}  >> providers.cfg
REM Microsoft.Windows.Print.WindowsProtectedPrintConfiguration
@echo {d6773a85-1345-51b6-78c0-83b8bad18ac6}  >> providers.cfg
REM Microsoft.Windows.Print.BidiSpl
@echo {8fdc4e28-f79e-5b10-67d2-abbdde0eb492}  >> providers.cfg
REM Microsoft.Windows.Print.ClassInstaller
@echo {70cfefa3-edb1-5f09-aa78-047998973db4}  >> providers.cfg
REM Microsoft.Windows.Print.SplLib
@echo {7981fc8d-605e-4052-87a7-fe07ced4ebaf}  >> providers.cfg
REM Microsoft.Windows.Print.PrintPLM
@echo {9a191e89-421b-596b-7509-8732bb37e5a7}  >> providers.cfg
REM Microsoft.Windows.Print.LocalMon
@echo {2cca72d1-e6c4-583f-b5f3-09a6fd03d7f2}  >> providers.cfg
REM Microsoft.Windows.Print.Win32Spl
@echo {6838ba59-f713-50ab-e08d-2104c7c6c5c2}  >> providers.cfg
REM Microsoft.Windows.Print.LocalSpooler
@echo {ba4936a1-31db-4edc-89ce-9190e3c0653b}  >> providers.cfg
REM Microsoft.Windows.Print.SpoolerService
@echo {b4d2914c-ff23-403b-babf-f0755fb060fe}  >> providers.cfg
REM Microsoft.Windows.Print.UalPrint
@echo {958c225a-bceb-5381-5eec-78105239d403}  >> providers.cfg
REM Microsoft.Windows.Print.AsyncNotify
@echo {24c8068e-eb8d-50eb-b33d-3c71e64e16ad}  >> providers.cfg
REM Microsoft.Windows.Print.DevmodeSizePatch
@echo {97b0ffcd-6217-567e-4fda-e5e0f7f6da54}  >> providers.cfg
REM Microsoft.Windows.Print.PerfLib
@echo {1d7de9de-bf31-59da-11f8-7744efe97627}  >> providers.cfg
REM Microsoft.Windows.Print.Sandbox
@echo {b830bb6f-f59a-5846-766f-85eb6c3de78a}  >> providers.cfg
REM Microsoft.Windows.Print.Winspool
@echo {c69cb70a-3133-4cca-ab0e-046848effcda}  >> providers.cfg
REM Microsoft.Windows.Print.SplWow64
@echo {c501f929-70aa-5c15-a8bf-9a2143dca7dc}  >> providers.cfg

REM ETW providers - Level = 0xFFFFFFFF

REM Microsoft-Windows-PrintDialogs
@echo {27E76321-1E5B-4a82-BA0C-26E978F15072} 0xFFFFFFFF 0xFF >> providers.cfg
REM Microsoft-Windows-PrintDrivers
@echo {0E173F13-4266-4EFD-883C-79B24789B1BC} 0xFFFFFFFF 0xFF >> providers.cfg
REM microsoft-windows-printservice-usbmon
@echo {7f812073-b28d-4afc-9ced-b8010f914ef6} 0xFFFFFFFF 0xFF >> providers.cfg
REM Microsoft-Windows-PrintService
@echo {747EF6FD-E535-4d16-B510-42C90F6873A1} 0xFFFFFFFF 0xFF >> providers.cfg
REM Microsoft-Windows-ProcessStateManager
@echo {d49918cf-9489-4bf1-9d7b-014d864cf71f} 0xFFFFFFFF 0xFF >> providers.cfg
REM Microsoft-Windows-SystemEventsBroker
@echo {B6BFCC79-A3AF-4089-8D4D-0EECB1B80779} 0xFFFFFFFF 0xFF >> providers.cfg

REM Collect system information

@echo Architecture %PROCESSOR_ARCHITECTURE% >> PrintTrace.cfg
ver >> PrintTrace.cfg
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v BuildLabEx >> PrintTrace.cfg
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v EditionId >>  PrintTrace.cfg
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v InstallationType >> PrintTrace.cfg
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\SQMClient" /v MachineId >> PrintTrace.cfg

echo BEFORE >> PrintTrace.cfg

echo. >> PrintTrace.cfg
%WinDir%\System32\WindowsPowerShell\v1.0\powershell -NoLogo -NoProfile -NonInteractive -Command "get-printer -full |fl; get-printerdriver |fl" >> PrintTrace.cfg
echo. >> PrintTrace.cfg

echo. >> PrintTrace.cfg
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\PrinterExtensionAssociations" /s >> PrintTrace.cfg 2>&1
echo. >> PrintTrace.cfg

echo HKLM Printers before >> PrintTrace.cfg
echo. >> PrintTrace.cfg
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Printers" /S >> PrintTrace.cfg
echo. >> PrintTrace.cfg
echo HKCU Printers before >> PrintTrace.cfg
reg query "HKEY_CURRENT_USER\Printers" /S >> PrintTrace.cfg
echo. >> PrintTrace.cfg

REM Start tracing

REM netsh trace start capture=yes report=yes persistent=yes overwrite=yes maxsize=4096 scenario=NetConnection tracefile=NetTrace.etl provider="Microsoft-Windows-WinHttp" keywords=0x7FFFFFFFfffffffff level=0xff provider="Microsoft-Windows-TCPIP" keywords=0x7FFFFFFFfffffffff level=0xff provider="Microsoft-Windows-Kernel-PnP" keywords=0x7FFFFFFFfffffffff level=0xff provider="Microsoft-Windows-UserPnp" keywords=0x7FFFFFFFfffffffff level=0xff provider={72B18662-744E-4A68-B816-8D562289A850} keywords=0x7FFFFFFFfffffffff level=0xff
logman -ets start PrintTrace -nb 50 256 -bs 128 -pf providers.cfg
REM Use a larger buffer size and more buffers to avoid dropped ETW events for large traces
REM logman delete PrintTrace
REM logman create trace PrintTrace -nb 50 256 -bs 128 -pf providers.cfg -o .\PrintTrace.etl
REM logman start PrintTrace

@echo.
@echo Reproduce the issue.  Press [enter] once finished.  Send the generated PrintTrace.zip file.
@echo.
pause

REM Stop tracing

REM logman stop PrintTrace
logman -ets stop PrintTrace
REM netsh trace stop

echo AFTER >> PrintTrace.cfg

echo. >> PrintTrace.cfg
%WinDir%\System32\WindowsPowerShell\v1.0\powershell -NoLogo -NoProfile -NonInteractive -Command "get-printer -full |fl; get-printerdriver |fl" >> PrintTrace.cfg
echo. >> PrintTrace.cfg

echo. >> PrintTrace.cfg
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\PrinterExtensionAssociations" /s >> PrintTrace.cfg 2>&1
echo. >> PrintTrace.cfg

echo HKLM Printers after >> PrintTrace.cfg
echo. >> PrintTrace.cfg
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Printers" /S >> PrintTrace.cfg
echo. >> PrintTrace.cfg
echo HKCU Printers after  >> PrintTrace.cfg
reg query "HKEY_CURRENT_USER\Printers" /S >> PrintTrace.cfg
echo. >> PrintTrace.cfg

REM Copy WiaTrace
if exist %windir%\debug\WIA\wiatrace.log copy %windir%\debug\WIA\wiatrace.log

REM Copy EsclScanLog
if exist %windir%\debug\WIA\EsclScanLog.txt copy %windir%\debug\WIA\EsclScanLog.txt

REM Copy upgrade logs
if exist %windir%\inf\setupapi.app.log copy %windir%\inf\setupapi.app.log setupapi.app.log
if exist %windir%\inf\setupapi.dev.log copy %windir%\inf\setupapi.dev.log setupapi.dev.log
if exist %windir%\inf\setupapi.offline.log copy %windir%\inf\setupapi.offline.log setupapi.offline.log
if exist %windir%\inf\setupapi.setup.log copy %windir%\inf\setupapi.setup.log setupapi.setup.log
if exist %windir%\inf\setupapi.upgrade.log copy %windir%\inf\setupapi.upgrade.log setupapi.upgrade.log

REM Get output of running processes
tasklist /svc >> tasklist.log

REM zip up logs
popd
%WinDir%\System32\WindowsPowerShell\v1.0\powershell -NoLogo -NoProfile -NonInteractive -Command "& { Add-Type -A System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::CreateFromDirectory('%tmp%\trace', 'PrintTrace.zip'); }"

@echo.
@echo Please send the following file in the current directory:
dir /b PrintTrace.zip
