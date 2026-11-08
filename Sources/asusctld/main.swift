import Foundation
import AppKit
import ASUSControlCore

@main
struct AsusCtlDaemonMain {
    static func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        print("[\(ts)] [asusctld] \(message)")
        fflush(stdout)
    }

    static func ensureKextLoadedIfRoot() {
        let bridge = AsusBridgeClient()
        guard !bridge.isKextLoaded(), geteuid() == 0 else { return }

        let srcPath = "/Library/Application Support/ASUSControl/AsusBridge.kext"
        let dstPath = "/tmp/AsusBridge.kext"
        let fm = FileManager.default
        if fm.fileExists(atPath: srcPath) {
            try? fm.removeItem(atPath: dstPath)
            try? fm.copyItem(atPath: srcPath, toPath: dstPath)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/kmutil")
            proc.arguments = ["load", "-p", dstPath]
            try? proc.run()
            proc.waitUntilExit()
        }
    }

    static func main() {
        let args = CommandLine.arguments
        let runOnce = args.contains("--once")

        log("Starting ASUS Control Daemon (asusctld v0.2.0) for FX707ZM...")
        ensureKextLoadedIfRoot()

        let bridge = AsusBridgeClient()
        let inspector = IORegistryInspector()
        let brightnessCtrl = DisplayBrightnessController()
        let lightingCtrl = TufKeyboardLightingController()

        // Restore persisted hardware state on startup
        SettingsStore.shared.applySavedSettingsToHardware()
        let initialSettings = SettingsStore.shared.load()
        log("Restored saved settings: ChargeLimit=\(initialSettings.batteryChargeLimitPercent)%, Profile=\(initialSettings.thermalProfile.displayName), RGB=\(initialSettings.rgbMode.displayName)")

        if runOnce {
            log("Completed --once initialization check.")
            return
        }

        // Register Sleep/Wake restoration observer
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let s = SettingsStore.shared.load()
            guard s.restoreOnWake else { return }
            log("System woke from sleep — restoring FX707ZM hardware settings...")
            SettingsStore.shared.applySavedSettingsToHardware()
        }

        final class DaemonLoopState: @unchecked Sendable {
            var lastOnAC: Bool?
            var lastHotkeySeq: UInt32
            init(lastOnAC: Bool?, lastHotkeySeq: UInt32) {
                self.lastOnAC = lastOnAC
                self.lastHotkeySeq = lastHotkeySeq
            }
        }
        let loopState = DaemonLoopState(
            lastOnAC: inspector.inspectBattery().externalConnected,
            lastHotkeySeq: (try? bridge.fetchSnapshot().hotkeySequence) ?? 0
        )

        // Poll timer for AC/Battery transitions and ACPI/ATKD/EDP1 hotkey events
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let bat = inspector.inspectBattery()
            let onAC = bat.externalConnected

            if let prevAC = loopState.lastOnAC, prevAC != onAC {
                loopState.lastOnAC = onAC
                let s = SettingsStore.shared.load()
                log("Power source changed: \(onAC ? "AC Connected" : "On Battery")")
                if s.autoSwitchProfileOnPowerChange {
                    let target = onAC ? s.acPreferredProfile : s.batteryPreferredProfile
                    do {
                        try bridge.setThermalProfile(target)
                        log("Auto-switched thermal profile to \(target.displayName)")
                    } catch {
                        log("Failed to auto-switch profile: \(error.localizedDescription)")
                    }
                } else if !onAC && s.thermalProfile == .turbo {
                    // Safety fallback: Turbo is not supported on battery
                    _ = try? bridge.setThermalProfile(.balanced)
                    log("Downgraded Turbo to Balanced on battery transition.")
                }
            }

            if let snap = try? bridge.fetchSnapshot(), snap.hotkeySequence != loopState.lastHotkeySeq {
                loopState.lastHotkeySeq = snap.hotkeySequence
                let code = snap.lastHotkeyCode
                log(String(format: "Received ACPI hotkey notification code 0x%02X (seq=%u)", code, snap.hotkeySequence))
                switch code {
                case 0x86, 0x20, 0x87, 0x10:
                    if let newBrt = try? brightnessCtrl.handleHotkeyEvent(code: code) {
                        log(String(format: "Adjusted display brightness via hotkey 0x%02X -> %.1f%%", code, newBrt))
                    }
                case 0xB3:
                    if let mode = try? lightingCtrl.cycleMode() {
                        log("Cycled TUF RGB mode via Fn+F4 -> \(mode.displayName)")
                    }
                case 0xAE:
                    let s = SettingsStore.shared.load()
                    let order: [ThermalProfile] = onAC ? [.silent, .balanced, .turbo] : [.silent, .balanced]
                    let idx = order.firstIndex(of: s.thermalProfile) ?? 0
                    let next = order[(idx + 1) % order.count]
                    _ = try? bridge.setThermalProfile(next)
                    log("Cycled thermal profile via Fn+F5 -> \(next.displayName)")
                default:
                    break
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.run()
    }
}
