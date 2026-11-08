import Foundation

/// Persistent user configuration for ASUS Control for macOS (`FX707ZM`).
public struct ASUSControlSettings: Codable, Sendable, Equatable {
    public var batteryChargeLimitPercent: Int
    public var thermalProfile: ThermalProfile
    public var acPreferredProfile: ThermalProfile
    public var batteryPreferredProfile: ThermalProfile
    public var autoSwitchProfileOnPowerChange: Bool
    public var restoreOnWake: Bool

    public var customFanCurveEnabled: Bool
    public var customCPUFanTemps: [UInt8]
    public var customCPUFanDuties: [UInt8]
    public var customGPUFanTemps: [UInt8]
    public var customGPUFanDuties: [UInt8]

    public var customPPTEnabled: Bool
    public var cpuPL1SPLWatts: Int
    public var cpuPL2SPPTWatts: Int

    public var lastDisplayBrightnessPercent: Double
    public var keyboardBrightness: KeyboardBrightnessLevel
    public var rgbMode: TufRGBMode
    public var rgbRed: UInt8
    public var rgbGreen: UInt8
    public var rgbBlue: UInt8
    public var rgbSpeed: TufRGBSpeed

    public init(
        batteryChargeLimitPercent: Int = 80,
        thermalProfile: ThermalProfile = .balanced,
        acPreferredProfile: ThermalProfile = .balanced,
        batteryPreferredProfile: ThermalProfile = .silent,
        autoSwitchProfileOnPowerChange: Bool = true,
        restoreOnWake: Bool = true,
        customFanCurveEnabled: Bool = false,
        customCPUFanTemps: [UInt8] = [50, 56, 62, 66, 70, 74, 78, 82],
        customCPUFanDuties: [UInt8] = [14, 18, 25, 32, 40, 50, 62, 75],
        customGPUFanTemps: [UInt8] = [50, 56, 62, 66, 70, 74, 78, 82],
        customGPUFanDuties: [UInt8] = [10, 15, 22, 30, 38, 48, 60, 72],
        customPPTEnabled: Bool = false,
        cpuPL1SPLWatts: Int = 45,
        cpuPL2SPPTWatts: Int = 65,
        lastDisplayBrightnessPercent: Double = 75.0,
        keyboardBrightness: KeyboardBrightnessLevel = .medium,
        rgbMode: TufRGBMode = .staticColor,
        rgbRed: UInt8 = 255,
        rgbGreen: UInt8 = 170,
        rgbBlue: UInt8 = 0,
        rgbSpeed: TufRGBSpeed = .medium
    ) {
        self.batteryChargeLimitPercent = min(max(batteryChargeLimitPercent, 60), 100)
        self.thermalProfile = thermalProfile
        self.acPreferredProfile = acPreferredProfile
        self.batteryPreferredProfile = batteryPreferredProfile == .turbo ? .balanced : batteryPreferredProfile
        self.autoSwitchProfileOnPowerChange = autoSwitchProfileOnPowerChange
        self.restoreOnWake = restoreOnWake
        self.customFanCurveEnabled = customFanCurveEnabled
        self.customCPUFanTemps = customCPUFanTemps
        self.customCPUFanDuties = customCPUFanDuties
        self.customGPUFanTemps = customGPUFanTemps
        self.customGPUFanDuties = customGPUFanDuties
        self.customPPTEnabled = customPPTEnabled
        self.cpuPL1SPLWatts = cpuPL1SPLWatts
        self.cpuPL2SPPTWatts = cpuPL2SPPTWatts
        self.lastDisplayBrightnessPercent = lastDisplayBrightnessPercent
        self.keyboardBrightness = keyboardBrightness
        self.rgbMode = rgbMode
        self.rgbRed = rgbRed
        self.rgbGreen = rgbGreen
        self.rgbBlue = rgbBlue
        self.rgbSpeed = rgbSpeed
    }
}

/// Thread-safe JSON store for reading/writing `ASUSControlSettings` and applying them to `AsusBridge.kext`.
public final class SettingsStore: @unchecked Sendable {
    public static let shared = SettingsStore()

    private let lock = NSLock()
    public let configFileURL: URL

    public init(customURL: URL? = nil) {
        if let customURL {
            self.configFileURL = customURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let dir = home.appendingPathComponent(".config/asus-control", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.configFileURL = dir.appendingPathComponent("settings.json")
        }
    }

    public func load() -> ASUSControlSettings {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: configFileURL),
              let decoded = try? JSONDecoder().decode(ASUSControlSettings.self, from: data) else {
            return ASUSControlSettings()
        }
        return decoded
    }

