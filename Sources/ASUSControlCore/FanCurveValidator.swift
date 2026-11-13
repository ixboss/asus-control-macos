import Foundation

/// Pure validation logic for 8-point custom fan curves shared by
/// `AsusBridgeClient.writeCustomFanCurve` (user-space) and mirrored by the
/// kernel-side guardrails in `AsusBridge.cpp::writeFanCurve`.
public enum FanCurveValidator {
    public static let pointCount = 8
    public static let minTemperatureC: UInt8 = 20
    public static let maxTemperatureC: UInt8 = 105
    public static let minTopDutyPercent: UInt8 = 40

    /// Validates exactly 8 points with temperatures in 20..105 °C, duties in
    /// 0..100 %, non-decreasing monotonicity, and a >= 40 % safety floor on
    /// the top point (guarantees the fan can always reach an emergency spin-up).
    public static func validate(temperatures: [UInt8], dutiesPercent: [UInt8]) throws {
        guard temperatures.count == pointCount, dutiesPercent.count == pointCount else {
            throw NSError(domain: "AsusBridgeClient", code: Int(kIOReturnBadArgument),
                          userInfo: [NSLocalizedDescriptionKey: "Fan curve requires exactly \(pointCount) temperature points and \(pointCount) duty percentage points."])
        }
        for i in 0..<pointCount {
            guard (minTemperatureC...maxTemperatureC).contains(temperatures[i]), dutiesPercent[i] <= 100 else {
                throw NSError(domain: "AsusBridgeClient", code: Int(kIOReturnBadArgument),
                              userInfo: [NSLocalizedDescriptionKey: "Point \(i + 1) out of range (Temp: \(minTemperatureC)..\(maxTemperatureC)°C, Duty: 0..100%)."])
            }
            if i > 0 && (temperatures[i] < temperatures[i - 1] || dutiesPercent[i] < dutiesPercent[i - 1]) {
                throw NSError(domain: "AsusBridgeClient", code: Int(kIOReturnBadArgument),
                              userInfo: [NSLocalizedDescriptionKey: "Fan curve temperatures and duties must be non-decreasing."])
            }
        }
        guard dutiesPercent[pointCount - 1] >= minTopDutyPercent else {
            throw NSError(domain: "AsusBridgeClient", code: Int(kIOReturnBadArgument),
                          userInfo: [NSLocalizedDescriptionKey: "Safety guardrail: Point \(pointCount) duty must be at least \(minTopDutyPercent)%%."])
        }
    }
}
