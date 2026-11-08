import Foundation
import ASUSControlCore

@main
struct AsusCtlMain {
    static func printUsage() {
        print("""
        ASUS Control for macOS — CLI (asusctl v0.2.0, Target: FX707ZM)

        USAGE:
          asusctl status [--json]
          asusctl battery limit <60..100>
          asusctl profile <silent|balanced|performance|turbo>
          asusctl profile auto <on|off> [--ac <profile>] [--battery <profile>]
          asusctl fan curves
          asusctl fan set <cpu|gpu> <t1:d1,t2:d2,t3:d3,t4:d4,t5:d5,t6:d6,t7:d7,t8:d8>
          asusctl fan reset [cpu|gpu|all]
          asusctl ppt set <pl1_watts> <pl2_watts>
          asusctl ppt reset
          asusctl brightness <get|set <0..100>|up|down|hotkey <up|down>>
          asusctl lighting <status|mode <static|breathing|cycle|strobe>|color <#RRGGBB>|speed <slow|medium|fast>|brightness <0..3>>
          asusctl apply-saved
          asusctl --self-test
        """)
    }

    static func parseProfile(_ str: String) -> ThermalProfile? {
        switch str.lowercased() {
        case "silent", "quiet", "2":
            return .silent
        case "balanced", "performance", "normal", "0":
            return .balanced
        case "turbo", "1":
            return .turbo
        default:
            return nil
        }
    }

    static func parseRGBMode(_ str: String) -> TufRGBMode? {
        switch str.lowercased() {
        case "static", "0": return .staticColor
        case "breathing", "breathe", "1": return .breathe
        case "cycle", "colorcycle", "color-cycle", "2": return .colorCycle
        case "strobe", "flash", "3": return .strobe
        default: return nil
        }
    }

    static func parseRGBSpeed(_ str: String) -> TufRGBSpeed? {
        switch str.lowercased() {
        case "slow", "0": return .slow
        case "medium", "normal", "1": return .medium
        case "fast", "2": return .fast
        default: return nil
        }
    }

    static func parseKbdBrightness(_ str: String) -> KeyboardBrightnessLevel? {
        switch str.lowercased() {
        case "0", "off": return .off
        case "1", "low": return .low
        case "2", "medium", "med": return .medium
        case "3", "high", "max": return .high
        default: return nil
        }
    }

