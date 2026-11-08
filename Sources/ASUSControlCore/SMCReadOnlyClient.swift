import Foundation
import IOKit

/// Read-only AppleSMC / VirtualSMC client using standard IOKit selector 2 (`kSMCHandleYPCEvent`).
/// Strictly performs read operations (`kSMCGetKeyCount`, `kSMCGetKeyFromIndex`, `kSMCGetKeyInfo`, `kSMCReadKey`).
public final class SMCReadOnlyClient: Sendable {
    private static let kSMCHandleYPCEvent: UInt32 = 2
    private static let kSMCReadKey: UInt8 = 5
    private static let kSMCGetKeyCount: UInt8 = 7
    private static let kSMCGetKeyFromIndex: UInt8 = 8
    private static let kSMCGetKeyInfo: UInt8 = 9

    /// Exact 80-byte layout required by AppleSMC / VirtualSMC `SMCParamStruct`.
    private struct SMCParamStruct {
        var key: UInt32 = 0
        var versMajor: UInt8 = 0
        var versMinor: UInt8 = 0
        var versBuild: UInt8 = 0
        var versReserved: UInt8 = 0
        var versRelease: UInt16 = 0
        var pLimitVersion: UInt16 = 0
        var pLimitLength: UInt16 = 0
        var pLimitCPU: UInt32 = 0
        var pLimitGPU: UInt32 = 0
        var pLimitMem: UInt32 = 0
        var keyInfoDataSize: UInt32 = 0
        var keyInfoDataType: UInt32 = 0
        var keyInfoDataAttributes: UInt8 = 0
        var padding1: UInt8 = 0
        var padding2: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var padding3: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        ) = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    public init() {}

    public static func fourCC(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in str.utf8.prefix(4) {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    public static func fourCCString(_ val: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((val >> 24) & 0xFF),
            UInt8((val >> 16) & 0xFF),
            UInt8((val >> 8) & 0xFF),
            UInt8(val & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    public func inspectSMC() -> SMCKeyDiagnostic {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else {
            return SMCKeyDiagnostic(
                totalKeysCount: 0, fanNumberKeyPresent: false, fanCountReported: 0,
                fanRPMKeysPresent: false, cpuTempKeysPresent: false, ambientLightLux: nil,
                batteryTemperatureKeysCelsius: [:], sampleKeys: [:]
            )
        }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            return SMCKeyDiagnostic(
                totalKeysCount: 0, fanNumberKeyPresent: false, fanCountReported: 0,
                fanRPMKeysPresent: false, cpuTempKeysPresent: false, ambientLightLux: nil,
                batteryTemperatureKeysCelsius: [:], sampleKeys: [:]
            )
        }
        defer { IOServiceClose(conn) }

        let totalKeys = readKeyUInt32(conn: conn, key: "#KEY") ?? 0
        let fnumBytes = readKeyBytes(conn: conn, key: "FNum")
        let fnumPresent = fnumBytes != nil
        let fanCount = Int(fnumBytes?.first ?? 0)

        let f0Ac = readKeyBytes(conn: conn, key: "F0Ac")
        let f1Ac = readKeyBytes(conn: conn, key: "F1Ac")
        let tc0p = readKeyBytes(conn: conn, key: "TC0P")
        let tc0d = readKeyBytes(conn: conn, key: "TC0D")

        var lux: UInt16? = nil
        if let alv0 = readKeyBytes(conn: conn, key: "ALV0"), alv0.count >= 10 {
            lux = (UInt16(alv0[8]) << 8) | UInt16(alv0[9])
        }

        var battTemps: [String: Double] = [:]
        for k in ["TB0T", "TB1T", "TB2T"] {
            if let b = readKeyBytes(conn: conn, key: k), b.count == 2 {
                // sp78 signed fixed-point 8.8
                let raw = (Int16(bitPattern: (UInt16(b[0]) << 8) | UInt16(b[1])))
                let temp = Double(raw) / 256.0
                battTemps[k] = (temp * 100).rounded() / 100
            }
        }

        var samples: [String: String] = [:]
        for k in ["#KEY", "FNum", "AC-N", "BATP", "BBIN", "BRSC", "B0AV", "B0AC", "B0RM", "B0FC", "ALV0", "TB0T"] {
            if let b = readKeyBytes(conn: conn, key: k) {
                samples[k] = b.map { String(format: "%02x", $0) }.joined()
            }
        }

        return SMCKeyDiagnostic(
            totalKeysCount: Int(totalKeys),
            fanNumberKeyPresent: fnumPresent,
            fanCountReported: fanCount,
            fanRPMKeysPresent: (f0Ac != nil || f1Ac != nil),
            cpuTempKeysPresent: (tc0p != nil || tc0d != nil),
            ambientLightLux: lux,
            batteryTemperatureKeysCelsius: battTemps,
            sampleKeys: samples
        )
    }

    private func callSMC(conn: io_connect_t, input: inout SMCParamStruct, output: inout SMCParamStruct) -> Bool {
        let inSize = MemoryLayout<SMCParamStruct>.size
        var outSize = MemoryLayout<SMCParamStruct>.size
        let kr = IOConnectCallStructMethod(
            conn,
            Self.kSMCHandleYPCEvent,
            &input,
            inSize,
            &output,
            &outSize
        )
        return kr == KERN_SUCCESS && output.result == 0
    }

    private func readKeyBytes(conn: io_connect_t, key: String) -> [UInt8]? {
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        input.key = Self.fourCC(key)
        input.data8 = Self.kSMCGetKeyInfo
        guard callSMC(conn: conn, input: &input, output: &output), output.keyInfoDataSize > 0 else {
            return nil
        }

        let size = Int(min(output.keyInfoDataSize, 32))
        var readIn = SMCParamStruct()
        var readOut = SMCParamStruct()
        readIn.key = Self.fourCC(key)
        readIn.keyInfoDataSize = output.keyInfoDataSize
        readIn.data8 = Self.kSMCReadKey
        guard callSMC(conn: conn, input: &readIn, output: &readOut) else {
            return nil
        }

        return withUnsafeBytes(of: &readOut.bytes) { rawBuf in
            Array(rawBuf.prefix(size))
        }
    }

    private func readKeyUInt32(conn: io_connect_t, key: String) -> UInt32? {
        guard let b = readKeyBytes(conn: conn, key: key), b.count == 4 else { return nil }
        return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
    }
}
