// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ASUSControlMacOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ASUSControlCore",
            targets: ["ASUSControlCore"]
        ),
        .executable(
            name: "asusctl-diag",
            targets: ["asusctl-diag"]
        ),
        .executable(
            name: "asusctl",
            targets: ["asusctl"]
        ),
        .executable(
            name: "asusctld",
            targets: ["asusctld"]
        ),
        .executable(
            name: "ASUSControlApp",
            targets: ["ASUSControlApp"]
        )
    ],
    targets: [
        .target(
            name: "ASUSControlCore",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "asusctl-diag",
            dependencies: ["ASUSControlCore"]
        ),
        .executableTarget(
            name: "asusctl",
            dependencies: ["ASUSControlCore"]
        ),
        .executableTarget(
            name: "asusctld",
            dependencies: ["ASUSControlCore"]
        ),
        .executableTarget(
            name: "ASUSControlApp",
            dependencies: ["ASUSControlCore"],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "ASUSControlCoreTests",
            dependencies: ["ASUSControlCore"]
        )
    ]
)
