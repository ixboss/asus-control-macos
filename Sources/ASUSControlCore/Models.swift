import Foundation

/// Strict verification level for every hardware feature and telemetry source.
public enum VerificationStatus: String, Codable, Sendable {
    /// Directly confirmed through hardware inspection, ACPI/DSDT, IORegistry, or read-only execution on the current host (FX707ZM).
    case verifiedOnCurrentHost = "Verified on Current Host"
    /// Supported by FX707ZM DSDT AML or EC fields, awaiting kernel-space ATKD.WMNB read-only evaluation in Phase 1B.
    case verifiedInHostACPIPendingEvaluation = "Verified in Host ACPI (Pending Read-Only Evaluation)"
    /// Routed via WCHK -> W15H (BIOS SMM/SMI 0xAA) in FX707ZM DSDT; requires careful single-shot read probe.
    case routedViaHostSMMPendingProbe = "Routed via Host BIOS SMM (WCHK/W15H - Pending Probe)"
    /// Documented on another ASUS model only; not confirmed on FX707ZM.
    case documentedOnOtherModels = "Documented on Other Models"
    /// Confirmed absent or unsupported on FX707ZM.
    case unsupportedOnCurrentHost = "Unsupported on Current Host"
}

/// Classification of diagnostic/control operations by hardware side-effect profile.
public enum SafetyProfile: String, Codable, Sendable {
    /// Reads cached properties from IORegistry or sysctl in user-space; zero hardware/ACPI/EC interaction.
    case pureUserSpacePropertyRead = "Pure User-Space Property Read (Zero Side Effects)"
    /// Reads VirtualSMC keys via AppleSMC user client; low risk, polled by macOS powerd.
    case virtualSMCRead = "VirtualSMC Key Read (Low Risk)"
    /// Evaluates pure AML method without touching EC0 or SMM (e.g., ATKD.SFUN).
    case pureAMLMethodRead = "Pure AML Method Evaluation (No EC/SMI)"
    /// Evaluates AML method that reads Embedded Controller fields in ERAM (e.g., DSTS 0x00120094, 0x00110013).
    case directECFieldRead = "Direct AML -> EC0 Read (Rate-Limited, Mutex-Protected)"
    /// Evaluates AML method that triggers WCHK -> W15H (SMI 0xAA into BIOS SMM).
    case smmInterruptRead = "BIOS SMM/SMI Evaluation via W15H (Single-Shot Only)"
    /// Mutates hardware, EC, or AML state (Forbidden in Phase 1).
    case stateMutatingWrite = "State-Mutating Write (Disabled in Phase 1)"
}

public struct HostIdentity: Codable, Sendable {
    public let boardManufacturer: String
    public let boardProduct: String
    public let systemProduct: String
    public let biosVersion: String
    public let smbiosModel: String
    public let osVersion: String
    public let osBuild: String
    public let kernelVersion: String
    public let bootArgs: String
}

public struct CPUTopologyReport: Codable, Sendable {
    public let brandString: String
    public let family: Int
    public let model: Int
    public let stepping: Int
    public let microcodeVersion: Int
    public let activePhysicalCores: Int
    public let activeLogicalThreads: Int
    public let acpiTotalProcessorNodes: Int
    public let acpiEnabledPCoreThreads: [String]
    public let acpiDisabledProcessorNodes: [String]
    public let topologyExplanation: String
}

public struct GPUDeviceReport: Codable, Sendable {
    public let name: String
    public let vendorID: UInt32
    public let deviceID: UInt32
    public let acpiPath: String
    public let pciPath: String
    public let isDrivingInternalDisplay: Bool
    public let driverName: String
    public let notes: String
}

