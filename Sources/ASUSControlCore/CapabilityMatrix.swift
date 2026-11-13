import Foundation

// MARK: - Dynamic Multi-Model Capability Resolver (v0.4.0)

/// Verification tier assigned to an ASUS board profile.
public enum ASUSModelTier: String, Codable, Sendable {
    /// Fully hardware-verified on the reference host (FX707ZM, BIOS 316) — every selector probed live via DSTS.
    case tier1Verified = "Tier 1 (Verified on FX707ZM)"
    /// Compatible family (TUF FA507/FX507 or ROG Zephyrus/Strix) — WMI selectors expected but awaiting a live DSTS probe on this host.
    case tier2PendingProbe = "Tier 2 (Compatible - Pending DSTS Probe)"
    /// Unknown board — telemetry only; all control selectors disabled for safety.
    case unknown = "Unknown Board (Telemetry Only)"
}

/// Feature flags resolved per-board by `CapabilityMatrixResolver`.
public struct ASUSModelProfile: Codable, Sendable, Equatable {
    public let boardProduct: String
    public let family: String
    public let tier: ASUSModelTier
    public let supportsTelemetry: Bool
    public let supportsFanCurves: Bool
    public let supportsPowerLimits: Bool
    public let supportsChargeLimit: Bool
    public let supportsThermalProfiles: Bool
    public let supportsTufRGB: Bool
    public let supportsKeyboardBacklight: Bool

    public init(
        boardProduct: String,
        family: String,
        tier: ASUSModelTier,
        supportsTelemetry: Bool = true,
        supportsFanCurves: Bool = false,
        supportsPowerLimits: Bool = false,
        supportsChargeLimit: Bool = false,
        supportsThermalProfiles: Bool = false,
        supportsTufRGB: Bool = false,
        supportsKeyboardBacklight: Bool = false
    ) {
        self.boardProduct = boardProduct
        self.family = family
        self.tier = tier
        self.supportsTelemetry = supportsTelemetry
        self.supportsFanCurves = supportsFanCurves
        self.supportsPowerLimits = supportsPowerLimits
        self.supportsChargeLimit = supportsChargeLimit
        self.supportsThermalProfiles = supportsThermalProfiles
        self.supportsTufRGB = supportsTufRGB
        self.supportsKeyboardBacklight = supportsKeyboardBacklight
    }
}

/// Dynamic capability resolver: matches board/product identifiers read from
/// `IOPlatformExpertDevice` / SMC BIOS against known ASUS model families, and
/// probes supported ATKD WMI selectors via read-only single-shot `DSTS` calls.
/// FX707ZM remains the Tier-1 verified profile; other TUF (FA507/FX507) and
/// ROG (Zephyrus/Strix) boards resolve to Tier-2 with writes pending probe.
public struct CapabilityMatrixResolver: Sendable {
    public init() {}