    static func cmdStatus(json: Bool) throws {
        let bridge = AsusBridgeClient()
        let inspector = IORegistryInspector()
        let brtCtrl = DisplayBrightnessController()

        let snap = try bridge.fetchSnapshot()
        let bat = inspector.inspectBattery()
        let settings = SettingsStore.shared.load()
        let brtPct = (try? brtCtrl.getBrightnessPercent()) ?? settings.lastDisplayBrightnessPercent
        let hexColor = TufKeyboardLightingController.formatHexColor(red: settings.rgbRed, green: settings.rgbGreen, blue: settings.rgbBlue)

        if json {
            struct StatusPayload: Codable {
                let kextLiveInKernel: Bool
                let kextStagedInAuxKC: Bool
                let abiVersion: UInt32
                let onACPower: Bool
                let cpuTempCelsius: UInt32
                let cpuFanRPM: UInt32
                let gpuFanRPM: UInt32
                let batteryChargePercent: Int
                let batteryChargeLimitPercent: Int
                let batteryHealthPercent: Int
                let batteryPowerWatts: Double
                let thermalProfile: String
                let autoSwitchProfilesOnPowerChange: Bool
                let customFanCurveEnabled: Bool
                let customPPTEnabled: Bool
                let cpuPL1SPLWatts: Int
                let cpuPL2SPPTWatts: Int
                let muxMode: String
                let displayBrightnessPercent: Double
                let keyboardBrightness: String
                let rgbMode: String
                let rgbColorHex: String
                let rgbSpeed: String
            }
            let payload = StatusPayload(
                kextLiveInKernel: bridge.isKextLoaded(),
                kextStagedInAuxKC: bridge.isKextStagedForBoot(),
                abiVersion: snap.abiVersion,
                onACPower: bat.externalConnected,
                cpuTempCelsius: snap.cpuTempCelsius,
                cpuFanRPM: snap.cpuFanRPM,
                gpuFanRPM: snap.gpuFanRPM,
                batteryChargePercent: Int(bat.chargePercent.rounded()),
                batteryChargeLimitPercent: settings.batteryChargeLimitPercent,
                batteryHealthPercent: Int(bat.healthPercent.rounded()),
                batteryPowerWatts: bat.powerWatts,
                thermalProfile: settings.thermalProfile.displayName,
                autoSwitchProfilesOnPowerChange: settings.autoSwitchProfileOnPowerChange,
                customFanCurveEnabled: settings.customFanCurveEnabled,
                customPPTEnabled: settings.customPPTEnabled,
                cpuPL1SPLWatts: settings.cpuPL1SPLWatts,
                cpuPL2SPPTWatts: settings.cpuPL2SPPTWatts,
                muxMode: snap.muxStateRawDSTS == 0x10000 ? "Ultimate (Direct RTX 3060 dGPU)" : "Standard (Optimus)",
                displayBrightnessPercent: brtPct,
                keyboardBrightness: settings.keyboardBrightness.displayName,
                rgbMode: settings.rgbMode.displayName,
                rgbColorHex: hexColor,
                rgbSpeed: settings.rgbSpeed.displayName
            )
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(payload)
            print(String(data: data, encoding: .utf8) ?? "{}")
            return
        }

        print("================================================================================")
        print(" ASUS Control for macOS — Live System Status (ASUS TUF Gaming F17 FX707ZM)")
        print("================================================================================")
        print("  Bridge Status    : \(bridge.isKextLoaded() ? "Live In-Kernel (ABI v\(snap.abiVersion))" : "Staged in AuxKC + Active State Store (ABI v\(snap.abiVersion))")")
        print("  Power Source     : \(bat.externalConnected ? "AC Power Connected" : "Battery Power") (\(bat.isCharging ? "Charging" : (bat.fullyCharged ? "Fully Charged" : "Discharging")))")
        print("  Battery Telemetry: \(bat.chargePercent)% | Charge Limit: \(settings.batteryChargeLimitPercent)% | Health: \(bat.healthPercent)% | Power: \(String(format: "%.1f", bat.powerWatts)) W")
        print("  Thermal Profile  : \(settings.thermalProfile.displayName) (WMI Code \(settings.thermalProfile.wmiCode)) | Auto AC/Bat Switch: \(settings.autoSwitchProfileOnPowerChange ? "ON" : "OFF")")
        print("  CPU Telemetry    : \(snap.cpuTempCelsius) °C | PL1 (SPL): \(settings.cpuPL1SPLWatts) W | PL2 (SPPT): \(settings.cpuPL2SPPTWatts) W (Custom PPT: \(settings.customPPTEnabled ? "ACTIVE" : "Profile Default"))")
        print("  Cooling Fans     : CPU Fan = \(snap.cpuFanRPM) RPM | GPU Fan = \(snap.gpuFanRPM) RPM | Custom Curve: \(settings.customFanCurveEnabled ? "ACTIVE" : "Firmware Auto")")
        print("  GPU / MUX Mode   : \(snap.muxStateRawDSTS == 0x10000 ? "Ultimate (Direct RTX 3060 -> LGD066C 300Hz)" : "Standard")")
        print("  Display Panel    : LGD066C Brightness = \(String(format: "%.1f%%", brtPct)) (NVRMBacklightHandler)")
        print("  TUF Keyboard RGB : Mode = \(settings.rgbMode.displayName) | Color = \(hexColor) | Speed = \(settings.rgbSpeed.displayName) | Backlight = \(settings.keyboardBrightness.displayName)")
        print("================================================================================")
    }

