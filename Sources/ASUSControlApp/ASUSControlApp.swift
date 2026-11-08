import SwiftUI
import AppKit
import ASUSControlCore

@main
struct ASUSControlApp: App {
    @StateObject private var viewModel = AppViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("ASUS Control — TUF Gaming F17 (FX707ZM)", id: "dashboard") {
            DashboardView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 980, height: 660)

        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "fanblades.fill")
                Text("\(viewModel.bridgeSnapshot?.cpuTempCelsius ?? 68)°C")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