    public func save(_ settings: ASUSControlSettings) {
        lock.lock()
        defer { lock.unlock() }
        let dir = configFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings) {
            try? data.write(to: configFileURL, options: .atomic)
        }
    }

    @discardableResult
    public func update(_ mutate: (inout ASUSControlSettings) -> Void) -> ASUSControlSettings {
        var current = load()
        mutate(&current)
        save(current)
        return current
    }

    /// Re-applies all persisted settings to the hardware via `AsusBridgeClient` (used on startup, AC/Battery change, and Sleep/Wake).
    @discardableResult
    public func applySavedSettingsToHardware(bridge: AsusBridgeClient = AsusBridgeClient()) -> [String] {
        var appliedLogs: [String] = []
        guard bridge.isAvailable() else {
            return ["AsusBridge.kext not available; skipped hardware apply."]
        }

        let settings = load()
        let onAC = IORegistryInspector().inspectBattery().externalConnected

        // 1. Battery Charge Limit
        do {
            try bridge.setChargeLimit(settings.batteryChargeLimitPercent)
            appliedLogs.append("Battery charge limit -> \(settings.batteryChargeLimitPercent)%")
        } catch {
            appliedLogs.append("Battery charge limit error: \(error.localizedDescription)")
        }

        // 2. Thermal Profile (based on AC vs Battery if autoSwitchProfileOnPowerChange is enabled)
        let targetProfile: ThermalProfile
        if settings.autoSwitchProfileOnPowerChange {
            targetProfile = onAC ? settings.acPreferredProfile : settings.batteryPreferredProfile
        } else {
            targetProfile = onAC ? settings.thermalProfile : (settings.thermalProfile == .turbo ? .balanced : settings.thermalProfile)
        }
        do {
            try bridge.setThermalProfile(targetProfile)
            appliedLogs.append("Thermal profile -> \(targetProfile.displayName) (onAC=\(onAC))")
        } catch {
            appliedLogs.append("Thermal profile error: \(error.localizedDescription)")
        }

        // 3. Custom Fan Curves (if enabled)
        if settings.customFanCurveEnabled {
            do {
                try bridge.writeCustomFanCurve(
                    fanIndex: 0,
                    temperatures: settings.customCPUFanTemps,
                    dutiesPercent: settings.customCPUFanDuties
                )
                try bridge.writeCustomFanCurve(
                    fanIndex: 1,
                    temperatures: settings.customGPUFanTemps,
                    dutiesPercent: settings.customGPUFanDuties
                )
                appliedLogs.append("CPU & GPU custom 8-point fan curves applied")
            } catch {
                appliedLogs.append("Custom fan curve error: \(error.localizedDescription)")
            }
        }

        // 4. Custom CPU PPT Limits (if enabled)
        if settings.customPPTEnabled {
            let safePL1 = onAC ? min(settings.cpuPL1SPLWatts, 90) : min(settings.cpuPL1SPLWatts, 45)
            let safePL2 = onAC ? min(settings.cpuPL2SPPTWatts, 115) : min(settings.cpuPL2SPPTWatts, 60)
            do {
                try bridge.setCPUPowerLimits(pl1SPLWatts: safePL1, pl2SPPTWatts: max(safePL1, safePL2))
                appliedLogs.append("CPU PPT limits -> PL1=\(safePL1)W, PL2=\(max(safePL1, safePL2))W")
            } catch {
                appliedLogs.append("CPU PPT error: \(error.localizedDescription)")
            }
        }

        // 5. TUF RGB Lighting
        do {
            try TufKeyboardLightingController().applyLighting(
                mode: settings.rgbMode,
                red: settings.rgbRed,
                green: settings.rgbGreen,
                blue: settings.rgbBlue,
                speed: settings.rgbSpeed,
                brightness: settings.keyboardBrightness
            )
            appliedLogs.append(String(format: "TUF RGB -> %@ #%02X%02X%02X (%@, %@)",
                                      settings.rgbMode.displayName,
                                      settings.rgbRed, settings.rgbGreen, settings.rgbBlue,
                                      settings.rgbSpeed.displayName,
                                      settings.keyboardBrightness.displayName))
        } catch {
            appliedLogs.append("TUF RGB error: \(error.localizedDescription)")
        }

        return appliedLogs
    }
}
