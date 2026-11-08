import SwiftUI
import AppKit
import ASUSControlCore

public struct MenuBarView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Bar
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ASUS TUF Gaming F17")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("FX707ZM • BIOS \(viewModel.snapshot.host.biosVersion)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(viewModel.snapshot.battery.externalConnected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(viewModel.snapshot.battery.externalConnected ? "AC Power" : "Battery")
                        .font(.caption.bold())
                        .foregroundStyle(viewModel.snapshot.battery.externalConnected ? Color.green : Color.orange)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }

            Divider()

            // Live Telemetry Cards
            HStack(spacing: 8) {
                telemetryCard(
                    icon: "thermometer.high",
                    title: "CPU Temp",
                    value: "\(viewModel.hardwareVerification.cpuTempCelsius)°C",
                    sub: "PL1: \(viewModel.hardwareVerification.verifiedPL1Watts)W",
                    color: viewModel.hardwareVerification.cpuTempCelsius >= 80 ? .red : .orange
                )
                telemetryCard(
                    icon: "fanblades.fill",
                    title: "Fans (RPM)",
                    value: "\(viewModel.hardwareVerification.cpuFanRPM)",
                    sub: "GPU: \(viewModel.hardwareVerification.gpuFanRPM)",
                    color: .cyan
                )
                telemetryCard(
                    icon: "battery.100.bolt",
                    title: "Battery",
                    value: String(format: "%.0f%%", viewModel.snapshot.battery.chargePercent),
                    sub: "Limit: \(viewModel.hardwareVerification.verifiedChargeLimit)%",
                    color: .green
                )
            }

            // Thermal Profile Selector
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Thermal Profile")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("WMI: \(viewModel.hardwareVerification.verifiedProfile.displayName)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    ForEach(ThermalProfile.allCases) { profile in
                        let isSelected = viewModel.settings.thermalProfile == profile
                        let disabled = (profile == .turbo && !viewModel.snapshot.battery.externalConnected)
                        Button {
                            viewModel.setThermalProfile(profile)
                        } label: {
                            HStack(spacing: 4) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.bold())
                                }
                                Text(profile == .balanced ? "Balanced" : profile.displayName)
                                    .font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(isSelected ? Color.orange : Color(nsColor: .controlBackgroundColor))
                            .foregroundStyle(isSelected ? Color.black : (disabled ? Color.secondary.opacity(0.5) : Color.primary))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(isSelected ? Color.orange : Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(disabled)
                    }
                }
            }

            // Battery Charge Limit Selector
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Battery Charge Limit")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Active: \(viewModel.hardwareVerification.verifiedChargeLimit)%")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.green)
                }
                HStack(spacing: 8) {
                    ForEach([60, 80, 100], id: \.self) { limit in
                        let isSelected = viewModel.settings.batteryChargeLimitPercent == limit
                        Button {
                            viewModel.setChargeLimit(limit)
                        } label: {
                            HStack(spacing: 4) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.bold())
                                }
                                Text("\(limit)%")
                                    .font(.caption.bold().monospacedDigit())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.green : Color(nsColor: .controlBackgroundColor))
                            .foregroundStyle(isSelected ? Color.black : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(isSelected ? Color.green : Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Display Brightness Slider
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text("Display Brightness")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", viewModel.displayBrightnessPercent))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                }
                HStack(spacing: 8) {
                    Button {
                        viewModel.stepDisplayBrightness(up: false)
                    } label: {
                        Image(systemName: "minus")
                            .font(.caption2.bold())
                            .frame(width: 22, height: 20)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Slider(
                        value: Binding(
                            get: { viewModel.displayBrightnessPercent },
                            set: { viewModel.setDisplayBrightness($0) }
                        ),
                        in: 0...100
                    )
                    .tint(.orange)

                    Button {
                        viewModel.stepDisplayBrightness(up: true)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption2.bold())
                            .frame(width: 22, height: 20)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Keyboard Backlight Brightness & RGB Quick Row
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Keyboard Backlight & RGB")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.settings.rgbMode.displayName)
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }

                // Brightness Level (Off, 1, 2, 3)
                HStack(spacing: 6) {
                    ForEach(KeyboardBrightnessLevel.allCases) { lvl in
                        let isSel = viewModel.settings.keyboardBrightness == lvl
                        Button {
                            viewModel.applyRGBSettings(brightness: lvl)
                        } label: {
                            Text(lvl == .off ? "Off" : "Level \(lvl.rawValue)")
                                .font(.caption2.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(isSel ? Color.orange : Color(nsColor: .controlBackgroundColor))
                                .foregroundStyle(isSel ? Color.black : Color.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isSel ? Color.orange : Color.secondary.opacity(0.25), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Footer Actions
            HStack(spacing: 10) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "dashboard")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                        Text("Open Full Dashboard")
                    }
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.orange)
                    .foregroundStyle(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(.caption.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .foregroundStyle(Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func telemetryCard(icon: String, title: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
            Text(sub)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}
