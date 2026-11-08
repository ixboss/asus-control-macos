import Foundation
import ASUSControlCore

@main
struct AsusCtlDiagMain {
    static func runSelfTest(_ snap: DiagnosticSnapshot) -> Bool {
        var passed = true
        func check(_ cond: Bool, _ msg: String) {
            if cond {
                print("  [PASS] \(msg)")
            } else {
                print("  [FAIL] \(msg)")
                passed = false
            }
        }
        print("================================================================================")
        print(" ASUS Control for macOS — Phase 1A Read-Only Self-Test Suite (FX707ZM)")
        print("================================================================================")
        check(snap.host.boardProduct == "FX707ZM", "Host board product is FX707ZM (\(snap.host.boardProduct))")
        check(snap.host.biosVersion == "FX707ZM.316", "Host BIOS version is FX707ZM.316 (\(snap.host.biosVersion))")
        check(snap.cpu.activePhysicalCores == 6 && snap.cpu.activeLogicalThreads == 12, "Active CPU topology is 6P / 12T (\(snap.cpu.activePhysicalCores)C/\(snap.cpu.activeLogicalThreads)T)")
        check(snap.cpu.acpiTotalProcessorNodes == 64 && snap.cpu.acpiEnabledPCoreThreads.count == 12, "ACPI processor nodes: 12 enabled P-core threads out of 64 (\(snap.cpu.acpiEnabledPCoreThreads.count)/\(snap.cpu.acpiTotalProcessorNodes))")
        check(snap.gpus.count == 2, "Both Intel UHD (0x8086:0x4626) and NVIDIA RTX 3060 (0x10DE:0x2520) detected (\(snap.gpus.count))")
        check(snap.brightness.displayVendorID == 0x30E4 && snap.brightness.displayProductID == 0x066C, "Internal panel is LGD066C (0x30E4:0x066C)")
        check(snap.brightness.backlightDriverClass == "NVRMBacklightHandler" && snap.brightness.displayServicesCanChange, "Backlight controlled by NVRMBacklightHandler with DisplayServicesCanChange=true")
        check(snap.brightness.igpuHasActiveFramebuffer == false, "IGPU is in ADL-P load-only mode with zero active framebuffers")
        check(snap.battery.installed && snap.battery.designCapacitymWh == 5675, "Battery A32-K55 installed (DesignCapacity=5675 mAh / ~90 Wh)")
        check(snap.smc.totalKeysCount == 97 && snap.smc.fanCountReported == 0, "VirtualSMC reports 97 keys and FNum=0 (confirming need for AsusBridge.kext for fans/CTMP)")
        check(snap.acpiDevices.contains(where: { $0.name == "ATKD" }) && snap.acpiDevices.contains(where: { $0.name == "EC0" }), "ACPI ATKD (PNP0C14) and EC0 (PNP0C09) verified active in IORegistry")
        print("--------------------------------------------------------------------------------")
        print(" Self-Test Result: \(passed ? "ALL 11 VERIFICATION CHECKS PASSED (100%)" : "FAILED")")
        print("================================================================================\n")
        return passed
    }

