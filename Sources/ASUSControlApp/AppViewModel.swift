import Foundation
import SwiftUI
import AppKit
import ASUSControlCore

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var snapshot: DiagnosticSnapshot
    @Published public var bridgeSnapshot: AsusBridgeClient.RawSnapshot?
    @Published public var hardwareVerification: HardwareVerificationReport
    @Published public var settings: ASUSControlSettings
    @Published public var displayBrightnessPercent: Double = 75.0
    @Published public var rgbColorSwiftUI: Color = Color(red: 1.0, green: 0.67, blue: 0.0)
    @Published public var statusBannerMessage: String = "ASUS TUF Gaming F17 (FX707ZM) — Ready"
    @Published public var statusBannerIsError: Bool = false
    @Published public var kernelLogText: String = ""

    // Editable 8-point curves in UI
    @Published public var editCPUTemps: [Double] = [50, 56, 62, 66, 70, 74, 78, 82]
    @Published public var editCPUDuties: [Double] = [14, 18, 25, 32, 40, 50, 62, 75]
    @Published public var editGPUTemps: [Double] = [50, 56, 62, 66, 70, 74, 78, 82]
    @Published public var editGPUDuties: [Double] = [10, 15, 22, 30, 38, 48, 60, 72]

    // Editable PPT sliders
    @Published public var editPL1Watts: Double = 45
    @Published public var editPL2Watts: Double = 65

    private let matrix = FX707ZMCapabilityMatrix()
    private let bridge = AsusBridgeClient()
    private let brightnessCtrl = DisplayBrightnessController()
    private let lightingCtrl = TufKeyboardLightingController()
    private var refreshTimer: Timer?
    private var lastHotkeySeq: UInt32 = 0
    private var lastOnAC: Bool?

    public init() {
        let initialSnap = FX707ZMCapabilityMatrix().captureSnapshot()
        let loadedSettings = SettingsStore.shared.load()
        let client = AsusBridgeClient()
        self.snapshot = initialSnap
        self.settings = loadedSettings
        self.bridgeSnapshot = try? client.fetchSnapshot()
        self.hardwareVerification = client.readLiveHardwareVerification()
        self.displayBrightnessPercent = (try? DisplayBrightnessController().getBrightnessPercent()) ?? loadedSettings.lastDisplayBrightnessPercent
        self.rgbColorSwiftUI = Color(
            red: Double(loadedSettings.rgbRed) / 255.0,
            green: Double(loadedSettings.rgbGreen) / 255.0,
            blue: Double(loadedSettings.rgbBlue) / 255.0
        )
        self.editCPUTemps = loadedSettings.customCPUFanTemps.map(Double.init)
        self.editCPUDuties = loadedSettings.customCPUFanDuties.map(Double.init)
        self.editGPUTemps = loadedSettings.customGPUFanTemps.map(Double.init)
        self.editGPUDuties = loadedSettings.customGPUFanDuties.map(Double.init)
        self.editPL1Watts = Double(loadedSettings.cpuPL1SPLWatts)
        self.editPL2Watts = Double(loadedSettings.cpuPL2SPPTWatts)
        self.kernelLogText = client.readKernelLogProperty() ?? ""
        self.lastOnAC = initialSnap.battery.externalConnected
        self.lastHotkeySeq = self.bridgeSnapshot?.hotkeySequence ?? 0

        startPolling()
    }

    public func startPolling() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTelemetry()
            }
        }
    }

    public func refreshTelemetry() {
        self.snapshot = matrix.captureSnapshot()
        self.settings = SettingsStore.shared.load()
        if let bSnap = try? bridge.fetchSnapshot() {
            self.bridgeSnapshot = bSnap
            if bSnap.hotkeySequence != lastHotkeySeq {
                lastHotkeySeq = bSnap.hotkeySequence
                if let newBrt = try? brightnessCtrl.handleHotkeyEvent(code: bSnap.lastHotkeyCode) {
                    self.displayBrightnessPercent = newBrt
                }
            }
        }
        self.hardwareVerification = bridge.readLiveHardwareVerification()
        if let brt = try? brightnessCtrl.getBrightnessPercent() {
            self.displayBrightnessPercent = brt
        }
        self.kernelLogText = bridge.readKernelLogProperty() ?? ""

        let currentAC = snapshot.battery.externalConnected
        if let prevAC = lastOnAC, prevAC != currentAC {
            lastOnAC = currentAC
            if settings.autoSwitchProfileOnPowerChange {
                let target = currentAC ? settings.acPreferredProfile : settings.batteryPreferredProfile
                setThermalProfile(target)
            }
        }
    }

    private func showStatus(_ msg: String, isError: Bool = false) {
        self.statusBannerMessage = msg
        self.statusBannerIsError = isError
    }

    // MARK: - Actions

    public func setChargeLimit(_ limit: Int) {
        do {
            let raw = try bridge.setChargeLimit(limit)
            self.settings = SettingsStore.shared.load()
            self.bridgeSnapshot = try? bridge.fetchSnapshot()
            self.hardwareVerification = bridge.readLiveHardwareVerification()
            showStatus(String(format: "Battery charge limit set to %d%% (DEVS 0x00120057 = 0x%X, EC0.SRSC)", limit, raw))
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    public func setThermalProfile(_ profile: ThermalProfile) {
        do {
            let summary = try bridge.applyFullThermalProfile(profile)
            self.settings = SettingsStore.shared.load()
            self.editPL1Watts = Double(settings.cpuPL1SPLWatts)
            self.editPL2Watts = Double(settings.cpuPL2SPPTWatts)
            self.bridgeSnapshot = try? bridge.fetchSnapshot()
            self.hardwareVerification = bridge.readLiveHardwareVerification()
            showStatus("\(profile.displayName) Profile: \(summary)")
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    public func toggleAutoSwitchProfile(_ enabled: Bool) {
        self.settings = SettingsStore.shared.update {
            $0.autoSwitchProfileOnPowerChange = enabled
        }
        showStatus("Automatic AC/Battery Profile Switching: \(enabled ? "Enabled" : "Disabled")")
    }

    public func setACPreferredProfile(_ profile: ThermalProfile) {
        self.settings = SettingsStore.shared.update {
            $0.acPreferredProfile = profile
        }
    }

    public func setBatteryPreferredProfile(_ profile: ThermalProfile) {
        let safe = profile == .turbo ? .balanced : profile
        self.settings = SettingsStore.shared.update {
            $0.batteryPreferredProfile = safe
        }
    }

    public func toggleRestoreOnWake(_ enabled: Bool) {
        self.settings = SettingsStore.shared.update {
            $0.restoreOnWake = enabled
        }
    }

    public func loadFirmwareFanPreset(profileIndex: Int) {
        if let cpuCurve = try? bridge.readFanCurve(fanIndex: 0, profileIndex: profileIndex),
           let gpuCurve = try? bridge.readFanCurve(fanIndex: 1, profileIndex: profileIndex) {
            self.editCPUTemps = cpuCurve.temperaturesCelsius.map(Double.init)
            self.editCPUDuties = cpuCurve.dutyPercentEstimated.map { Double(max($0, 10)) }
            if self.editCPUDuties.count == 8 && self.editCPUDuties[7] < 40 {
                self.editCPUDuties[7] = 45
            }
            self.editGPUTemps = gpuCurve.temperaturesCelsius.map(Double.init)
            self.editGPUDuties = gpuCurve.dutyPercentEstimated.map { Double(max($0, 10)) }
            if self.editGPUDuties.count == 8 && self.editGPUDuties[7] < 40 {
                self.editGPUDuties[7] = 45
            }
            showStatus("Loaded \(cpuCurve.profileName) 8-point firmware curve into editor.")
        }
    }

    public func applyCustomFanCurves() {
        let cpuT = editCPUTemps.map { UInt8(clamping: Int($0.rounded())) }
        let cpuD = editCPUDuties.map { UInt8(clamping: Int($0.rounded())) }
        let gpuT = editGPUTemps.map { UInt8(clamping: Int($0.rounded())) }
        let gpuD = editGPUDuties.map { UInt8(clamping: Int($0.rounded())) }
        do {
            try bridge.writeCustomFanCurve(fanIndex: 0, temperatures: cpuT, dutiesPercent: cpuD)
            try bridge.writeCustomFanCurve(fanIndex: 1, temperatures: gpuT, dutiesPercent: gpuD)
            self.settings = SettingsStore.shared.load()
            self.bridgeSnapshot = try? bridge.fetchSnapshot()
            showStatus("Applied custom 8-point CPU & GPU fan curves (0x00110024 / 0x00110025).")
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    public func resetFanCurvesToAuto() {
        do {
            try bridge.resetFanCurveToAuto(fanIndex: 0)
            try bridge.resetFanCurveToAuto(fanIndex: 1)
            self.settings = SettingsStore.shared.load()
            self.bridgeSnapshot = try? bridge.fetchSnapshot()
            showStatus("Reset CPU & GPU fans to automatic firmware curve (EC0.FMAE = 0).")
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    public func applyCPUPowerLimits() {
        let pl1 = Int(editPL1Watts.rounded())
        let pl2 = Int(editPL2Watts.rounded())
        do {
            try bridge.setCPUPowerLimits(pl1SPLWatts: pl1, pl2SPPTWatts: pl2)
            self.settings = SettingsStore.shared.load()
            self.bridgeSnapshot = try? bridge.fetchSnapshot()
            showStatus("Applied CPU Power Limits: PL1 (SPL) = \(pl1) W, PL2 (SPPT) = \(pl2) W")
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    public func resetCPUPowerLimits() {
        self.settings = SettingsStore.shared.update {
            $0.customPPTEnabled = false
            $0.cpuPL1SPLWatts = 45
            $0.cpuPL2SPPTWatts = 65
        }
        self.editPL1Watts = 45
        self.editPL2Watts = 65
        _ = try? bridge.setThermalProfile(settings.thermalProfile)
        showStatus("Reset CPU Power Limits to profile default (\(settings.thermalProfile.displayName)).")
    }

    public func setDisplayBrightness(_ pct: Double) {
        self.displayBrightnessPercent = pct
        do {
            let actual = try brightnessCtrl.setBrightnessPercent(pct)
            self.displayBrightnessPercent = actual
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    public func stepDisplayBrightness(up: Bool) {
        do {
            let actual = up ? try brightnessCtrl.stepUp() : try brightnessCtrl.stepDown()
            self.displayBrightnessPercent = actual
            showStatus(String(format: "Internal Panel LGD066C Brightness: %.1f%%", actual))
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    public func applyRGBSettings(
        mode: TufRGBMode? = nil,
        red: UInt8? = nil,
        green: UInt8? = nil,
        blue: UInt8? = nil,
        speed: TufRGBSpeed? = nil,
        brightness: KeyboardBrightnessLevel? = nil
    ) {
        do {
            let resultMsg = try lightingCtrl.applyLighting(
                mode: mode,
                red: red,
                green: green,
                blue: blue,
                speed: speed,
                brightness: brightness
            )
            self.settings = SettingsStore.shared.load()
            self.bridgeSnapshot = try? bridge.fetchSnapshot()
            self.hardwareVerification = bridge.readLiveHardwareVerification()
            self.rgbColorSwiftUI = Color(
                red: Double(settings.rgbRed) / 255.0,
                green: Double(settings.rgbGreen) / 255.0,
                blue: Double(settings.rgbBlue) / 255.0
            )
            showStatus(resultMsg)
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    public func updateRGBFromColorPicker(_ newColor: Color) {
        if let cgColor = newColor.cgColor,
           let converted = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
           let comps = converted.components, comps.count >= 3 {
            let r = UInt8(clamping: Int((comps[0] * 255.0).rounded()))
            let g = UInt8(clamping: Int((comps[1] * 255.0).rounded()))
            let b = UInt8(clamping: Int((comps[2] * 255.0).rounded()))
            applyRGBSettings(red: r, green: g, blue: b)
        }
    }

    public func stageKextV3UpdateInTerminal() {
        let defaultCmd = "curl -fsSL https://raw.githubusercontent.com/ixboss/asus-control-macos/main/scripts/stage-kext-update.sh | sudo bash"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(defaultCmd, forType: .string)
        showStatus("Copied kext staging command to clipboard.")
    }
}
