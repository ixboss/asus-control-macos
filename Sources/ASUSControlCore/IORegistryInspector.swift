import Foundation
import IOKit
import IOKit.ps
import CoreGraphics
import Darwin

/// Read-only hardware and IORegistry inspector for ASUS TUF Gaming F17 (FX707ZM).
/// Performs zero ACPI method calls, zero EC writes, and zero SMI interrupts.
public struct IORegistryInspector: Sendable {
    public init() {}

    // MARK: - Sysctl Helpers

    private static func decodeCString(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func sysctlString(_ name: String) -> String? {
        var size: Int = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return decodeCString(buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func sysctlInt(_ name: String) -> Int? {
        var val: Int64 = 0
        var size = MemoryLayout<Int64>.size
        if sysctlbyname(name, &val, &size, nil, 0) == 0 {
            if size == 4 {
                return Int(Int32(truncatingIfNeeded: val))
            }
            return Int(val)
        }
        return nil
    }

    // MARK: - Host Identity

    public func inspectHostIdentity() -> HostIdentity {
        let osVer = ProcessInfo.processInfo.operatingSystemVersion
        let osVersionStr = "\(osVer.majorVersion).\(osVer.minorVersion).\(osVer.patchVersion)"
        let osBuild = Self.sysctlString("kern.osversion") ?? "Unknown"
        let kernelVersion = Self.sysctlString("kern.version") ?? "Unknown"

        var smbiosModel = Self.sysctlString("hw.model") ?? "Unknown"
        var bootArgs = ""

        // Read NVRAM boot-args from IODeviceTree:/options
        let optionsEntry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/options")
        if optionsEntry != IO_OBJECT_NULL {
            defer { IOObjectRelease(optionsEntry) }
            if let prop = IORegistryEntryCreateCFProperty(optionsEntry, "boot-args" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                if let str = prop as? String {
                    bootArgs = str
                } else if let data = prop as? Data {
                    bootArgs = String(data: data.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
                }
            }
        }

        // Read NullMoth system-profile.json if available for exact board/BIOS identity
        var boardManufacturer = "ASUSTeK COMPUTER INC."
        var boardProduct = "FX707ZM"
        var systemProduct = "ASUS TUF Gaming F17 FX707ZM_FX707ZM"
        var biosVersion = "FX707ZM.316"

        let profilePath = "/Library/NullMoth/system-profile.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: profilePath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let board = json["board"] as? [String: Any] {
                boardManufacturer = (board["manufacturer"] as? String) ?? boardManufacturer
                boardProduct = (board["product"] as? String) ?? boardProduct
                systemProduct = (board["systemProduct"] as? String) ?? systemProduct
                biosVersion = (board["biosVersion"] as? String) ?? biosVersion
            }
            if let smbios = json["smbios"] as? String {
                smbiosModel = smbios
            }
        }

        return HostIdentity(
            boardManufacturer: boardManufacturer,
            boardProduct: boardProduct,
            systemProduct: systemProduct,
            biosVersion: biosVersion,
            smbiosModel: smbiosModel,
            osVersion: osVersionStr,
            osBuild: osBuild,
            kernelVersion: kernelVersion,
            bootArgs: bootArgs
        )
    }

    // MARK: - CPU Topology

    public func inspectCPUTopology() -> CPUTopologyReport {
        let brand = Self.sysctlString("machdep.cpu.brand_string") ?? "Unknown CPU"
        let family = Self.sysctlInt("machdep.cpu.family") ?? 0
        let model = Self.sysctlInt("machdep.cpu.model") ?? 0
        let stepping = Self.sysctlInt("machdep.cpu.stepping") ?? 0
        let microcode = Self.sysctlInt("machdep.cpu.microcode_version") ?? 0
        let physCores = Self.sysctlInt("hw.physicalcpu") ?? 0
        let logThreads = Self.sysctlInt("hw.logicalcpu") ?? 0

        var enabledNodes: [String] = []
        var disabledNodes: [String] = []

        var seenNames = Set<String>()
        let matching = IOServiceMatching("IOACPIPlatformDevice")
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS {
            defer { IOObjectRelease(iter) }
            while case let service = IOIteratorNext(iter), service != IO_OBJECT_NULL {
                defer { IOObjectRelease(service) }
                var nameBuf = [CChar](repeating: 0, count: 128)
                guard IORegistryEntryGetName(service, &nameBuf) == KERN_SUCCESS else { continue }
                let rawName = Self.decodeCString(nameBuf)
                let name = rawName.components(separatedBy: "@").first ?? rawName
                guard name.hasPrefix("C0") && name.count == 4 else { continue }
                guard !seenNames.contains(name) else { continue }
                seenNames.insert(name)

                let props = Self.propertiesDictionary(for: service)
                let procID = (props["processor-id"] as? Int)
                    ?? (props["processor-id"] as? Data)?.first.map { Int($0) }
                let lapic = (props["processor-lapic"] as? Int)
                    ?? (props["processor-lapic"] as? Data)?.first.map { Int($0) }

                var hasACPICPUChild = false
                var childIter: io_iterator_t = 0
                if IORegistryEntryGetChildIterator(service, kIOServicePlane, &childIter) == KERN_SUCCESS {
                    defer { IOObjectRelease(childIter) }
                    while case let child = IOIteratorNext(childIter), child != IO_OBJECT_NULL {
                        defer { IOObjectRelease(child) }
                        if IOObjectConformsTo(child, "AppleACPICPU") != 0 {
                            hasACPICPUChild = true
                        }
                    }
                }

                if hasACPICPUChild {
                    enabledNodes.append("\(name) (id=\(procID ?? -1), lapic=\(lapic ?? -1))")
                } else {
                    disabledNodes.append("\(name) (id=\(procID ?? -1))")
                }
            }
        }

        enabledNodes.sort()
        disabledNodes.sort()

        let explanation = "Hardware has 14 physical cores / 20 threads (6 HT P-cores + 8 non-HT E-cores in MADT apic.aml). Because XNU requires homogeneous threads-per-core across the package, ProcessorId 12..19 (8 E-cores, APIC IDs 48..62) are marked LocalApicId=255 Disabled in the in-memory APIC table, leaving the 6 Hyper-Threaded P-cores (12 threads, LocalApicId 0,1,8,9,16,17,24,25,32,33,40,41) active under XCPM."

        return CPUTopologyReport(
            brandString: brand,
            family: family,
            model: model,
            stepping: stepping,
            microcodeVersion: microcode,
            activePhysicalCores: physCores,
            activeLogicalThreads: logThreads,
            acpiTotalProcessorNodes: enabledNodes.count + disabledNodes.count,
            acpiEnabledPCoreThreads: enabledNodes,
            acpiDisabledProcessorNodes: disabledNodes,
            topologyExplanation: explanation
        )
    }

    // MARK: - GPUs & Display Routing

    public func inspectGPUs() -> [GPUDeviceReport] {
        var reports: [GPUDeviceReport] = []

        // Check IGPU@2 and PEGP@0
        let matching = IOServiceMatching("IOPCIDevice")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return reports
        }
        defer { IOObjectRelease(iter) }

        while case let dev = IOIteratorNext(iter), dev != IO_OBJECT_NULL {
            defer { IOObjectRelease(dev) }
            let props = Self.propertiesDictionary(for: dev)
            guard let vendorData = props["vendor-id"] as? Data, vendorData.count >= 2,
                  let deviceData = props["device-id"] as? Data, deviceData.count >= 2 else { continue }

            let vendorID = vendorData.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
            let deviceID = deviceData.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }

            // Filter to display class or known GPUs (Intel 0x8086:0x4626, NVIDIA 0x10DE:0x2520)
            let isIntelGPU = (vendorID == 0x8086 && deviceID == 0x4626)
            let isNvidiaGPU = (vendorID == 0x10DE && deviceID == 0x2520)
            guard isIntelGPU || isNvidiaGPU else { continue }

            let acpiPath = (props["acpi-path"] as? String) ?? "Unknown"
            var nameBuf = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(dev, &nameBuf)
            let nodeName = Self.decodeCString(nameBuf)

            var driverName = "None"
            var isDrivingInternal = false
            var notes = ""

            var childIter: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(dev, kIOServicePlane, &childIter) == KERN_SUCCESS {
                defer { IOObjectRelease(childIter) }
                while case let child = IOIteratorNext(childIter), child != IO_OBJECT_NULL {
                    defer { IOObjectRelease(child) }
                    var childNameBuf = [CChar](repeating: 0, count: 128)
                    IORegistryEntryGetName(child, &childNameBuf)
                    let cName = Self.decodeCString(childNameBuf)
                    if cName == "NVRM" {
                        driverName = "NVRM + NVRMFB (NullMoth 2.7.2)"
                        isDrivingInternal = true
                        notes = "Drives internal eDP panel LGD066C (display 0x400) on head 0 with NVRMBacklightHandler via ACPI NBCI _DSM."
                    } else if cName.contains("AppleIntelFramebufferController") {
                        let wxeReady = (props["WhateverXeBacklightProfileReady"] as? Bool) ?? false
                        driverName = "WhateverXe (ADL-P load-only)"
                        isDrivingInternal = false
                        notes = "WhateverXeBacklightProfileReady=\(wxeReady); native FB/accelerator probes rejected by nmxintel=1 (no active framebuffer)."
                    }
                }
            }

            reports.append(GPUDeviceReport(
                name: isNvidiaGPU ? "NVIDIA GeForce RTX 3060 Laptop GPU (\(nodeName))" : "Intel UHD Graphics Alder Lake-P (\(nodeName))",
                vendorID: UInt32(vendorID),
                deviceID: UInt32(deviceID),
                acpiPath: acpiPath,
                pciPath: isNvidiaGPU ? "PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)" : "PciRoot(0x0)/Pci(0x2,0x0)",
                isDrivingInternalDisplay: isDrivingInternal,
                driverName: driverName,
                notes: notes
            ))
        }

        return reports.sorted { $0.vendorID < $1.vendorID }
    }