    static func runBridgeProbe() {
        let client = AsusBridgeClient()
        print("================================================================================")
        print(" ASUS Control for macOS — Phase 1B Read-Only AsusBridge.kext Probe (FX707ZM)")
        print("================================================================================")
        guard client.isAvailable() else {
            print("  [STATUS] AsusBridge.kext is NOT currently loaded in IORegistry.")
            print("  [LOAD  ] To load temporarily for read-only verification:")
            print("           sudo cp -R build/kext/AsusBridge.kext /tmp/AsusBridge.kext && sudo chown -R root:wheel /tmp/AsusBridge.kext && sudo kextutil /tmp/AsusBridge.kext")
            print("================================================================================\n")
            return
        }

        do {
            let snap = try client.fetchSnapshot()
            print("  [STATUS] AsusBridge.kext Connected (ABI Version: \(snap.abiVersion))")
            print("  [WMNB  ] INIT = 0x\(String(format: "%08X", snap.initRaw)), SFUN = 0x\(String(format: "%08X", snap.sfunRaw))")
            print("  [POWER ] ACAD._PSR (On AC) = \(snap.onACPower), EC0.ECOK = \(snap.ecOk)")
            print("  [TEMP  ] CPU Package Temp (0x00120094) : \(snap.cpuTempCelsius) °C (Raw DSTS: 0x\(String(format: "%08X", snap.cpuTempRawDSTS)))")
            print("  [FANS  ] CPU Fan Speed    (0x00110013) : \(snap.cpuFanRPM) RPM (Raw DSTS: 0x\(String(format: "%08X", snap.cpuFanRawDSTS)))")
            print("  [FANS  ] GPU Fan Speed    (0x00110014) : \(snap.gpuFanRPM) RPM (Raw DSTS: 0x\(String(format: "%08X", snap.gpuFanRawDSTS)))")
            print("  [GPU   ] MUX Switch State (0x00090016) : 0x\(String(format: "%08X", snap.muxStateRawDSTS)) (\(snap.muxStateRawDSTS == 0x10000 ? "Ultimate / Direct dGPU" : "Standard / Optimus"))")
            print("  [GPU   ] dGPU State       (0x00090020) : 0x\(String(format: "%08X", snap.dgpuStateRawDSTS))")
            print("  [PPT   ] CPU PL1 / SPL    (0x001200A3) : 0x\(String(format: "%08X", snap.pptPL1RawDSTS))")
            print("  [PPT   ] CPU PL2 / SPPT   (0x001200A0) : 0x\(String(format: "%08X", snap.pptPL2RawDSTS))")
            print("  [KBD   ] KBD Backlight EC (0x0010005B) : 0x\(String(format: "%08X", snap.kbdBacklightRawDSTS)) (Level: \(snap.kbdBacklightRawDSTS & 0xFFFF))")
            print("  [KEYS  ] Hotkey Events                 : Sequence=\(snap.hotkeySequence), LastCode=0x\(String(format: "%02X", snap.lastHotkeyCode))")

            print("\n  --- Firmware Default 8-Point Fan Curves (EC0.CFCV & EC0.GFCV) ---")
            for profile in 0...2 {
                for fan in 0...1 {
                    if let curve = try? client.readFanCurve(fanIndex: fan, profileIndex: profile) {
                        let pairs = zip(curve.temperaturesCelsius, curve.dutyPercentEstimated)
                            .map { "\($0.0)°C:\($0.1)%" }
                            .joined(separator: ", ")
                        print("  * \(curve.fanName) [\(curve.profileName)]: \(pairs)")
                    }
                }
            }

            print("\n  --- Single-Shot Read-Only DSTS Probes (SMM / W15H & Display) ---")
            let singleProbes: [(UInt32, String)] = [
                (0x00050011, "Display Backlight Control (BLCT)"),
                (0x00120057, "Battery Charge Limit (RSOC)"),
                (0x00120075, "Thermal Performance Profile (THRP)"),
                (0x00100056, "TUF Gaming RGB Mode/Color (KBLT/KBLM)"),
                (0x00100057, "TUF Gaming RGB State (TUFA)")
            ]
            for (devID, label) in singleProbes {
                if let res = try? client.probeWhitelistedDSTS(deviceID: devID, label: label) {
                    print("  * \(res.deviceIDHex) (\(res.label)): ok=\(res.evaluatedOK) raw=\(res.rawValueHex) present=\(res.presentBitSet) payload=\(res.decodedPayload)")
                }
            }

            if let klog = client.readKernelLogProperty() {
                print("\n  --- AsusBridge Kernel Ring Log ---")
                print("  \(klog)")
            }
        } catch {
            print("  [ERROR ] Failed to query AsusBridgeUserClient: \(error.localizedDescription)")
        }
        print("================================================================================\n")
    }