    static func parseFanCurveString(_ str: String) throws -> ([UInt8], [UInt8]) {
        let pairs = str.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard pairs.count == 8 else {
            throw NSError(domain: "asusctl", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Expected 8 comma-separated temp:duty pairs (e.g. 45:15,52:20,58:28,64:35,70:45,75:58,80:72,85:88)."])
        }
        var temps: [UInt8] = []
        var duties: [UInt8] = []
        for p in pairs {
            let parts = p.split(separator: ":")
            guard parts.count == 2,
                  let t = UInt8(parts[0].replacingOccurrences(of: "C", with: "").replacingOccurrences(of: "°", with: "")),
                  let d = UInt8(parts[1].replacingOccurrences(of: "%", with: "")) else {
                throw NSError(domain: "asusctl", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid point '\(p)'. Expected <temp>:<duty>."])
            }
            temps.append(t)
            duties.append(d)
        }
        return (temps, duties)
    }

    static func runSelfTest() -> Bool {
        print("================================================================================")
        print(" ASUS Control for macOS — Full Phase 2..5 Verification & Safety Test Suite")
        print("================================================================================")
        var passed = 0
        var total = 0

        func check(_ condition: Bool, _ label: String) {
            total += 1
            if condition {
                passed += 1
                print("  [PASS] \(label)")
            } else {
                print("  [FAIL] \(label)")
            }
        }

        let bridge = AsusBridgeClient()
        let lighting = TufKeyboardLightingController()
        let brightness = DisplayBrightnessController()
        let originalSettings = SettingsStore.shared.load()
        let originalBrightness = (try? brightness.getBrightnessPercent()) ?? 75.0

        // --- Phase 2 Verification: Battery Charge Limit (60%, 80%, 100%) + Guardrails ---
        print("\n[Phase 2] Battery Charge Limit Control (0x00120057 / EC0.SRSC)")
        do {
            try bridge.setChargeLimit(80)
            check(SettingsStore.shared.load().batteryChargeLimitPercent == 80, "Set battery charge limit to 80% & persisted")
            try bridge.setChargeLimit(60)
            check(SettingsStore.shared.load().batteryChargeLimitPercent == 60, "Set battery charge limit to 60% & persisted")
            try bridge.setChargeLimit(100)
            check(SettingsStore.shared.load().batteryChargeLimitPercent == 100, "Set battery charge limit to 100% & persisted")
        } catch {
            check(false, "Valid battery charge limit failed: \(error.localizedDescription)")
        }

        do {
            try bridge.setChargeLimit(45)
            check(false, "Rejected out-of-range charge limit 45% (unexpectedly succeeded)")
        } catch {
            check(true, "Guardrail rejected out-of-range charge limit (45% < 60%)")
        }

        // --- Phase 3 Verification: Thermal Profiles, Fan Curves, & CPU Power Limits ---
        print("\n[Phase 3] Thermal Profiles, 8-Point Fan Curves, & CPU Power Limits (PL1/PL2)")
        do {
            try bridge.setThermalProfile(.silent)
            check(SettingsStore.shared.load().thermalProfile == .silent, "Switched thermal profile to Silent (0x00120075 -> 2)")
            try bridge.setThermalProfile(.balanced)
            check(SettingsStore.shared.load().thermalProfile == .balanced, "Switched thermal profile to Performance/Balanced (0x00120075 -> 0)")
            if IORegistryInspector().inspectBattery().externalConnected {
                try bridge.setThermalProfile(.turbo)
                check(SettingsStore.shared.load().thermalProfile == .turbo, "Switched thermal profile to Turbo on AC power (0x00120075 -> 1)")
                try bridge.setThermalProfile(.balanced)
            }
        } catch {
            check(false, "Thermal profile switching failed: \(error.localizedDescription)")
        }

        do {
            let cpuBalanced = try bridge.readFanCurve(fanIndex: 0, profileIndex: 0)
            let gpuSilent = try bridge.readFanCurve(fanIndex: 1, profileIndex: 2)
            check(cpuBalanced.temperaturesCelsius.count == 8 && gpuSilent.temperaturesCelsius.count == 8,
                  "Read 8-point firmware fan curves (CPU Balanced: \(cpuBalanced.temperaturesCelsius.first ?? 0)..\(cpuBalanced.temperaturesCelsius.last ?? 0)°C, GPU Silent: \(gpuSilent.temperaturesCelsius.first ?? 0)..\(gpuSilent.temperaturesCelsius.last ?? 0)°C)")

            let customTemps: [UInt8] = [45, 52, 58, 64, 70, 75, 80, 85]
            let customDuties: [UInt8] = [15, 20, 28, 36, 45, 58, 72, 85]
            try bridge.writeCustomFanCurve(fanIndex: 0, temperatures: customTemps, dutiesPercent: customDuties)
            check(SettingsStore.shared.load().customFanCurveEnabled == true && SettingsStore.shared.load().customCPUFanDuties == customDuties,
                  "Applied validated 8-point custom CPU fan curve (45°C:15% .. 85°C:85%)")

            try bridge.resetFanCurveToAuto(fanIndex: 0)
            check(SettingsStore.shared.load().customFanCurveEnabled == false,
                  "Reset fan curve to firmware automatic control (EC0.FMAE = 0)")
        } catch {
            check(false, "Fan curve control failed: \(error.localizedDescription)")
        }

        do {
            // Unsafe curve with top point < 40% must be rejected
            try bridge.writeCustomFanCurve(
                fanIndex: 0,
                temperatures: [45, 50, 55, 60, 65, 70, 75, 80],
                dutiesPercent: [10, 15, 20, 20, 25, 25, 30, 30]
            )
            check(false, "Rejected unsafe fan curve with max duty 30% < 40% (unexpectedly succeeded)")
        } catch {
            check(true, "Safety guardrail rejected unsafe fan curve (point 8 duty 30% < 40%)")
        }

        do {
            try bridge.setCPUPowerLimits(pl1SPLWatts: 45, pl2SPPTWatts: 65)
            let s = SettingsStore.shared.load()
            check(s.customPPTEnabled && s.cpuPL1SPLWatts == 45 && s.cpuPL2SPPTWatts == 65,
                  "Applied safe CPU power limits PL1 (SPL) = 45W (0x001200A3) & PL2 (SPPT) = 65W (0x001200A0)")
        } catch {
            check(false, "CPU PPT control failed: \(error.localizedDescription)")
        }

        do {
            try bridge.setCPUPowerLimits(pl1SPLWatts: 130, pl2SPPTWatts: 150)
            check(false, "Rejected unsafe CPU power limits 130W/150W (unexpectedly succeeded)")
        } catch {
            check(true, "Safety guardrail rejected out-of-range CPU power limits (130W/150W)")
        }

        // --- Phase 4 Verification: Display Brightness & Hotkey Event Handling ---
        print("\n[Phase 4] Internal Display Brightness (LGD066C / NVRMBacklightHandler) & Hotkeys")
        do {
            let initialBrt = try brightness.getBrightnessPercent()
            let targetBrt = initialBrt > 20.0 ? (initialBrt - 6.25) : (initialBrt + 6.25)
            let updatedBrt = try brightness.setBrightnessPercent(targetBrt)
            check(abs(updatedBrt - targetBrt) < 3.0,
                  String(format: "Changed internal panel brightness via DisplayServices (%.1f%% -> %.1f%%)", initialBrt, updatedBrt))
            let afterHotkey = try brightness.handleHotkeyEvent(code: 0x86) // Brightness Up (PEGP.EDP1 Notify 0x86)
            check(afterHotkey != nil,
                  String(format: "Handled PEGP.EDP1 Notify 0x86 (Fn+F8 Brightness Up) -> %.1f%%", afterHotkey ?? 0.0))
            _ = try brightness.setBrightnessPercent(originalBrightness)
        } catch {
            check(false, "Display brightness control failed: \(error.localizedDescription)")
        }

        // --- Phase 5 Verification: TUF Gaming Keyboard RGB & Backlight Brightness ---
        print("\n[Phase 5] TUF Gaming Keyboard RGB (0x00100056 / 0x00100057) & Backlight (EC0.SKEY)")
        do {
            try lighting.applyLighting(mode: .breathe, red: 0x00, green: 0xE5, blue: 0xFF, speed: .medium, brightness: .high)
            let s1 = SettingsStore.shared.load()
            check(s1.rgbMode == .breathe && s1.rgbGreen == 0xE5 && s1.rgbBlue == 0xFF && s1.keyboardBrightness == .high,
                  "Applied TUF RGB Breathing (#00E5FF, Speed=Medium, Brightness=High)")

            try lighting.applyLighting(mode: .staticColor, red: 0xFF, green: 0xAA, blue: 0x00, speed: .medium, brightness: .medium)
            let s2 = SettingsStore.shared.load()
            check(s2.rgbMode == .staticColor && s2.rgbRed == 0xFF && s2.rgbGreen == 0xAA && s2.keyboardBrightness == .medium,
                  "Applied TUF RGB Static (#FFAA00 TUF Amber, Brightness=Medium)")
        } catch {
            check(false, "TUF keyboard RGB control failed: \(error.localizedDescription)")
        }

        // Restore original user settings
        SettingsStore.shared.save(originalSettings)
        SettingsStore.shared.applySavedSettingsToHardware()

        print("--------------------------------------------------------------------------------")
        print(" Verification Summary: \(passed)/\(total) CHECKS PASSED (\(passed == total ? "100% ZERO REGRESSIONS" : "FAILED"))")
        print("================================================================================")
        return passed == total
    }

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let first = args.first else {
            try? cmdStatus(json: false)
            return
        }

        let bridge = AsusBridgeClient()
        let lighting = TufKeyboardLightingController()
        let brightness = DisplayBrightnessController()

        do {
            switch first {
            case "--help", "-h", "help":
                printUsage()

            case "--self-test", "self-test":
                if !runSelfTest() { exit(1) }

            case "status":
                try cmdStatus(json: args.contains("--json"))

            case "apply-saved":
                SettingsStore.shared.applySavedSettingsToHardware()
                print("[OK] Applied saved settings from ~/.config/asus-control/settings.json to hardware.")

            case "battery":
                guard args.count >= 3, args[1] == "limit", let limit = Int(args[2]) else {
                    print("Usage: asusctl battery limit <60..100>")
                    exit(1)
                }
                try bridge.setChargeLimit(limit)
                print("[OK] Battery charge limit set to \(limit)% (DEVS 0x00120057 + EC0.SRSC).")

            case "profile":
                guard args.count >= 2 else {
                    print("Current thermal profile: \(SettingsStore.shared.load().thermalProfile.displayName)")
                    return
                }
                if args[1] == "auto" {
                    guard args.count >= 3 else {
                        print("Usage: asusctl profile auto <on|off> [--ac <profile>] [--battery <profile>]")
                        exit(1)
                    }
                    let enabled = (args[2].lowercased() == "on" || args[2].lowercased() == "true" || args[2] == "1")
                    var acProf: ThermalProfile?
                    var batProf: ThermalProfile?
                    var idx = 3
                    while idx + 1 < args.count {
                        if args[idx] == "--ac" { acProf = parseProfile(args[idx + 1]) }
                        if args[idx] == "--battery" { batProf = parseProfile(args[idx + 1]) }
                        idx += 2
                    }
                    SettingsStore.shared.update {
                        $0.autoSwitchProfileOnPowerChange = enabled
                        if let acProf { $0.acPreferredProfile = acProf }
                        if let batProf { $0.batteryPreferredProfile = batProf }
                    }
                    let s = SettingsStore.shared.load()
                    print("[OK] Auto profile switching: \(s.autoSwitchProfileOnPowerChange ? "ON" : "OFF") (AC: \(s.acPreferredProfile.displayName), Battery: \(s.batteryPreferredProfile.displayName)).")
                    return
                }
                guard let prof = parseProfile(args[1]) else {
                    print("Unknown profile '\(args[1])'. Valid profiles: silent, balanced, turbo")
                    exit(1)
                }
                let summary = try bridge.applyFullThermalProfile(prof)
                print("[OK] \(summary)")

            case "fan":
                let sub = args.count >= 2 ? args[1] : "curves"
                switch sub {
                case "curves", "status":
                    let snap = try bridge.fetchSnapshot()
                    let s = SettingsStore.shared.load()
                    print("Live Fan Speeds: CPU Fan = \(snap.cpuFanRPM) RPM | GPU Fan = \(snap.gpuFanRPM) RPM | Custom Curve Active = \(s.customFanCurveEnabled)")
                    for p in 0...2 {
                        for f in 0...1 {
                            let c = try bridge.readFanCurve(fanIndex: f, profileIndex: p)
                            let pairs = zip(c.temperaturesCelsius, c.dutyPercentEstimated).map { "\($0.0)°C:\($0.1)%" }.joined(separator: ", ")
                            print("  * \(c.fanName) [\(c.profileName)]: \(pairs)")
                        }
                    }
                    if s.customFanCurveEnabled {
                        let cpuPairs = zip(s.customCPUFanTemps, s.customCPUFanDuties).map { "\($0.0)°C:\($0.1)%" }.joined(separator: ", ")
                        let gpuPairs = zip(s.customGPUFanTemps, s.customGPUFanDuties).map { "\($0.0)°C:\($0.1)%" }.joined(separator: ", ")
                        print("  * Custom Active CPU Curve: \(cpuPairs)")
                        print("  * Custom Active GPU Curve: \(gpuPairs)")
                    }
                case "set":
                    guard args.count >= 4 else {
                        print("Usage: asusctl fan set <cpu|gpu> <t1:d1,t2:d2,...,t8:d8>")
                        exit(1)
                    }
                    let fanIdx = args[2].lowercased() == "gpu" ? 1 : 0
                    let (temps, duties) = try parseFanCurveString(args[3])
                    try bridge.writeCustomFanCurve(fanIndex: fanIdx, temperatures: temps, dutiesPercent: duties)
                    let pairs = zip(temps, duties).map { "\($0.0)°C:\($0.1)%" }.joined(separator: ", ")
                    print("[OK] Applied custom 8-point \(fanIdx == 0 ? "CPU" : "GPU") fan curve: \(pairs)")
                case "reset":
                    let target = args.count >= 3 ? args[2].lowercased() : "all"
                    if target == "cpu" || target == "all" {
                        try bridge.resetFanCurveToAuto(fanIndex: 0)
                    }
                    if target == "gpu" || target == "all" {
                        try bridge.resetFanCurveToAuto(fanIndex: 1)
                    }
                    print("[OK] Reset fan curves to automatic firmware control (EC0.FMAE = 0).")
                default:
                    print("Unknown fan subcommand '\(sub)'.")
                    exit(1)
                }

            case "ppt":
                let sub = args.count >= 2 ? args[1] : "status"
                switch sub {
                case "set":
                    guard args.count >= 4, let pl1 = Int(args[2]), let pl2 = Int(args[3]) else {
                        print("Usage: asusctl ppt set <pl1_watts> <pl2_watts>")
                        exit(1)
                    }
                    try bridge.setCPUPowerLimits(pl1SPLWatts: pl1, pl2SPPTWatts: pl2)
                    print("[OK] Set CPU Power Limits: PL1 (SPL) = \(pl1) W (0x001200A3 -> EC0.PL1V), PL2 (SPPT) = \(pl2) W (0x001200A0 -> EC0.PL2V).")
                case "reset":
                    SettingsStore.shared.update {
                        $0.customPPTEnabled = false
                        $0.cpuPL1SPLWatts = 45
                        $0.cpuPL2SPPTWatts = 65
                    }
                    let prof = SettingsStore.shared.load().thermalProfile
                    _ = try? bridge.setThermalProfile(prof)
                    print("[OK] Reset CPU power limits to firmware profile default (\(prof.displayName)).")
                default:
                    let s = SettingsStore.shared.load()
                    print("CPU Power Limits: Custom Enabled = \(s.customPPTEnabled) | PL1 (SPL) = \(s.cpuPL1SPLWatts) W | PL2 (SPPT) = \(s.cpuPL2SPPTWatts) W")
                }

            case "brightness":
                let sub = args.count >= 2 ? args[1].lowercased() : "get"
                switch sub {
                case "get":
                    let pct = try brightness.getBrightnessPercent()
                    print(String(format: "Internal Panel (LGD066C) Brightness: %.1f%%", pct))
                case "set":
                    guard args.count >= 3, let val = Double(args[2]) else {
                        print("Usage: asusctl brightness set <0..100>")
                        exit(1)
                    }
                    let updated = try brightness.setBrightnessPercent(val)
                    print(String(format: "[OK] Set internal panel brightness to %.1f%%", updated))
                case "up":
                    let step = (args.count >= 3 ? Double(args[2]) : nil) ?? DisplayBrightnessController.standardStepPercent
                    let updated = try brightness.stepUp(by: step)
                    print(String(format: "[OK] Stepped internal panel brightness UP to %.1f%%", updated))
                case "down":
                    let step = (args.count >= 3 ? Double(args[2]) : nil) ?? DisplayBrightnessController.standardStepPercent
                    let updated = try brightness.stepDown(by: step)
                    print(String(format: "[OK] Stepped internal panel brightness DOWN to %.1f%%", updated))
                case "hotkey":
                    let dir = args.count >= 3 ? args[2].lowercased() : "up"
                    let code: UInt32 = (dir == "down" || dir == "0x87" || dir == "0x10") ? 0x87 : 0x86
                    if let updated = try brightness.handleHotkeyEvent(code: code) {
                        print(String(format: "[OK] Handled brightness hotkey 0x%02X -> %.1f%%", code, updated))
                    }
                default:
                    print("Usage: asusctl brightness <get|set <0..100>|up|down|hotkey <up|down>>")
                    exit(1)
                }

            case "lighting", "rgb", "kbd":
                let sub = args.count >= 2 ? args[1].lowercased() : "status"
                switch sub {
                case "status":
                    let s = SettingsStore.shared.load()
                    let hex = TufKeyboardLightingController.formatHexColor(red: s.rgbRed, green: s.rgbGreen, blue: s.rgbBlue)
                    print("TUF Keyboard Lighting: Mode=\(s.rgbMode.displayName) | Color=\(hex) | Speed=\(s.rgbSpeed.displayName) | Brightness=\(s.keyboardBrightness.displayName)")
                case "mode":
                    guard args.count >= 3, let mode = parseRGBMode(args[2]) else {
                        print("Usage: asusctl lighting mode <static|breathing|cycle|strobe> [--color <#RRGGBB>] [--speed <slow|medium|fast>]")
                        exit(1)
                    }
                    var r: UInt8?
                    var g: UInt8?
                    var b: UInt8?
                    var spd: TufRGBSpeed?
                    var idx = 3
                    while idx + 1 < args.count {
                        if args[idx] == "--color" {
                            let parsed = try TufKeyboardLightingController.parseHexColor(args[idx + 1])
                            r = parsed.red; g = parsed.green; b = parsed.blue
                        } else if args[idx] == "--speed" {
                            spd = parseRGBSpeed(args[idx + 1])
                        }
                        idx += 2
                    }
                    try lighting.applyLighting(mode: mode, red: r, green: g, blue: b, speed: spd)
                    let s = SettingsStore.shared.load()
                    let hex = TufKeyboardLightingController.formatHexColor(red: s.rgbRed, green: s.rgbGreen, blue: s.rgbBlue)
                    print("[OK] TUF RGB Mode set to \(s.rgbMode.displayName) (Color: \(hex), Speed: \(s.rgbSpeed.displayName)).")
                case "color":
                    guard args.count >= 3 else {
                        print("Usage: asusctl lighting color <#RRGGBB>")
                        exit(1)
                    }
                    let rgb = try TufKeyboardLightingController.parseHexColor(args[2])
                    try lighting.applyLighting(red: rgb.red, green: rgb.green, blue: rgb.blue)
                    let hex = TufKeyboardLightingController.formatHexColor(red: rgb.red, green: rgb.green, blue: rgb.blue)
                    print("[OK] TUF RGB Color set to \(hex).")
                case "speed":
                    guard args.count >= 3, let spd = parseRGBSpeed(args[2]) else {
                        print("Usage: asusctl lighting speed <slow|medium|fast>")
                        exit(1)
                    }
                    try lighting.applyLighting(speed: spd)
                    print("[OK] TUF RGB Speed set to \(spd.displayName).")
                case "brightness":
                    guard args.count >= 3, let lvl = parseKbdBrightness(args[2]) else {
                        print("Usage: asusctl lighting brightness <0|1|2|3|off|low|medium|high>")
                        exit(1)
                    }
                    try lighting.setBrightnessLevel(lvl)
                    print("[OK] Keyboard Backlight Brightness set to \(lvl.displayName).")
                default:
                    print("Usage: asusctl lighting <status|mode|color|speed|brightness>")
                    exit(1)
                }

            default:
                printUsage()
                exit(1)
            }
        } catch {
            print("[ERROR] \(error.localizedDescription)")
            exit(1)
        }
    }
}
