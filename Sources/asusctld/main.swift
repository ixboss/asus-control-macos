import Foundation
import AppKit
import IOKit.ps
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

    // MARK: - Sendable box for the C-function-pointer IOPS notification callback
    final class EventBox: @unchecked Sendable {
        let handler: @Sendable () -> Void
        init(handler: @escaping @Sendable () -> Void) { self.handler = handler }
    }

    static func handlePowerSourceChange(onAC: Bool) {
        let s = SettingsStore.shared.load()
        let bridge = AsusBridgeClient()
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

    static func main() {
        let args = CommandLine.arguments
        let runOnce = args.contains("--once")

        log("Starting ASUS Control Daemon (asusctld v0.4.0) for FX707ZM...")
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

        // --------------------------------------------------------------------
        // Wake-from-sleep restoration (NSWorkspace, event-driven — no polling)
        // --------------------------------------------------------------------
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

        // --------------------------------------------------------------------
        // AC/Battery profile switching via IOPSNotificationCreateRunLoopSource
        // (IOKit.ps) — instant, zero idle CPU wakeups (replaces 0.5 s polling)
        // --------------------------------------------------------------------
        let initialOnAC = inspector.inspectBattery().externalConnected
        let powerBox = Unmanaged.passRetained(EventBox { [inspector] in
            let onAC = inspector.inspectBattery().externalConnected
            handlePowerSourceChange(onAC: onAC)
        }).toOpaque()
        if let powerSource = IOPSNotificationCreateRunLoopSource({ refcon in
            guard let refcon else { return }
            let box = Unmanaged<EventBox>.fromOpaque(refcon).takeUnretainedValue()
            box.handler()
        }, powerBox)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .defaultMode)
            log("IOPS power-source notification source installed (event-driven, initial onAC=\(initialOnAC)).")
        } else {
            log("WARNING: IOPSNotificationCreateRunLoopSource failed; power events will follow wake notifications only.")
        }

        // --------------------------------------------------------------------
        // Live IPC: DistributedNotificationCenter "org.asuscontrol.settingsChanged"
        // (posted atomically by SettingsStore on every save/update from asusctl,
        // ASUSControlApp, or this daemon) — refresh daemon-side cached state and
        // mirror the settings file so all three processes agree instantly.
        // --------------------------------------------------------------------
        let ipcRelay = SettingsChangeRelay()
        ipcRelay.rebind { [inspector] in
            let s = SettingsStore.shared.load()
            log("Settings changed externally (org.asuscontrol.settingsChanged): ChargeLimit=\(s.batteryChargeLimitPercent)%, Profile=\(s.thermalProfile.displayName), AutoSwitch=\(s.autoSwitchProfileOnPowerChange)")
            let onAC = inspector.inspectBattery().externalConnected
            handlePowerSourceChange(onAC: onAC)
        }
        DistributedNotificationCenter.default().addObserver(
            ipcRelay,
            selector: #selector(SettingsChangeRelay.settingsChanged(_:)),
            name: Notification.Name(SettingsStore.settingsChangedNotification),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // --------------------------------------------------------------------
        // ACPI/ATKD/EDP1 hotkey events: the kext has no user-space event push,
        // so snapshot polling remains — but at a relaxed 1 s interval and only
        // while AsusBridge is live in-kernel (0 wakeups when staged/AuxKC).
        // --------------------------------------------------------------------
        final class HotkeyLoopState: @unchecked Sendable {
            var lastHotkeySeq: UInt32
            init(lastHotkeySeq: UInt32) { self.lastHotkeySeq = lastHotkeySeq }
        }
        let hotkeyState = HotkeyLoopState(lastHotkeySeq: (try? bridge.fetchSnapshot().hotkeySequence) ?? 0)

        if bridge.isKextLoaded() {
            let hotkeyTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                guard let snap = try? bridge.fetchSnapshot(), snap.hotkeySequence != hotkeyState.lastHotkeySeq else { return }
                hotkeyState.lastHotkeySeq = snap.hotkeySequence
                let code = snap.lastHotkeyCode
                let onAC = inspector.inspectBattery().externalConnected
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
            RunLoop.main.add(hotkeyTimer, forMode: .common)
        } else {
            log("AsusBridge not live in-kernel; hotkey poll disabled (zero idle CPU wakeups).")
        }

        RunLoop.main.run()
    }
}