    // MARK: - Brightness & Backlight Path

    public func inspectBrightness() -> BrightnessReport {
        var displayVendorID: UInt32 = 0
        var displayProductID: UInt32 = 0
        var logicalVal: Int?
        var logicalMin: Int?
        var logicalMax: Int?
        var linearVal: Int?

        let matching = IOServiceMatching("AppleBacklightDisplay")
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        if entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }
            let props = Self.propertiesDictionary(for: entry)
            displayVendorID = UInt32((props["DisplayVendorID"] as? Int) ?? 0)
            displayProductID = UInt32((props["DisplayProductID"] as? Int) ?? 0)
            if let params = props["IODisplayParameters"] as? [String: Any] {
                if let brt = params["brightness"] as? [String: Any] {
                    logicalVal = brt["value"] as? Int
                    logicalMin = brt["min"] as? Int
                    logicalMax = brt["max"] as? Int
                }
                if let lin = params["linear-brightness"] as? [String: Any] {
                    linearVal = lin["value"] as? Int
                }
            }
        }

        // Check PNLF presence
        var pnlfPresent = false
        let acpiMatch = IOServiceNameMatching("PNLF")
        let pnlfEntry = IOServiceGetMatchingService(kIOMainPortDefault, acpiMatch)
        if pnlfEntry != IO_OBJECT_NULL {
            pnlfPresent = true
            IOObjectRelease(pnlfEntry)
        }

        // Query DisplayServices dynamically (read-only)
        let dsResult = Self.queryDisplayServicesReadOnly()

        let summary = "Internal panel LGD066C (0x\(String(format: "%04X", displayVendorID)):0x\(String(format: "%04X", displayProductID))) is routed to PEGP@0 (RTX 3060) -> NVRMDisplay@0 -> NVRMBacklightHandler + AppleBacklightDisplay. NVRM evaluates NBCI _DSM (0x0, 0x10, 0x14) from ssdt14.aml and sends RM control 0x730292 on brightness updates. IGPU@2 is in ADL-P load-only mode with no framebuffer; PNLF/AppleIntelPanelA is inert."

        return BrightnessReport(
            internalPanelName: (displayVendorID == 0x30E4 && displayProductID == 0x066C) ? "LGD066C (1920x1080 eDP 300Hz)" : "Internal eDP Panel",
            displayVendorID: displayVendorID,
            displayProductID: displayProductID,
            connectedGPUPath: "IOACPIPlane:/_SB/PC00@0/PEG1@10000/PEGP@0",
            backlightDriverClass: "NVRMBacklightHandler",
            displayServicesAvailable: dsResult.available,
            displayServicesCanChange: dsResult.canChange,
            softwareBrightnessPercent: dsResult.brightness.map { $0 * 100.0 },
            ioDisplayLogicalValue: logicalVal,
            ioDisplayLogicalMin: logicalMin,
            ioDisplayLogicalMax: logicalMax,
            ioDisplayLinearValue: linearVal,
            pnlfPresentOnIGPU: pnlfPresent,
            whateverXeBacklightProfileReadyOnIGPU: true,
            igpuHasActiveFramebuffer: false,
            architectureSummary: summary
        )
    }

    private static func queryDisplayServicesReadOnly() -> (available: Bool, canChange: Bool, brightness: Float?) {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            return (false, false, nil)
        }
        defer { dlclose(handle) }

        typealias CanChangeFn = @convention(c) (UInt32) -> Bool
        typealias GetBrtFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32

        let mainDisplayID = CGMainDisplayID()
        let candidateIDs: [UInt32] = mainDisplayID != 0 ? [mainDisplayID, 1] : [1]

        var canChange = false
        if let sym = dlsym(handle, "DisplayServicesCanChangeBrightness") {
            let fn = unsafeBitCast(sym, to: CanChangeFn.self)
            for id in candidateIDs where fn(id) {
                canChange = true
                break
            }
        }

        var brt: Float = -1.0
        var gotBrt: Float? = nil
        if let sym = dlsym(handle, "DisplayServicesGetBrightness") {
            let fn = unsafeBitCast(sym, to: GetBrtFn.self)
            for id in candidateIDs {
                if fn(id, &brt) == 0 && brt >= 0.0 {
                    gotBrt = brt
                    break
                }
            }
        }
        return (true, canChange, gotBrt)
    }

    // MARK: - Battery & Power

    public func inspectBattery() -> BatteryReport {
        let matching = IOServiceMatching("AppleSmartBattery")
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard entry != IO_OBJECT_NULL else {
            return BatteryReport(
                installed: false, deviceName: "None", externalConnected: false,
                isCharging: false, fullyCharged: false, designCapacitymWh: 0,
                maxCapacitymWh: 0, currentCapacitymWh: 0, healthPercent: 0,
                chargePercent: 0, voltagemV: 0, amperagemA: 0, powerWatts: 0,
                temperatureCelsius: 0, cycleCount: 0
            )
        }
        defer { IOObjectRelease(entry) }

        let p = Self.propertiesDictionary(for: entry)
        let installed = (p["BatteryInstalled"] as? Bool) ?? false
        let devName = (p["DeviceName"] as? String) ?? "BAT1"
        let extConn = (p["ExternalConnected"] as? Bool) ?? false
        let isCharging = (p["IsCharging"] as? Bool) ?? false
        let fullyCharged = (p["FullyCharged"] as? Bool) ?? false
        let designCap = (p["DesignCapacity"] as? Int) ?? 0
        let maxCap = (p["AppleRawMaxCapacity"] as? Int) ?? (p["MaxCapacity"] as? Int) ?? 0
        let curCap = (p["AppleRawCurrentCapacity"] as? Int) ?? (p["CurrentCapacity"] as? Int) ?? 0
        let voltage = (p["Voltage"] as? Int) ?? 0
        let amperage = (p["InstantAmperage"] as? Int) ?? (p["Amperage"] as? Int) ?? 0
        let rawTemp = (p["Temperature"] as? Int) ?? 0
        let cycles = (p["CycleCount"] as? Int) ?? 0

        let health = designCap > 0 ? (Double(maxCap) / Double(designCap)) * 100.0 : 0.0
        let pct = maxCap > 0 ? (Double(curCap) / Double(maxCap)) * 100.0 : 0.0
        let watts = (Double(voltage) * Double(abs(amperage))) / 1_000_000.0
        // AppleSmartBattery Temperature on SMCBatteryManager is deci-Kelvin or centi-Celsius (3021 -> 30.21 C or 28.95 C)
        let tempC = rawTemp > 2500 ? (Double(rawTemp) / 100.0) : 0.0

        return BatteryReport(
            installed: installed,
            deviceName: devName,
            externalConnected: extConn,
            isCharging: isCharging,
            fullyCharged: fullyCharged,
            designCapacitymWh: designCap,
            maxCapacitymWh: maxCap,
            currentCapacitymWh: curCap,
            healthPercent: (health * 10).rounded() / 10,
            chargePercent: (pct * 10).rounded() / 10,
            voltagemV: voltage,
            amperagemA: amperage,
            powerWatts: (watts * 100).rounded() / 100,
            temperatureCelsius: (tempC * 100).rounded() / 100,
            cycleCount: cycles
        )
    }

    // MARK: - Key ACPI Devices

    public func inspectACPIDevices() -> [ACPIDevicePresence] {
        let targetNames: Set<String> = ["ATKD", "EC0", "SMKB", "ALS0", "PNLF", "ACAD", "BAT1", "NPCF", "ASUP"]
        var results: [ACPIDevicePresence] = []

        let matching = IOServiceMatching("IOACPIPlatformDevice")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return results
        }
        defer { IOObjectRelease(iter) }

        while case let service = IOIteratorNext(iter), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            var nameBuf = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(service, &nameBuf) == KERN_SUCCESS else { continue }
            let rawName = Self.decodeCString(nameBuf)
            let baseName = rawName.components(separatedBy: "@").first ?? rawName
            guard targetNames.contains(baseName) else { continue }

            let props = Self.propertiesDictionary(for: service)
            let hid = (props["_HID"] as? String)
                ?? (props["name"] as? Data).flatMap({ String(data: $0.prefix(while: { $0 != 0 }), encoding: .utf8) })
                ?? "Unknown"
            let uid = props["_UID"] as? String
            let acpiPath = (props["acpi-path"] as? String) ?? "Unknown"
            let sta = props["_STA"] as? Int

            var attachedDriver: String? = nil
            var childIter: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(service, kIOServicePlane, &childIter) == KERN_SUCCESS {
                defer { IOObjectRelease(childIter) }
                let child = IOIteratorNext(childIter)
                if child != IO_OBJECT_NULL {
                    defer { IOObjectRelease(child) }
                    var cName = [CChar](repeating: 0, count: 128)
                    IORegistryEntryGetName(child, &cName)
                    attachedDriver = Self.decodeCString(cName)
                }
            }

            results.append(ACPIDevicePresence(
                name: rawName,
                hidOrCompatible: hid,
                uid: uid,
                acpiPath: acpiPath,
                status: sta,
                attachedDriver: attachedDriver
            ))
        }

        return results.sorted { $0.name < $1.name }
    }

    // MARK: - Helpers

    public static func propertiesDictionary(for entry: io_registry_entry_t) -> [String: Any] {
        var dict: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &dict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let cfDict = dict?.takeRetainedValue() as? [String: Any] else {
            return [:]
        }
        return cfDict
    }
}
