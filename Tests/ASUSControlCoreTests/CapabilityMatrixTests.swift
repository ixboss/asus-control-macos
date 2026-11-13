import XCTest
@testable import ASUSControlCore

/// Covers dynamic multi-model `CapabilityMatrixResolver` matching (pure
/// board-id logic — no IORegistry access on CI) and thermal-profile mappings.
final class CapabilityMatrixTests: XCTestCase {
    func testFX707ZMResolvesTier1Verified() {
        let p = CapabilityMatrixResolver().match(boardProduct: "FX707ZM", systemProduct: "ASUS TUF Gaming F17 FX707ZM_FX707ZM")
        XCTAssertEqual(p.tier, .tier1Verified)
        XCTAssertEqual(p.family, "TUF Gaming F17")
        XCTAssertTrue(p.supportsTelemetry)
        XCTAssertTrue(p.supportsFanCurves)
        XCTAssertTrue(p.supportsPowerLimits)
        XCTAssertTrue(p.supportsChargeLimit)
        XCTAssertTrue(p.supportsThermalProfiles)
        XCTAssertTrue(p.supportsTufRGB)
        XCTAssertTrue(p.supportsKeyboardBacklight)
    }

    func testTUF_FA507_FX507_ResolvesTier2() {
        for board in ["FA507XV", "FX507ZE", "fa507nv"] {
            let p = CapabilityMatrixResolver().match(boardProduct: board)
            XCTAssertEqual(p.tier, .tier2PendingProbe, board)
            XCTAssertEqual(p.family, "TUF Gaming A15/F15 (FA507/FX507)", board)
            XCTAssertTrue(p.supportsTelemetry && p.supportsFanCurves && p.supportsPowerLimits)
        }
    }

    func testROGZephyrusStrixResolvesTier2WithoutTufRGB() {
        for board in ["G513RM", "GA402XZ", "GU603ZW", "GX650PY"] {
            let p = CapabilityMatrixResolver().match(boardProduct: board)
            XCTAssertEqual(p.tier, .tier2PendingProbe, board)
            XCTAssertEqual(p.family, "ROG Zephyrus / Strix", board)
            XCTAssertFalse(p.supportsTufRGB, board)
        }
    }

    func testUnknownBoardIsTelemetryOnly() {
        let p = CapabilityMatrixResolver().match(boardProduct: "ABCD1234")
        XCTAssertEqual(p.tier, .unknown)
        XCTAssertTrue(p.supportsTelemetry)
        XCTAssertFalse(p.supportsFanCurves)
        XCTAssertFalse(p.supportsPowerLimits)
        XCTAssertFalse(p.supportsChargeLimit)
        XCTAssertFalse(p.supportsThermalProfiles)
        XCTAssertFalse(p.supportsTufRGB)
    }

    func testSystemProductFallbackMatching() {
        let p = CapabilityMatrixResolver().match(boardProduct: "UNKNOWN", systemProduct: "ASUS TUF Gaming A17 FA507NV_FA507")
        XCTAssertEqual(p.tier, .tier2PendingProbe)
    }

    func testThermalProfileMappings() {
        XCTAssertEqual(ThermalProfile.balanced.wmiCode, 0)
        XCTAssertEqual(ThermalProfile.turbo.wmiCode, 1)
        XCTAssertEqual(ThermalProfile.silent.wmiCode, 2)
        XCTAssertEqual(ThermalProfile(wmiCode: 0), .balanced)
        XCTAssertEqual(ThermalProfile(wmiCode: 1), .turbo)
        XCTAssertEqual(ThermalProfile(wmiCode: 2), .silent)
        XCTAssertNil(ThermalProfile(wmiCode: 3))
    }

    func testFanCurveArgIndexMapping() {
        XCTAssertEqual(ThermalProfile.balanced.fanCurveArgIndex, 0)
        XCTAssertEqual(ThermalProfile.silent.fanCurveArgIndex, 1)
        XCTAssertEqual(ThermalProfile.turbo.fanCurveArgIndex, 2)
    }

    func testTurboPowerLimitsDowngradedOnBattery() {
        let ac = ThermalProfile.turbo.defaultPowerLimits(onAC: true)
        let batt = ThermalProfile.turbo.defaultPowerLimits(onAC: false)
        XCTAssertGreaterThan(ac.pl1, batt.pl1)
        XCTAssertGreaterThan(ac.pl2, batt.pl2)
    }
}
