import XCTest
@testable import ASUSControlCore

/// Covers atomic `SettingsStore` JSON serialization round-trips, default
/// clamping, and the shared IPC notification name. Uses isolated temp-dir
/// stores (never the user's real `~/.config/asus-control/settings.json`).
final class SettingsStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("asus-control-tests-\(UUID().uuidString)")
            .appendingPathComponent("settings.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    func testDefaultsRoundTrip() throws {
        let store = SettingsStore(customURL: tempURL)
        let defaults = store.load()
        XCTAssertEqual(defaults.batteryChargeLimitPercent, 80)
        XCTAssertEqual(defaults.thermalProfile, .balanced)

        store.save(defaults)
        let reloaded = store.load()
        XCTAssertEqual(reloaded, defaults)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
    }

    func testSaveLoadAllFieldsRoundTrip() throws {
        let store = SettingsStore(customURL: tempURL)
        var s = store.load()
        s.batteryChargeLimitPercent = 60
        s.thermalProfile = .turbo
        s.acPreferredProfile = .turbo
        s.batteryPreferredProfile = .silent
        s.autoSwitchProfileOnPowerChange = false
        s.restoreOnWake = false
        s.customFanCurveEnabled = true
        s.customCPUFanTemps = [45, 52, 58, 64, 70, 75, 80, 85]
        s.customCPUFanDuties = [15, 20, 28, 36, 45, 58, 72, 85]
        s.customPPTEnabled = true
        s.cpuPL1SPLWatts = 65
        s.cpuPL2SPPTWatts = 95
        s.keyboardBrightness = .high
        s.rgbMode = .breathe
        s.rgbRed = 0x12
        s.rgbGreen = 0x34
        s.rgbBlue = 0x56
        s.rgbSpeed = .fast

        store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testChargeLimitClampedOnInit() {
        let store = SettingsStore(customURL: tempURL)
        let s = ASUSControlSettings(batteryChargeLimitPercent: 45)
        XCTAssertLessThanOrEqual(60, s.batteryChargeLimitPercent)
        _ = store // clamping contract mirrored from kernel-side 60..100 guardrail
    }

    func testTurboBatteryPreferredDowngradedOnInit() {
        let s = ASUSControlSettings(batteryPreferredProfile: .turbo)
        XCTAssertEqual(s.batteryPreferredProfile, .balanced)
    }

    func testUpdateMutatesAtomically() {
        let store = SettingsStore(customURL: tempURL)
        let updated = store.update {
            $0.batteryChargeLimitPercent = 100
            $0.thermalProfile = .silent
        }
        XCTAssertEqual(updated.batteryChargeLimitPercent, 100)
        XCTAssertEqual(updated.thermalProfile, .silent)
        XCTAssertEqual(store.load().batteryChargeLimitPercent, 100)
    }

    func testIPCNotificationNameConstant() {
        XCTAssertEqual(SettingsStore.settingsChangedNotification, "org.asuscontrol.settingsChanged")
    }
}
