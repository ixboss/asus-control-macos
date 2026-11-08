import Foundation
import CoreGraphics
import Darwin

/// Controls internal display brightness on the FX707ZM (`LGD066C` on `RTX 3060` via `NVRMBacklightHandler`)
/// using `DisplayServices.framework` (`DisplayServicesGetBrightness` / `DisplayServicesSetBrightness`),
/// and bridges ACPI `PEGP.EDP1` (`0x86`/`0x87`) and `ATKD` (`0x10`/`0x20`) brightness hotkeys.
public struct DisplayBrightnessController: Sendable {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    public static let standardStepPercent: Double = 6.25 // 1/16th standard macOS brightness step

    public init() {}

    private func targetDisplayIDs() -> [UInt32] {
        let mainID = CGMainDisplayID()
        return mainID != 0 ? [mainID, 1] : [1]
    }

    /// Reads current internal panel brightness as a percentage (`0.0 ... 100.0`).
    public func getBrightnessPercent() throws -> Double {
        guard let handle = dlopen(Self.frameworkPath, RTLD_LAZY) else {
            throw NSError(domain: "DisplayBrightnessController", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load DisplayServices.framework"])
        }
        defer { dlclose(handle) }

        typealias GetBrtFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
        guard let sym = dlsym(handle, "DisplayServicesGetBrightness") else {
            throw NSError(domain: "DisplayBrightnessController", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "DisplayServicesGetBrightness symbol not found"])
        }
        let getFn = unsafeBitCast(sym, to: GetBrtFn.self)

        for id in targetDisplayIDs() {
            var val: Float = -1.0
            if getFn(id, &val) == 0 && val >= 0.0 {
                return Double(min(1.0, max(0.0, val))) * 100.0
            }
        }
        // Fallback to IORegistry AppleBacklightDisplay if headless/locked
        let brtReport = IORegistryInspector().inspectBrightness()
        if let pct = brtReport.softwareBrightnessPercent {
            return Double(pct)
        }
        throw NSError(domain: "DisplayBrightnessController", code: -3,
                      userInfo: [NSLocalizedDescriptionKey: "Unable to read brightness from DisplayServices"])
    }

    /// Sets internal panel brightness to `percent` (`0.0 ... 100.0`).
    @discardableResult
    public func setBrightnessPercent(_ percent: Double) throws -> Double {
        guard percent >= 0.0 && percent <= 100.0 else {
            throw NSError(domain: "DisplayBrightnessController", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "Brightness percentage must be between 0 and 100."])
        }
        let normalized = Float(min(100.0, max(0.0, percent)) / 100.0)

        guard let handle = dlopen(Self.frameworkPath, RTLD_LAZY) else {
            throw NSError(domain: "DisplayBrightnessController", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load DisplayServices.framework"])
        }
        defer { dlclose(handle) }

        typealias SetBrtFn = @convention(c) (UInt32, Float) -> Int32
        typealias NotifyFn = @convention(c) (UInt32, Double) -> Void

        guard let sym = dlsym(handle, "DisplayServicesSetBrightness") else {
            throw NSError(domain: "DisplayBrightnessController", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "DisplayServicesSetBrightness symbol not found"])
        }
        let setFn = unsafeBitCast(sym, to: SetBrtFn.self)
        let notifySym = dlsym(handle, "DisplayServicesBrightnessChanged")

        var applied = false
        for id in targetDisplayIDs() {
            if setFn(id, normalized) == 0 {
                if let notifySym {
                    let notifyFn = unsafeBitCast(notifySym, to: NotifyFn.self)
                    notifyFn(id, Double(normalized))
                }
                applied = true
                break
            }
        }

        guard applied else {
            throw NSError(domain: "DisplayBrightnessController", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "DisplayServicesSetBrightness returned error on internal panel."])
        }

        let updated = (try? getBrightnessPercent()) ?? Double(normalized * 100.0)
        SettingsStore.shared.update {
            $0.lastDisplayBrightnessPercent = updated
        }
        return updated
    }

    /// Steps brightness up (`+6.25%` default) and returns the new percentage.
    @discardableResult
    public func stepUp(by deltaPercent: Double = Self.standardStepPercent) throws -> Double {
        let current = try getBrightnessPercent()
        let target = min(100.0, current + abs(deltaPercent))
        return try setBrightnessPercent(target)
    }

    /// Steps brightness down (`-6.25%` default) and returns the new percentage.
    @discardableResult
    public func stepDown(by deltaPercent: Double = Self.standardStepPercent) throws -> Double {
        let current = try getBrightnessPercent()
        let target = max(0.0, current - abs(deltaPercent))
        return try setBrightnessPercent(target)
    }

    /// Handles an ACPI / ATKD / PEGP.EDP1 hotkey notification code (`0x86` / `0x20` = Up, `0x87` / `0x10` = Down).
    /// Returns the new brightness percentage if the key code is a display brightness hotkey, or `nil` otherwise.
    @discardableResult
    public func handleHotkeyEvent(code: UInt32) throws -> Double? {
        switch code {
        case 0x86, 0x20: // ACPI video brightness up (0x86 on PEGP.EDP1) or ATKD brightness up (0x20)
            return try stepUp()
        case 0x87, 0x10: // ACPI video brightness down (0x87 on PEGP.EDP1) or ATKD brightness down (0x10)
            return try stepDown()
        default:
            return nil
        }
    }
}
