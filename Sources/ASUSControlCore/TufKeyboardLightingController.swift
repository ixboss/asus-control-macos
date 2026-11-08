import Foundation

/// High-level controller for ASUS TUF Gaming F17 (`FX707ZM`) keyboard RGB lighting (`0x00100056` / `0x00100057`)
/// and keyboard backlight brightness (`0x0010005B` / `EC0.SKEY` `0xC4` & `0xC5`).
public struct TufKeyboardLightingController: Sendable {
    private let bridge = AsusBridgeClient()

    public init() {}

    /// Parses a `#RRGGBB` or `RRGGBB` hex string into `(UInt8, UInt8, UInt8)`.
    public static func parseHexColor(_ hex: String) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "")
        guard cleaned.count == 6, let val = UInt32(cleaned, radix: 16) else {
            throw NSError(domain: "TufKeyboardLightingController", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid RGB hex color '\(hex)'. Expected #RRGGBB (e.g. #FFAA00)."])
        }
        return (
            red: UInt8((val >> 16) & 0xFF),
            green: UInt8((val >> 8) & 0xFF),
            blue: UInt8(val & 0xFF)
        )
    }

    public static func formatHexColor(red: UInt8, green: UInt8, blue: UInt8) -> String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// Applies TUF Gaming RGB mode, RGB color, and speed via `AsusBridgeClient`, scaling RGB intensity by active brightness level.
    @discardableResult
    public func applyLighting(
        mode: TufRGBMode? = nil,
        red: UInt8? = nil,
        green: UInt8? = nil,
        blue: UInt8? = nil,
        speed: TufRGBSpeed? = nil,
        brightness: KeyboardBrightnessLevel? = nil
    ) throws -> String {
        let current = SettingsStore.shared.load()
        let targetMode = mode ?? current.rgbMode
        let targetR = red ?? current.rgbRed
        let targetG = green ?? current.rgbGreen
        let targetB = blue ?? current.rgbBlue
        let targetSpeed = speed ?? current.rgbSpeed

        // If user explicitly changes RGB mode/color/speed while brightness was Off, automatically raise brightness to High (3)
        var targetBrightness = brightness ?? current.keyboardBrightness
        if brightness == nil && targetBrightness == .off && (mode != nil || red != nil || green != nil || blue != nil) {
            targetBrightness = .high
        }

        // Step 1: Set hardware keyboard brightness level (0x00050021 -> 0x80 | level, plus EC0.SKEY fallback)
        let brtRes = try bridge.setKeyboardBrightness(targetBrightness)

        // Step 2: Scale RGB output intensity according to brightness level (0=0%, 1=35%, 2=70%, 3=100%)
        let scale: Double
        switch targetBrightness {
        case .off:    scale = 0.0
        case .low:    scale = 0.35
        case .medium: scale = 0.70
        case .high:   scale = 1.00
        }
        let effR = UInt8((Double(targetR) * scale).rounded())
        let effG = UInt8((Double(targetG) * scale).rounded())
        let effB = UInt8((Double(targetB) * scale).rounded())

        let rgbRes = try bridge.setTufRGB(
            mode: targetMode,
            red: effR,
            green: effG,
            blue: effB,
            speed: targetSpeed,
            saveToFirmware: true
        )

        // Preserve user's base unscaled RGB color and chosen brightness in SettingsStore
        SettingsStore.shared.update {
            $0.rgbMode = targetMode
            $0.rgbRed = targetR
            $0.rgbGreen = targetG
            $0.rgbBlue = targetB
            $0.rgbSpeed = targetSpeed
            $0.keyboardBrightness = targetBrightness
        }

        let hexStr = Self.formatHexColor(red: targetR, green: targetG, blue: targetB)
        return String(format: "RGB %@ (%@, %@) • Backlight: %@ [WMI 0x100056=0x%X, 0x100057=0x%X]",
                      targetMode.displayName, hexStr, targetSpeed.displayName, targetBrightness.displayName,
                      rgbRes.0, rgbRes.1)
    }

    /// Sets keyboard backlight brightness level (`0...3`).
    @discardableResult
    public func setBrightnessLevel(_ level: KeyboardBrightnessLevel) throws -> String {
        try applyLighting(brightness: level)
    }

    /// Cycles to the next TUF RGB mode (`Static -> Breathing -> Color Cycle -> Strobe`).
    @discardableResult
    public func cycleMode() throws -> TufRGBMode {
        let current = SettingsStore.shared.load()
        let nextRaw = (current.rgbMode.rawValue + 1) % 4
        let nextMode = TufRGBMode(rawValue: nextRaw) ?? .staticColor
        try applyLighting(mode: nextMode)
        return nextMode
    }
}