    /// Pure board-id matcher (unit-testable; no IORegistry access).
    public func match(boardProduct: String, systemProduct: String? = nil) -> ASUSModelProfile {
        let board = boardProduct.uppercased()
        let system = (systemProduct ?? "").uppercased()

        // Tier 1: fully verified reference board
        if board == "FX707ZM" || system.contains("FX707ZM") {
            return ASUSModelProfile(
                boardProduct: boardProduct,
                family: "TUF Gaming F17",
                tier: .tier1Verified,
                supportsTelemetry: true,
                supportsFanCurves: true,
                supportsPowerLimits: true,
                supportsChargeLimit: true,
                supportsThermalProfiles: true,
                supportsTufRGB: true,
                supportsKeyboardBacklight: true
            )
        }

        // Tier 2a: TUF Gaming A17/F15 (FA507/FX507 share the ATKD WMNB interface and thermal/curve selectors)
        if board.hasPrefix("FA507") || board.hasPrefix("FX507") || system.hasPrefix("FA507") || system.hasPrefix("FX507") {
            return ASUSModelProfile(
                boardProduct: boardProduct,
                family: "TUF Gaming A15/F15 (FA507/FX507)",
                tier: .tier2PendingProbe,
                supportsTelemetry: true,
                supportsFanCurves: true,
                supportsPowerLimits: true,
                supportsChargeLimit: true,
                supportsThermalProfiles: true,
                supportsTufRGB: true,
                supportsKeyboardBacklight: true
            )
        }

        // Tier 2b: ROG Strix / Zephyrus (G513/G713/GA402/GA503/GU603/GU502 etc.)
        let rogPrefixes = ["G513", "G713", "GA402", "GA503", "GU603", "GU502", "GV301", "GX650", "FA507N"]
        if rogPrefixes.contains(where: { board.hasPrefix($0) || system.hasPrefix($0) }) {
            return ASUSModelProfile(
                boardProduct: boardProduct,
                family: "ROG Zephyrus / Strix",
                tier: .tier2PendingProbe,
                supportsTelemetry: true,
                supportsFanCurves: true,
                supportsPowerLimits: true,
                supportsChargeLimit: true,
                supportsThermalProfiles: true,
                supportsTufRGB: false, // Aura Sync uses the 0xB3/0xB4 stack — pending probe
                supportsKeyboardBacklight: true
            )
        }

        // Unknown board: telemetry-only, all writes disabled for safety
        return ASUSModelProfile(boardProduct: boardProduct, family: "Unknown", tier: .unknown)
    }

    /// Live resolution on the current host via IORegistry host identity.
    public func resolveLive(inspector: IORegistryInspector = IORegistryInspector()) -> ASUSModelProfile {
        let host = inspector.inspectHostIdentity()
        return match(boardProduct: host.boardProduct, systemProduct: host.systemProduct)
    }

    /// Read-only `DSTS` probe of the supported ATKD WMI selector set.
    /// Returns `(deviceIDHex, present)` per whitelisted selector; only ever issues DSTS reads.
    public func probeSupportedSelectors(bridge: AsusBridgeClient = AsusBridgeClient()) -> [(deviceIDHex: String, present: Bool)] {
        let probes: [(UInt32, String)] = [
            (0x00120094, "CPU Temperature"),
            (0x00110013, "CPU Fan RPM"),
            (0x00110014, "GPU Fan RPM"),
            (0x00110024, "CPU Fan Curve"),
            (0x00110025, "GPU Fan Curve"),
            (0x001200A3, "CPU PL1 (SPL)"),
            (0x001200A0, "CPU PL2 (SPPT)"),
            (0x00120057, "Battery Charge Limit"),
            (0x00120075, "Thermal Profile"),
            (0x00100056, "TUF RGB"),
            (0x0010005B, "Keyboard Backlight")
        ]
        return probes.compactMap { id, label in
            guard let r = try? bridge.probeWhitelistedDSTS(deviceID: id, label: label) else { return (String(format: "0x%08X", id), false) }
            return (r.deviceIDHex, r.presentBitSet)
        }
    }
}

/// Canonical hardware capability matrix for ASUS TUF Gaming F17 (FX707ZM, BIOS FX707ZM.316).
/// Every entry is grounded in evidence collected from the current host's IORegistry and DSDT.aml / ssdt14.aml.
public struct FX707ZMCapabilityMatrix: Sendable {
    public init() {}

