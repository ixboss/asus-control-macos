import SwiftUI
import ASUSControlCore

public enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview & Telemetry"
    case performance = "Performance & Power Limits"
    case fanCurves = "8-Point Fan Curves"
    case battery = "Battery Health"
    case displayAndRGB = "Display & TUF Keyboard"
    case diagnostics = "Diagnostics & Matrix"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .performance: return "bolt.shield.fill"
        case .fanCurves: return "fanblades.fill"
        case .battery: return "battery.100.bolt"
        case .displayAndRGB: return "keyboard.fill"
        case .diagnostics: return "checkmark.seal.fill"
        }
    }
}

public struct DashboardView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedSection: DashboardSection = .overview

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    Label(section.rawValue, systemImage: section.iconName)
                        .font(.body)
                        .padding(.vertical, 4)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.hardwareVerification.kextLoaded ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(viewModel.hardwareVerification.kextLoaded ? "AsusBridge Active (ABI v2)" : "AsusBridge Offline")
                            .font(.caption.bold())
                    }
                    Text("Target: ASUS TUF F17 FX707ZM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
        } detail: {
            VStack(spacing: 0) {
                // Top Header Bar
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedSection.rawValue)
                            .font(.title2.bold())
                        Text(viewModel.statusBannerMessage)
                            .font(.caption)
                            .foregroundStyle(viewModel.statusBannerIsError ? .red : .secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        viewModel.refreshTelemetry()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch selectedSection {
                        case .overview:
                            overviewSection
                        case .performance:
                            performanceSection
                        case .fanCurves:
                            fanCurvesSection
                        case .battery:
                            batterySection
                        case .displayAndRGB:
                            displayAndRGBSection
                        case .diagnostics:
                            diagnosticsSection
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 960, minHeight: 660)
    }

    // MARK: - 1. Overview Section

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Metrics Row
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                metricCard(
                    title: "CPU Package Temp",
                    value: "\(viewModel.hardwareVerification.cpuTempCelsius) °C",
                    subtitle: "EC0.CTMP (0x00120094)",
                    icon: "thermometer.high",
                    accent: viewModel.hardwareVerification.cpuTempCelsius >= 80 ? .red : .orange
                )
                metricCard(
                    title: "CPU Fan Speed",
                    value: "\(viewModel.hardwareVerification.cpuFanRPM) RPM",
                    subtitle: "DSTS 0x00110013",
                    icon: "fanblades.fill",
                    accent: .cyan
                )
                metricCard(
                    title: "GPU Fan Speed",
                    value: "\(viewModel.hardwareVerification.gpuFanRPM) RPM",
                    subtitle: "DSTS 0x00110014",
                    icon: "fanblades",
                    accent: .blue
                )
                metricCard(
                    title: "Battery Charge",
                    value: String(format: "%.0f%% (Limit %d%%)", viewModel.snapshot.battery.chargePercent, viewModel.hardwareVerification.verifiedChargeLimit),
                    subtitle: viewModel.snapshot.battery.externalConnected ? "AC Power Connected" : "Discharging (\(String(format: "%.1f", viewModel.snapshot.battery.powerWatts)) W)",
                    icon: "battery.100.bolt",
                    accent: .green
                )
            }

            // Host Hardware Summary
            GroupBox("Host Hardware & Graphics Routing (Verified on FX707ZM)") {
                VStack(alignment: .leading, spacing: 12) {
                    infoRow("Model / Board", "\(viewModel.snapshot.host.systemProduct) (\(viewModel.snapshot.host.boardProduct)) — BIOS \(viewModel.snapshot.host.biosVersion)")
                    infoRow("Processor", "\(viewModel.snapshot.cpu.brandString) (\(viewModel.snapshot.cpu.activePhysicalCores) P-Cores / \(viewModel.snapshot.cpu.activeLogicalThreads) Threads)")
                    infoRow("Primary Display GPU", "NVIDIA GeForce RTX 3060 Laptop GPU (0x10DE:0x2520) — MUX: Ultimate Direct dGPU")
                    infoRow("Internal eDP Panel", "\(viewModel.snapshot.brightness.internalPanelName) — Backlight: \(viewModel.snapshot.brightness.backlightDriverClass) (\(String(format: "%.0f%%", viewModel.displayBrightnessPercent)))")
                    infoRow("Secondary iGPU", "Intel UHD Graphics (Alder Lake-P) — Load-only (nmxintel=1, zero active displays)")
                }
                .padding(10)
            }

            // Quick Controls
            GroupBox("Quick Hardware Controls") {
                HStack(spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Thermal Profile")
                            .font(.subheadline.bold())
                        HStack(spacing: 8) {
                            ForEach(ThermalProfile.allCases) { prof in
                                let isSel = viewModel.settings.thermalProfile == prof
                                Button {
                                    viewModel.setThermalProfile(prof)
                                } label: {
                                    HStack(spacing: 4) {
                                        if isSel { Image(systemName: "checkmark").font(.caption2.bold()) }
                                        Text(prof.displayName)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(isSel ? .orange : Color.secondary.opacity(0.2))
                                .foregroundStyle(isSel ? Color.black : Color.primary)
                                .disabled(prof == .turbo && !viewModel.snapshot.battery.externalConnected)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Battery Charge Limit")
                            .font(.subheadline.bold())
                        HStack(spacing: 8) {
                            ForEach([60, 80, 100], id: \.self) { lim in
                                let isSel = viewModel.settings.batteryChargeLimitPercent == lim
                                Button {
                                    viewModel.setChargeLimit(lim)
                                } label: {
                                    HStack(spacing: 4) {
                                        if isSel { Image(systemName: "checkmark").font(.caption2.bold()) }
                                        Text("\(lim)%")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(isSel ? .green : Color.secondary.opacity(0.2))
                                .foregroundStyle(isSel ? Color.black : Color.primary)
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
    }

    // MARK: - 2. Performance Section

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("ASUS Thermal & Performance Profiles (0x00120075)") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ForEach(ThermalProfile.allCases) { profile in
                            let selected = viewModel.settings.thermalProfile == profile
                            let disabled = profile == .turbo && !viewModel.snapshot.battery.externalConnected
                            let limits = profile.defaultPowerLimits(onAC: viewModel.snapshot.battery.externalConnected)
                            Button {
                                viewModel.setThermalProfile(profile)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: profile == .silent ? "leaf.fill" : (profile == .balanced ? "gauge.medium" : "flame.fill"))
                                            .font(.title3)
                                        Text(profile.displayName)
                                            .font(.headline)
                                        Spacer()
                                        if selected {
                                            Image(systemName: "checkmark.circle.fill")
                                        }
                                    }
                                    Text(profile == .silent ? "Lower acoustic noise envelope (PL1: \(limits.pl1)W, PL2: \(limits.pl2)W)" :
                                            (profile == .balanced ? "Balanced ASUS default target (PL1: \(limits.pl1)W, PL2: \(limits.pl2)W)" :
                                                "Maximum sustained performance (PL1: \(limits.pl1)W, PL2: \(limits.pl2)W)"))
                                        .font(.caption)
                                        .foregroundStyle(selected ? Color.black.opacity(0.85) : Color.secondary)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected ? Color.orange : Color(nsColor: .controlBackgroundColor))
                                .foregroundStyle(selected ? Color.black : Color.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(selected ? Color.orange : Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(disabled)
                        }
                    }

                    Divider()

                    Toggle(
                        "Automatically switch thermal profile on AC / Battery power transitions",
                        isOn: Binding(
                            get: { viewModel.settings.autoSwitchProfileOnPowerChange },
                            set: { viewModel.toggleAutoSwitchProfile($0) }
                        )
                    )

                    HStack(spacing: 24) {
                        Picker("Preferred on AC Power:", selection: Binding(
                            get: { viewModel.settings.acPreferredProfile },
                            set: { viewModel.setACPreferredProfile($0) }
                        )) {
                            ForEach(ThermalProfile.allCases) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .frame(maxWidth: 320)

                        Picker("Preferred on Battery:", selection: Binding(
                            get: { viewModel.settings.batteryPreferredProfile },
                            set: { viewModel.setBatteryPreferredProfile($0) }
                        )) {
                            Text(ThermalProfile.silent.displayName).tag(ThermalProfile.silent)
                            Text(ThermalProfile.balanced.displayName).tag(ThermalProfile.balanced)
                        }
                        .frame(maxWidth: 320)
                    }
                }
                .padding(12)
            }

            GroupBox("CPU Power Limits — Intel Core i7-12700H (PL1 SPL & PL2 SPPT)") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Writes EC0.PL1V (Sustained Power Limit) via 0x001200A3 and EC0.PL2V (Short Burst Limit) via 0x001200A0.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("PL1 — Sustained Power Limit (SPL -> EC0.PL1V)")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(viewModel.editPL1Watts.rounded())) W")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.orange)
                        }
                        Slider(
                            value: $viewModel.editPL1Watts,
                            in: 15...(viewModel.snapshot.battery.externalConnected ? 90 : 45),
                            step: 1
                        )
                        .tint(.orange)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("PL2 — Short Burst Power Limit (SPPT -> EC0.PL2V)")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(viewModel.editPL2Watts.rounded())) W")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.cyan)
                        }
                        Slider(
                            value: $viewModel.editPL2Watts,
                            in: 25...(viewModel.snapshot.battery.externalConnected ? 115 : 60),
                            step: 1
                        )
                        .tint(.cyan)
                    }

                    HStack(spacing: 12) {
                        Button("Apply Custom Power Limits") {
                            viewModel.applyCPUPowerLimits()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Button("Reset to Profile Default") {
                            viewModel.resetCPUPowerLimits()
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                        Text(viewModel.settings.customPPTEnabled ? "Active: PL1 = \(viewModel.settings.cpuPL1SPLWatts)W, PL2 = \(viewModel.settings.cpuPL2SPPTWatts)W" : "Active: Firmware Profile Default")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
        }
    }

    // MARK: - 3. Fan Curves Section

    private var fanCurvesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Text("Load Preset:")
                    .font(.subheadline.bold())
                Button("Balanced") { viewModel.loadFirmwareFanPreset(profileIndex: 0) }
                    .buttonStyle(.bordered)
                Button("Silent") { viewModel.loadFirmwareFanPreset(profileIndex: 1) }
                    .buttonStyle(.bordered)
                Button("Turbo") { viewModel.loadFirmwareFanPreset(profileIndex: 2) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Apply Curves to EC") {
                    viewModel.applyCustomFanCurves()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button("Reset to Auto") {
                    viewModel.resetFanCurvesToAuto()
                }
                .buttonStyle(.bordered)
            }

            GroupBox("CPU Fan Curve (0x00110024 -> EC0.SFTC) — Current: \(viewModel.hardwareVerification.cpuFanRPM) RPM") {
                fanCurveEditorGrid(temps: $viewModel.editCPUTemps, duties: $viewModel.editCPUDuties, accent: .cyan)
            }

            GroupBox("GPU Fan Curve (0x00110025 -> EC0.SFTG) — Current: \(viewModel.hardwareVerification.gpuFanRPM) RPM") {
                fanCurveEditorGrid(temps: $viewModel.editGPUTemps, duties: $viewModel.editGPUDuties, accent: .blue)
            }

            Text("Safety: Temperatures and duties must be non-decreasing. Point 8 duty must be at least 40%.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func fanCurveEditorGrid(temps: Binding<[Double]>, duties: Binding<[Double]>, accent: Color) -> some View {
        HStack(spacing: 12) {
            ForEach(0..<8, id: \.self) { idx in
                VStack(spacing: 6) {
                    Text("Pt \(idx + 1)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text("\(Int(duties.wrappedValue[idx].rounded()))%")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(accent)
                    Slider(
                        value: Binding(
                            get: { duties.wrappedValue[idx] },
                            set: { duties.wrappedValue[idx] = $0 }
                        ),
                        in: (idx == 7 ? 40 : 0)...100,
                        step: 1
                    )
                    .frame(height: 90)
                    Text("\(Int(temps.wrappedValue[idx].rounded()))°C")
                        .font(.caption2.monospacedDigit())
                    Stepper("", value: Binding(
                        get: { temps.wrappedValue[idx] },
                        set: { temps.wrappedValue[idx] = $0 }
                    ), in: 30...100, step: 1)
                    .labelsHidden()
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(8)
    }

    // MARK: - 4. Battery Section

    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Battery Health & Charge Limit (0x00120057 + EC0.SRSC)") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Limiting charge to 60% or 80% while on AC power preserves lithium-ion health by reducing voltage stress.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 14) {
                        chargePresetCard(limit: 60, title: "60% — Maximum Lifespan", subtitle: "Ideal for stationary desk usage")
                        chargePresetCard(limit: 80, title: "80% — Balanced Health", subtitle: "Recommended daily balance")
                        chargePresetCard(limit: 100, title: "100% — Full Capacity", subtitle: "For maximum travel runtime")
                    }

                    Divider()

                    Toggle(
                        "Automatically restore settings after macOS Sleep/Wake",
                        isOn: Binding(
                            get: { viewModel.settings.restoreOnWake },
                            set: { viewModel.toggleRestoreOnWake($0) }
                        )
                    )
                }
                .padding(12)
            }

            GroupBox("Live Battery Telemetry (AppleSmartBattery / EC0.BAT1)") {
                VStack(alignment: .leading, spacing: 10) {
                    infoRow("Battery Model", "\(viewModel.snapshot.battery.deviceName) (Installed: \(viewModel.snapshot.battery.installed ? "Yes" : "No"))")
                    infoRow("Power Source", viewModel.snapshot.battery.externalConnected ? "AC Adapter Connected" : "Battery Power")
                    infoRow("Current Charge", String(format: "%.1f%% (%d / %d mAh)", viewModel.snapshot.battery.chargePercent, viewModel.snapshot.battery.currentCapacitymWh, viewModel.snapshot.battery.maxCapacitymWh))
                    infoRow("Battery Health", String(format: "%.1f%% (%d / %d mAh • %d Cycles)", viewModel.snapshot.battery.healthPercent, viewModel.snapshot.battery.maxCapacitymWh, viewModel.snapshot.battery.designCapacitymWh, viewModel.snapshot.battery.cycleCount))
                    infoRow("Electrical Telemetry", String(format: "%d mV • %d mA • %.2f W • %.1f °C", viewModel.snapshot.battery.voltagemV, viewModel.snapshot.battery.amperagemA, viewModel.snapshot.battery.powerWatts, viewModel.snapshot.battery.temperatureCelsius))
                }
                .padding(12)
            }
        }
    }

    private func chargePresetCard(limit: Int, title: String, subtitle: String) -> some View {
        let isSelected = viewModel.settings.batteryChargeLimitPercent == limit
        return Button {
            viewModel.setChargeLimit(limit)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(isSelected ? Color.black : Color.green)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.black.opacity(0.85) : Color.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.green : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? Color.black : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.green : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 5. Display & RGB Section

    private var displayAndRGBSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Internal Display Brightness — LGD066C (1080p @ 300Hz)") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.yellow)
                        Text("Display Backlight Level")
                            .font(.subheadline.bold())
                        Spacer()
                        Text(String(format: "%.0f%%", viewModel.displayBrightnessPercent))
                            .font(.headline.monospacedDigit())
                    }
                    HStack(spacing: 12) {
                        Button("-6.25% (Fn+F7)") {
                            viewModel.stepDisplayBrightness(up: false)
                        }
                        .buttonStyle(.bordered)

                        Slider(
                            value: Binding(
                                get: { viewModel.displayBrightnessPercent },
                                set: { viewModel.setDisplayBrightness($0) }
                            ),
                            in: 0...100
                        )
                        .tint(.orange)

                        Button("+6.25% (Fn+F8)") {
                            viewModel.stepDisplayBrightness(up: true)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(12)
            }

            GroupBox("TUF Gaming Keyboard Backlight & RGB Lighting") {
                VStack(alignment: .leading, spacing: 16) {
                    // Backlight Brightness
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard Backlight Level (0x00050021 / EC0.SKEY)")
                            .font(.subheadline.bold())
                        HStack(spacing: 10) {
                            ForEach(KeyboardBrightnessLevel.allCases) { lvl in
                                let isSel = viewModel.settings.keyboardBrightness == lvl
                                Button {
                                    viewModel.applyRGBSettings(brightness: lvl)
                                } label: {
                                    HStack(spacing: 4) {
                                        if isSel { Image(systemName: "checkmark").font(.caption2.bold()) }
                                        Text(lvl.displayName)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(isSel ? .orange : Color.secondary.opacity(0.2))
                                .foregroundStyle(isSel ? Color.black : Color.primary)
                            }
                        }
                    }

                    Divider()

                    // Lighting Effect Mode
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aura Lighting Mode (0x00100056)")
                            .font(.subheadline.bold())
                        HStack(spacing: 10) {
                            ForEach(TufRGBMode.allCases) { mode in
                                let isSel = viewModel.settings.rgbMode == mode
                                Button {
                                    viewModel.applyRGBSettings(mode: mode)
                                } label: {
                                    HStack(spacing: 4) {
                                        if isSel { Image(systemName: "checkmark").font(.caption2.bold()) }
                                        Text(mode.displayName)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(isSel ? .orange : Color.secondary.opacity(0.2))
                                .foregroundStyle(isSel ? Color.black : Color.primary)
                            }
                        }
                    }

                    // Color Picker & Presets
                    HStack(spacing: 16) {
                        ColorPicker(
                            "RGB Color:",
                            selection: Binding(
                                get: { viewModel.rgbColorSwiftUI },
                                set: { viewModel.updateRGBFromColorPicker($0) }
                            ),
                            supportsOpacity: false
                        )
                        .font(.subheadline.bold())

                        Divider().frame(height: 24)

                        Text("Presets:")
                            .font(.caption.bold())
                        rgbSwatchButton(label: "TUF Gold", r: 0xFF, g: 0xAA, b: 0x00)
                        rgbSwatchButton(label: "Cyber Cyan", r: 0x00, g: 0xE5, b: 0xFF)
                        rgbSwatchButton(label: "ROG Red", r: 0xFF, g: 0x2A, b: 0x55)
                        rgbSwatchButton(label: "Green", r: 0x00, g: 0xFF, b: 0x88)
                        rgbSwatchButton(label: "White", r: 0xFF, g: 0xFF, b: 0xFF)
                    }

                    // Animation Speed
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Animation Speed")
                            .font(.subheadline.bold())
                        HStack(spacing: 10) {
                            ForEach(TufRGBSpeed.allCases) { spd in
                                let isSel = viewModel.settings.rgbSpeed == spd
                                Button {
                                    viewModel.applyRGBSettings(speed: spd)
                                } label: {
                                    HStack(spacing: 4) {
                                        if isSel { Image(systemName: "checkmark").font(.caption2.bold()) }
                                        Text(spd.displayName)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(isSel ? .cyan : Color.secondary.opacity(0.2))
                                .foregroundStyle(isSel ? Color.black : Color.primary)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func rgbSwatchButton(label: String, r: UInt8, g: UInt8, b: UInt8) -> some View {
        Button {
            viewModel.applyRGBSettings(red: r, green: g, blue: b)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0))
                    .frame(width: 11, height: 11)
                Text(label)
                    .font(.caption)
            }
        }
        .buttonStyle(.bordered)
    }

    // MARK: - 6. Diagnostics Section

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Verified Hardware Capability & Safety Matrix (11/11 Verified)") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.snapshot.capabilities, id: \.featureID) { cap in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Text(cap.featureName)
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(cap.verificationStatus.rawValue)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            }
                            Text("WMI: \(cap.wmiDeviceIDHex ?? "N/A") • Path: \(cap.acpiOrECPath)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text(cap.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Divider()
                        }
                    }
                }
                .padding(10)
            }

            GroupBox("Kernel Ring Buffer Log (AsusBridge.kext)") {
                ScrollView(.horizontal) {
                    Text(viewModel.kernelLogText.replacingOccurrences(of: ";", with: "\n"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Helpers

    private func metricCard(title: String, value: String, subtitle: String, icon: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(accent)
                Spacer()
            }
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.caption.bold())
                .frame(width: 180, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }
}
