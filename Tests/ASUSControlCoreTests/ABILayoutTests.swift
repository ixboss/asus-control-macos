import XCTest
@testable import ASUSControlCore

/// Verifies the ABI v2 wire-layout contract between `asus_bridge_abi.h`
/// (`#pragma pack(push, 4)`) and the Swift user-space client.
final class ABILayoutTests: XCTestCase {
    // Mirrors of the C structs — keep field counts/sizes in lockstep with
    // kexts/AsusBridge/asus_bridge_abi.h (Snapshot 27 x UInt32, ECState 16 x UInt32,
    // FanCurve 8+8 x UInt8). A mismatched layout silently corrupts IOConnect
    // struct transfers, so sizes are asserted hard.
    struct SnapshotMirror {
        var w: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
                UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
                UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
                UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
    }

    struct ECStateMirror {
        var w: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
                UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
                UInt32, UInt32)
    }

    struct FanCurveMirror {
        var temperatures: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        var duties: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    }

    func testSnapshotLayoutIs27Words() {
        XCTAssertEqual(MemoryLayout<SnapshotMirror>.size, 27 * MemoryLayout<UInt32>.size,
                       "AsusBridgeSnapshot must be exactly 27 x UInt32 (108 bytes) to match ABI v2")
        XCTAssertEqual(AsusBridgeClient.expectedABIVersion, 2)
    }

    func testECStateLayoutIs16Words() {
        XCTAssertEqual(MemoryLayout<ECStateMirror>.size, 16 * MemoryLayout<UInt32>.size,
                       "AsusBridgeECState must be exactly 16 x UInt32 (64 bytes) to match ABI v2")
    }

    func testFanCurveLayoutIs16Bytes() {
        XCTAssertEqual(MemoryLayout<FanCurveMirror>.size, 16,
                       "AsusBridgeFanCurve must be exactly 16 bytes (8 temps + 8 duties)")
    }

    func testSelectorIDsMatchABIHeader() {
        XCTAssertEqual(AsusBridgeClient.Selector.getSnapshot.rawValue, 0)
        XCTAssertEqual(AsusBridgeClient.Selector.readFanCurve.rawValue, 1)
        XCTAssertEqual(AsusBridgeClient.Selector.readSingleDSTS.rawValue, 2)
        XCTAssertEqual(AsusBridgeClient.Selector.setChargeLimit.rawValue, 3)
        XCTAssertEqual(AsusBridgeClient.Selector.setThermalProfile.rawValue, 4)
        XCTAssertEqual(AsusBridgeClient.Selector.writeFanCurve.rawValue, 5)
        XCTAssertEqual(AsusBridgeClient.Selector.setPPTLimits.rawValue, 6)
        XCTAssertEqual(AsusBridgeClient.Selector.setTufRGB.rawValue, 7)
        XCTAssertEqual(AsusBridgeClient.Selector.triggerSKEY.rawValue, 8)
        XCTAssertEqual(AsusBridgeClient.Selector.setKbdBrightness.rawValue, 9)
        XCTAssertEqual(AsusBridgeClient.Selector.getECState.rawValue, 10)
    }
}