public struct BrightnessReport: Codable, Sendable {
    public let internalPanelName: String
    public let displayVendorID: UInt32
    public let displayProductID: UInt32
    public let connectedGPUPath: String
    public let backlightDriverClass: String
    public let displayServicesAvailable: Bool
    public let displayServicesCanChange: Bool
    public let softwareBrightnessPercent: Float?
    public let ioDisplayLogicalValue: Int?
    public let ioDisplayLogicalMin: Int?
    public let ioDisplayLogicalMax: Int?
    public let ioDisplayLinearValue: Int?
    public let pnlfPresentOnIGPU: Bool
    public let whateverXeBacklightProfileReadyOnIGPU: Bool
    public let igpuHasActiveFramebuffer: Bool
    public let architectureSummary: String
}

public struct BatteryReport: Codable, Sendable {
    public let installed: Bool
    public let deviceName: String
    public let externalConnected: Bool
    public let isCharging: Bool
    public let fullyCharged: Bool
    public let designCapacitymWh: Int
    public let maxCapacitymWh: Int
    public let currentCapacitymWh: Int
    public let healthPercent: Double
    public let chargePercent: Double
    public let voltagemV: Int
    public let amperagemA: Int
    public let powerWatts: Double
    public let temperatureCelsius: Double
    public let cycleCount: Int
}

public struct SMCKeyDiagnostic: Codable, Sendable {
    public let totalKeysCount: Int
    public let fanNumberKeyPresent: Bool
    public let fanCountReported: Int
    public let fanRPMKeysPresent: Bool
    public let cpuTempKeysPresent: Bool
    public let ambientLightLux: UInt16?
    public let batteryTemperatureKeysCelsius: [String: Double]
    public let sampleKeys: [String: String]
}

public struct ACPIDevicePresence: Codable, Sendable {
    public let name: String
    public let hidOrCompatible: String
    public let uid: String?
    public let acpiPath: String
    public let status: Int?
    public let attachedDriver: String?
}

public struct CapabilityEntry: Codable, Sendable {
    public let featureID: String
    public let featureName: String
    public let wmiDeviceIDHex: String?
    public let acpiOrECPath: String
    public let verificationStatus: VerificationStatus
    public let safetyProfile: SafetyProfile
    public let notes: String
}

public struct DiagnosticSnapshot: Codable, Sendable {
    public let timestampISO8601: String
    public let host: HostIdentity
    public let cpu: CPUTopologyReport
    public let gpus: [GPUDeviceReport]
    public let brightness: BrightnessReport
    public let battery: BatteryReport
    public let smc: SMCKeyDiagnostic
    public let acpiDevices: [ACPIDevicePresence]
    public let capabilities: [CapabilityEntry]
}

// MARK: - Phase 2-6 Hardware Control Domain Types

/// ASUS TUF Gaming F17 (FX707ZM) Firmware Thermal / Performance Profiles (`0x00120075`).
public enum ThermalProfile: String, Codable, CaseIterable, Sendable, Identifiable {
    case silent = "silent"
    case balanced = "balanced"
    case turbo = "turbo"

    public var id: String { rawValue }

    /// WMI DEVS(0x00120075, code) payload on FX707ZM (`0=Balanced/Performance, 1=Turbo, 2=Silent`).
    public var wmiCode: UInt32 {
        switch self {
        case .balanced: return 0
        case .turbo:    return 1
        case .silent:   return 2
        }
    }

    public var displayName: String {
        switch self {
        case .silent:   return "Silent"
        case .balanced: return "Performance (Balanced)"
        case .turbo:    return "Turbo"
        }
    }

    public var arabicName: String {
        switch self {
        case .silent:   return "هادئ (Silent)"
        case .balanced: return "متوازن (Balanced)"
        case .turbo:    return "أقصى أداء (Turbo)"
        }
    }

    /// Index in FX707ZM DSDT `DSTS(0x00110024/25, arg1)` (`0=CFCV Balanced, 1=CSFV Silent, 2=CTFV Turbo`).
    public var fanCurveArgIndex: Int {
        switch self {
        case .balanced: return 0
        case .silent:   return 1
        case .turbo:    return 2
        }
    }

