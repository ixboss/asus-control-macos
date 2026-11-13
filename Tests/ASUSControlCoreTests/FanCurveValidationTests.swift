import XCTest
@testable import ASUSControlCore

/// Covers 8-point fan curve clamping/validation guardrails (kernel-side rules
/// mirrored from `AsusBridge.cpp::writeFanCurve` / `FanCurveValidator`).
final class FanCurveValidationTests: XCTestCase {
    private let validTemps: [UInt8] = [45, 52, 58, 64, 70, 75, 80, 85]
    private let validDuties: [UInt8] = [15, 20, 28, 36, 45, 58, 72, 85]

    func testValidCurvePasses() throws {
        try FanCurveValidator.validate(temperatures: validTemps, dutiesPercent: validDuties)
    }

    func testWrongPointCountRejected() {
        XCTAssertThrowsError(try FanCurveValidator.validate(temperatures: Array(validTemps.dropFirst()), dutiesPercent: validDuties))
        XCTAssertThrowsError(try FanCurveValidator.validate(temperatures: validTemps, dutiesPercent: Array(validDuties.dropLast())))
    }

    func testTemperatureBelow20Rejected() {
        var temps = validTemps
        temps[0] = 19
        XCTAssertThrowsError(try FanCurveValidator.validate(temperatures: temps, dutiesPercent: validDuties))
    }

    func testTemperatureAbove105Rejected() {
        var temps = validTemps
        temps[7] = 106
        XCTAssertThrowsError(try FanCurveValidator.validate(temperatures: temps, dutiesPercent: validDuties))
    }

    func testDutyAbove100Rejected() {
        var duties = validDuties
        duties[7] = 101
        XCTAssertThrowsError(try FanCurveValidator.validate(temperatures: validTemps, dutiesPercent: duties))
    }

    func testNonMonotonicTemperatureRejected() {
        var temps = validTemps
        temps.swapAt(4, 5)
        XCTAssertThrowsError(try FanCurveValidator.validate(temperatures: temps, dutiesPercent: validDuties))
    }

    func testNonMonotonicDutyRejected() {
        var duties = validDuties
        duties[5] = 10
        XCTAssertThrowsError(try FanCurveValidator.validate(temperatures: validTemps, dutiesPercent: duties))
    }

    func testTopPointBelow40PercentRejected() {
        let unsafeDuties: [UInt8] = [10, 15, 20, 20, 25, 25, 30, 30]
        XCTAssertThrowsError(try FanCurveValidator.validate(temperatures: validTemps, dutiesPercent: unsafeDuties))
    }

    func testEqualPlateauPointsAccepted() throws {
        let plateauDuties: [UInt8] = [40, 40, 40, 40, 40, 40, 40, 40]
        try FanCurveValidator.validate(temperatures: validTemps, dutiesPercent: plateauDuties)
    }

    func testConstantsMatchKernelGuardrails() {
        XCTAssertEqual(FanCurveValidator.pointCount, 8)
        XCTAssertEqual(FanCurveValidator.minTemperatureC, 20)
        XCTAssertEqual(FanCurveValidator.maxTemperatureC, 105)
        XCTAssertEqual(FanCurveValidator.minTopDutyPercent, 40)
    }
}