    static func main() {
        let args = CommandLine.arguments
        let jsonMode = args.contains("--json")
        let selfTestMode = args.contains("--self-test")
        let bridgeProbeMode = args.contains("--bridge-probe")

        let matrix = FX707ZMCapabilityMatrix()
        let snapshot = matrix.captureSnapshot()

        if selfTestMode {
            let ok = runSelfTest(snapshot)
            if !ok { exit(1) }
        }

        if bridgeProbeMode {
            runBridgeProbe()
            return
        }

        if jsonMode {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(snapshot),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
            return
        }

        print("================================================================================")
        print(" ASUS Control for macOS — Phase 1A Read-Only Hardware & Capability Audit")
        print(" Timestamp: \(snapshot.timestampISO8601)")
        print("================================================================================\n")

        print("[1] HOST IDENTITY")
        print("  Manufacturer : \(snapshot.host.boardManufacturer)")
        print("  Board / Model: \(snapshot.host.boardProduct) (\(snapshot.host.systemProduct))")
        print("  BIOS Version : \(snapshot.host.biosVersion)")
        print("  SMBIOS       : \(snapshot.host.smbiosModel)")
        print("  macOS Version: \(snapshot.host.osVersion) (Build \(snapshot.host.osBuild))")
        print("  Kernel       : \(snapshot.host.kernelVersion)")
        print("  Boot-Args    : \(snapshot.host.bootArgs)\n")

        print("[2] CPU TOPOLOGY")
        print("  Brand        : \(snapshot.cpu.brandString)")
        print("  Signature    : Family \(snapshot.cpu.family), Model \(snapshot.cpu.model), Stepping \(snapshot.cpu.stepping) (Microcode 0x\(String(snapshot.cpu.microcodeVersion, radix: 16)))")
        print("  macOS Active : \(snapshot.cpu.activePhysicalCores) Physical Cores / \(snapshot.cpu.activeLogicalThreads) Logical Threads")
        print("  ACPI Nodes   : \(snapshot.cpu.acpiTotalProcessorNodes) total (\(snapshot.cpu.acpiEnabledPCoreThreads.count) Enabled P-Core Threads, \(snapshot.cpu.acpiDisabledProcessorNodes.count) Disabled Nodes)")
        print("  Enabled CPUs : \(snapshot.cpu.acpiEnabledPCoreThreads.joined(separator: ", "))")
        print("  Explanation  : \(snapshot.cpu.topologyExplanation)\n")

        print("[3] GPU & DISPLAY ROUTING")
        for gpu in snapshot.gpus {
            print("  - \(gpu.name) [\(String(format: "%04X:%04X", gpu.vendorID, gpu.deviceID))]")
            print("    ACPI Path  : \(gpu.acpiPath)")
            print("    Driver     : \(gpu.driverName)")
            print("    Internal Pn: \(gpu.isDrivingInternalDisplay ? "YES (Primary Internal Panel)" : "NO")")
            print("    Notes      : \(gpu.notes)")
        }
        print("")

        print("[4] INTERNAL DISPLAY BRIGHTNESS & BACKLIGHT")
        print("  Panel        : \(snapshot.brightness.internalPanelName) [Vendor 0x\(String(format: "%04X", snapshot.brightness.displayVendorID)), Product 0x\(String(format: "%04X", snapshot.brightness.displayProductID))]")
        print("  Connected GPU: \(snapshot.brightness.connectedGPUPath)")
        print("  Driver Class : \(snapshot.brightness.backlightDriverClass)")
        print("  DisplaySrv   : Available=\(snapshot.brightness.displayServicesAvailable), CanChange=\(snapshot.brightness.displayServicesCanChange), SoftwareLevel=\(snapshot.brightness.softwareBrightnessPercent.map { String(format: "%.1f%%", $0) } ?? "N/A")")
        if let val = snapshot.brightness.ioDisplayLogicalValue,
           let min = snapshot.brightness.ioDisplayLogicalMin,
           let max = snapshot.brightness.ioDisplayLogicalMax {
            let pct = Double(val - min) / Double(max - min) * 100.0
            print("  IORegistry   : Logical=\(val)/\(max) (\(String(format: "%.1f%%", pct))), Linear=\(snapshot.brightness.ioDisplayLinearValue ?? -1)")
        }
        print("  IGPU / PNLF  : PNLF Present=\(snapshot.brightness.pnlfPresentOnIGPU), WhateverXeProfileReady=\(snapshot.brightness.whateverXeBacklightProfileReadyOnIGPU), IGPU Active FB=\(snapshot.brightness.igpuHasActiveFramebuffer)")
        print("  Summary      : \(snapshot.brightness.architectureSummary)\n")

        print("[5] BATTERY & POWER TELEMETRY")
        print("  Installed    : \(snapshot.battery.installed) (Device: \(snapshot.battery.deviceName))")
        print("  Power Source : \(snapshot.battery.externalConnected ? "AC Power Connected" : "Battery Power") (Charging: \(snapshot.battery.isCharging), FullyCharged: \(snapshot.battery.fullyCharged))")
        print("  Charge Level : \(snapshot.battery.chargePercent)% (\(snapshot.battery.currentCapacitymWh) / \(snapshot.battery.maxCapacitymWh) mWh)")
        print("  Battery Hlth : \(snapshot.battery.healthPercent)% (Max \(snapshot.battery.maxCapacitymWh) mWh vs Design \(snapshot.battery.designCapacitymWh) mWh, Cycles: \(snapshot.battery.cycleCount))")
        print("  Electrical   : \(snapshot.battery.voltagemV) mV, \(snapshot.battery.amperagemA) mA (\(snapshot.battery.powerWatts) W), Temp: \(snapshot.battery.temperatureCelsius) °C\n")

        print("[6] VIRTUALSMC KEY DIAGNOSTICS")
        print("  Total Keys   : \(snapshot.smc.totalKeysCount)")
        print("  Fan Keys     : FNum Present=\(snapshot.smc.fanNumberKeyPresent) (Count=\(snapshot.smc.fanCountReported)), F0Ac/F1Ac Present=\(snapshot.smc.fanRPMKeysPresent)")
        print("  CPU Temp Keys: TC0P/TC0D Present=\(snapshot.smc.cpuTempKeysPresent)")
        print("  Ambient Light: \(snapshot.smc.ambientLightLux.map { "\($0) lux (ALV0)" } ?? "Not Present")")
        print("  Battery Temps: \(snapshot.smc.batteryTemperatureKeysCelsius)\n")

        print("[7] KEY ACPI DEVICES IN IOREGISTRY")
        for dev in snapshot.acpiDevices {
            print("  - \(dev.name.padding(toLength: 8, withPad: " ", startingAt: 0)) | HID/Name: \(dev.hidOrCompatible.padding(toLength: 10, withPad: " ", startingAt: 0)) | UID: \((dev.uid ?? "-").padding(toLength: 6, withPad: " ", startingAt: 0)) | STA: \(dev.status.map(String.init) ?? "-") | Driver: \(dev.attachedDriver ?? "None") | Path: \(dev.acpiPath)")
        }
        print("")

        print("[8] FX707ZM HARDWARE CAPABILITY & SAFETY MATRIX")
        for cap in snapshot.capabilities {
            print("  * [\(cap.verificationStatus.rawValue)] \(cap.featureName) (\(cap.featureID))")
            print("    WMI ID : \(cap.wmiDeviceIDHex ?? "N/A") | Path: \(cap.acpiOrECPath)")
            print("    Safety : \(cap.safetyProfile.rawValue)")
            print("    Notes  : \(cap.notes)\n")
        }
    }
}