    /// Default safe CPU PL1 (SPL) and PL2 (SPPT) power limits in Watts written to `EC0.PL1V` and `EC0.PL2V`.
    public func defaultPowerLimits(onAC: Bool) -> (pl1: Int, pl2: Int) {
        switch self {
        case .silent:
            return onAC ? (28, 38) : (22, 30)
        case .balanced:
            return onAC ? (45, 65) : (35, 45)
        case .turbo:
            return onAC ? (80, 105) : (40, 55)
        }
    }

    public init?(wmiCode: UInt32) {
        switch wmiCode {
        case 0: self = .balanced
        case 1: self = .turbo
        case 2: self = .silent
        default: return nil
        }
    }
}

/// Live hardware verification readback from `AsusBridge.kext`, `IORegistry`, and `EC0`.
public struct HardwareVerificationReport: Codable, Sendable {
    public let kextLoaded: Bool
    public let kextV3Active: Bool
    public let wmiInitOK: Bool
    public let ecOK: Bool
    public let onACPower: Bool
    public let verifiedChargeLimit: Int
    public let verifiedProfile: ThermalProfile
    public let verifiedPL1Watts: Int
    public let verifiedPL2Watts: Int
    public let cpuTempCelsius: Int
    public let cpuFanRPM: Int
    public let gpuFanRPM: Int
    public let customFanMask: UInt32
    public let kbdRawDSTS: UInt32
    public let lastKernelCommandLog: String
    public let ecDirectMapped: Bool
    public let ecRSOC: Int?
    public let ecFTBL: Int?
    public let ecPL1V: Int?
    public let ecPL2V: Int?
}

/// TUF Gaming Keyboard RGB Modes (`0x00100056`).
public enum TufRGBMode: UInt32, Codable, CaseIterable, Sendable, Identifiable {
    case staticColor = 0
    case breathe     = 1
    case colorCycle  = 2
    case strobe      = 3

    public var id: UInt32 { rawValue }

    public var displayName: String {
        switch self {
        case .staticColor: return "Static"
        case .breathe:     return "Breathing"
        case .colorCycle:  return "Color Cycle"
        case .strobe:      return "Strobe"
        }
    }

    public var cliName: String {
        switch self {
        case .staticColor: return "static"
        case .breathe:     return "breathe"
        case .colorCycle:  return "cycle"
        case .strobe:      return "strobe"
        }
    }

    public init?(cliName: String) {
        switch cliName.lowercased() {
        case "static", "0": self = .staticColor
        case "breathe", "breathing", "1": self = .breathe
        case "cycle", "colorcycle", "2": self = .colorCycle
        case "strobe", "3": self = .strobe
        default: return nil
        }
    }
}

/// TUF Gaming Keyboard RGB Animation Speeds (`0x00100056`).
public enum TufRGBSpeed: UInt32, Codable, CaseIterable, Sendable, Identifiable {
    case slow   = 0
    case medium = 1
    case fast   = 2

    public var id: UInt32 { rawValue }

    public var displayName: String {
        switch self {
        case .slow:   return "Slow"
        case .medium: return "Medium"
        case .fast:   return "Fast"
        }
    }

    public init?(cliName: String) {
        switch cliName.lowercased() {
        case "slow", "0":   self = .slow
        case "medium", "med", "1": self = .medium
        case "fast", "2":   self = .fast
        default: return nil
        }
    }
}

/// Keyboard Backlight Brightness Level (`0...3`).
public enum KeyboardBrightnessLevel: Int, Codable, CaseIterable, Sendable, Identifiable {
    case off    = 0
    case low    = 1
    case medium = 2
    case high   = 3

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .off:    return "Off (0)"
        case .low:    return "Low (1)"
        case .medium: return "Medium (2)"
        case .high:   return "High (3)"
        }
    }
}