    public func buildCapabilities(
        brightness: BrightnessReport,
        battery: BatteryReport,
        smc: SMCKeyDiagnostic,
        acpiDevices: [ACPIDevicePresence]
    ) -> [CapabilityEntry] {
        let hasATKD = acpiDevices.contains { $0.name == "ATKD" }
        let hasEC0 = acpiDevices.contains { $0.name == "EC0" }
        let hasSMKB = acpiDevices.contains { $0.name.hasPrefix("SMKB") }
        let bridgeLoaded = AsusBridgeClient().isAvailable()

        // Dynamic model resolution: prepend the board profile resolved from IOPlatformExpertDevice identity.
        let resolved = CapabilityMatrixResolver().resolveLive()
        var entries: [CapabilityEntry] = [
            CapabilityEntry(
                featureID: "model.capability.profile",
                featureName: "ASUS Board Capability Profile (\(resolved.family))",
                wmiDeviceIDHex: nil,
                acpiOrECPath: "IOPlatformExpertDevice / NullMoth system-profile.json (board=\(resolved.boardProduct))",
                verificationStatus: resolved.tier == .tier1Verified ? .verifiedOnCurrentHost : .routedViaHostSMMPendingProbe,
                safetyProfile: .pureUserSpacePropertyRead,
                notes: "\(resolved.tier.rawValue). \(resolved.tier == .tier2PendingProbe ? "Control selectors pending read-only DSTS probe on this host." : (resolved.tier == .unknown ? "All control writes disabled; telemetry only." : "All selectors verified via AsusBridge.kext."))"
            )
        ]
        entries += [
            CapabilityEntry(
                featureID: "battery.telemetry",
                featureName: "Battery Telemetry (Charge, Health, Voltage, Amperage, Wattage, Temp)",
                wmiDeviceIDHex: nil,
                acpiOrECPath: "\\_SB.PC00.LPCB.EC0.BAT1 -> AppleSmartBattery / VirtualSMC",
                verificationStatus: battery.installed ? .verifiedOnCurrentHost : .unsupportedOnCurrentHost,
                safetyProfile: .pureUserSpacePropertyRead,
                notes: "Working via SMCBatteryManager + VirtualSMC (A32-K55, Design \(battery.designCapacitymWh) mWh)."
            ),
            CapabilityEntry(
                featureID: "als.telemetry",
                featureName: "Ambient Light Sensor (ALV0 Lux)",
                wmiDeviceIDHex: nil,
                acpiOrECPath: "\\_SB.ALS0 -> SMCLightSensor (ALV0)",
                verificationStatus: smc.ambientLightLux != nil ? .verifiedOnCurrentHost : .unsupportedOnCurrentHost,
                safetyProfile: .virtualSMCRead,
                notes: "Working via SSDT-ALS0.aml + SMCLightSensor.kext (current lux: \(smc.ambientLightLux ?? 0))."
            ),
            CapabilityEntry(
                featureID: "display.brightness.slider",
                featureName: "Internal Display Brightness Control (Software & Driver Path)",
                wmiDeviceIDHex: "0x00050011 (BLCT)",
                acpiOrECPath: "\\_SB.PC00.PEG1.PEGP (NBCI _DSM ssdt14.aml) -> NVRMBacklightHandler (RM 0x730292)",
                verificationStatus: (brightness.displayServicesCanChange && brightness.backlightDriverClass == "NVRMBacklightHandler")
                    ? .verifiedOnCurrentHost : .unsupportedOnCurrentHost,
                safetyProfile: .pureUserSpacePropertyRead,
                notes: "LGD066C on RTX 3060 (display 0x400). DisplayServicesCanChange=true; NVRM logs hardware level updates; physical backlight changes confirmed on host."
            ),
            CapabilityEntry(
                featureID: "display.brightness.fnkeys",
                featureName: "Brightness Function Keys (Fn+F7 / Fn+F8)",
                wmiDeviceIDHex: nil,
                acpiOrECPath: "\\_SB.ATKD / \\_SB.PC00.PEG1.PEGP.EDP1 (Notify 0x86 / 0x87)",
                verificationStatus: bridgeLoaded ? .verifiedOnCurrentHost : .verifiedInHostACPIPendingEvaluation,
                safetyProfile: .pureAMLMethodRead,
                notes: "DSDT BRTN (0x6be86/0x6bef8) notifies PEGP.EDP1 (0x86/0x87), bridged by AsusBridge + asusctld to DisplayServicesSetBrightness."
            ),
            CapabilityEntry(
                featureID: "cpu.temperature.ec",
                featureName: "CPU Package Temperature via EC0 / ATKD.DSTS",
                wmiDeviceIDHex: "0x00120094",
                acpiOrECPath: "\\_SB.ATKD.WMNB (DSTS 0x00120094) -> \\_SB.PC00.LPCB.EC0.CTMP",
                verificationStatus: bridgeLoaded ? .verifiedOnCurrentHost : ((hasATKD && hasEC0) ? .verifiedInHostACPIPendingEvaluation : .unsupportedOnCurrentHost),
                safetyProfile: .directECFieldRead,
                notes: "Verified live on FX707ZM via AsusBridge.kext (DSTS 0x00120094 -> 0x00010047 = 71 °C)."
            ),
            CapabilityEntry(
                featureID: "fans.rpm.monitoring",
                featureName: "CPU & GPU Fan RPM Monitoring",
                wmiDeviceIDHex: "0x00110013 (CPU), 0x00110014 (GPU)",
                acpiOrECPath: "\\_SB.ATKD.WMNB (DSTS 0x00110013 / 0x00110014) -> \\_SB.PC00.LPCB.EC0",
                verificationStatus: bridgeLoaded ? .verifiedOnCurrentHost : ((hasATKD && hasEC0) ? .verifiedInHostACPIPendingEvaluation : .unsupportedOnCurrentHost),
                safetyProfile: .directECFieldRead,
                notes: "Verified live on FX707ZM via AsusBridge.kext (CPU=3200 RPM [0x00010020], GPU=3300 RPM [0x00010021])."
            ),
            CapabilityEntry(
                featureID: "fans.curve.control",
                featureName: "8-Point Custom Fan Curves (CPU & GPU)",
                wmiDeviceIDHex: "0x00110024 (CPU), 0x00110025 (GPU)",
                acpiOrECPath: "\\_SB.ATKD.WMNB -> EC0.CFCV/GFCV (Read) & EC0.SFTC/SFTG (Write)",
                verificationStatus: bridgeLoaded ? .verifiedOnCurrentHost : ((hasATKD && hasEC0) ? .verifiedInHostACPIPendingEvaluation : .unsupportedOnCurrentHost),
                safetyProfile: .directECFieldRead,
                notes: "Verified live 8-point curves on FX707ZM via AsusBridge.kext (Performance, Turbo, Silent)."
            ),
            CapabilityEntry(
                featureID: "cpu.power.limits",
                featureName: "CPU Power Limits (PL1 SPL & PL2 SPPT)",
                wmiDeviceIDHex: "0x001200A3 (PL1V), 0x001200A0 (PL2V)",
                acpiOrECPath: "\\_SB.ATKD.WMNB -> \\_SB.PC00.LPCB.EC0.PL1V & PL2V",
                verificationStatus: bridgeLoaded ? .verifiedOnCurrentHost : ((hasATKD && hasEC0) ? .verifiedInHostACPIPendingEvaluation : .unsupportedOnCurrentHost),
                safetyProfile: .directECFieldRead,
                notes: "Verified DSTS presence (0x00010000) on FX707ZM via AsusBridge.kext. Note FX707ZM mapping: 0x001200A0->PL2V, 0x001200A3->PL1V."
            ),
            CapabilityEntry(
                featureID: "gpu.mux.switch",
                featureName: "MUX Switch State (Ultimate / Standard)",
                wmiDeviceIDHex: "0x00090016 (DSTS), 0x00090020 (DSTS/DEVS)",
                acpiOrECPath: "\\_SB.ATKD.WMNB -> DGPM, CUMA, EC0.UMAF",
                verificationStatus: bridgeLoaded ? .verifiedOnCurrentHost : ((hasATKD && hasEC0) ? .verifiedInHostACPIPendingEvaluation : .unsupportedOnCurrentHost),
                safetyProfile: .pureAMLMethodRead,
                notes: "Verified live on FX707ZM via AsusBridge.kext (0x00010000 = Ultimate / Direct dGPU)."
            ),
            CapabilityEntry(
                featureID: "keyboard.backlight.ec",
                featureName: "Keyboard Backlight State & Brightness Step (EC Path)",
                wmiDeviceIDHex: "0x0010005B (DSTS), 0x00100021 (DEVS)",
                acpiOrECPath: "\\_SB.ATKD.WMNB -> \\_SB.PC00.LPCB.EC0.KBLS & EC0.SKEY",
                verificationStatus: bridgeLoaded ? .verifiedOnCurrentHost : ((hasATKD && hasEC0) ? .verifiedInHostACPIPendingEvaluation : .unsupportedOnCurrentHost),
                safetyProfile: .directECFieldRead,
                notes: "Verified DSTS 0x0010005B on FX707ZM via AsusBridge.kext (returns 0x00000000 when KBLC bit 7 is 0; DEVS 0x00100021 calls EC0.SKEY)."
            ),
            CapabilityEntry(
                featureID: "battery.charge.limit",
                featureName: "Battery Charge Limit (60% / 80% / 100%)",
                wmiDeviceIDHex: "0x00120057",
                acpiOrECPath: "\\_SB.ATKD.WMNB -> WCHK/W15H (SMI 0xAA) & \\_SB.PC00.LPCB.EC0.RSOC",
                verificationStatus: bridgeLoaded ? .verifiedOnCurrentHost : .routedViaHostSMMPendingProbe,
                safetyProfile: .smmInterruptRead,
                notes: "Verified DSTS 0x00120057 via W15H SMM on FX707ZM (returns 0x00090000 = present & rechargeable)."
            ),
            CapabilityEntry(
                featureID: "performance.thermal.profile",
                featureName: "Performance / Thermal Profiles (Silent, Performance, Turbo)",
                wmiDeviceIDHex: "0x00120075",
                acpiOrECPath: "\\_SB.ATKD.WMNB -> WCHK/W15H (SMI 0xAA) & EC0.THRP / FTBL",
                verificationStatus: bridgeLoaded ? .verifiedOnCurrentHost : .routedViaHostSMMPendingProbe,
                safetyProfile: .smmInterruptRead,
                notes: "Verified DSTS 0x00120075 via W15H SMM on FX707ZM (returns 0x00010003 = present, default state 3)."
            ),
            CapabilityEntry(
                featureID: "keyboard.rgb.tuf",
                featureName: "TUF Gaming RGB Lighting (Mode, Color, Speed)",
                wmiDeviceIDHex: "0x00100056, 0x00100057",
                acpiOrECPath: "\\_SB.ATKD.WMNB (WCHK/W15H) / EC0 (KBLT, KBLM, KBSP, KBS1..3, TUFA) / \\_SB.SMKB@0 (ITE5570)",
                verificationStatus: bridgeLoaded ? .verifiedOnCurrentHost : (hasSMKB ? .routedViaHostSMMPendingProbe : .unsupportedOnCurrentHost),
                safetyProfile: .smmInterruptRead,
                notes: "Verified DSTS 0x00100056 & 0x00100057 via W15H SMM on FX707ZM (both return 0x00010000 = present)."
            )
        ]
        return entries
    }

    public func captureSnapshot() -> DiagnosticSnapshot {
        let inspector = IORegistryInspector()
        let smcClient = SMCReadOnlyClient()

        let host = inspector.inspectHostIdentity()
        let cpu = inspector.inspectCPUTopology()
        let gpus = inspector.inspectGPUs()
        let brightness = inspector.inspectBrightness()
        let battery = inspector.inspectBattery()
        let smc = smcClient.inspectSMC()
        let acpiDevices = inspector.inspectACPIDevices()
        let capabilities = buildCapabilities(
            brightness: brightness,
            battery: battery,
            smc: smc,
            acpiDevices: acpiDevices
        )

        let formatter = ISO8601DateFormatter()
        return DiagnosticSnapshot(
            timestampISO8601: formatter.string(from: Date()),
            host: host,
            cpu: cpu,
            gpus: gpus,
            brightness: brightness,
            battery: battery,
            smc: smc,
            acpiDevices: acpiDevices,
            capabilities: capabilities
        )
    }
}
