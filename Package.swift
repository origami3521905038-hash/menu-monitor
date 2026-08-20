// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MenuMonitor",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MenuMonitorCore", targets: ["MenuMonitorCore"]),
        .library(name: "MenuMonitorUI", type: .dynamic, targets: ["MenuMonitorUI"]),
        .executable(name: "MenuMonitor", targets: ["MenuMonitorApp"]),
        .executable(name: "MenuMonitorProbe", targets: ["MenuMonitorProbe"])
    ],
    targets: [
        .target(
            name: "CIOReportRuntime",
            path: "Sources/CIOReportRuntime",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("CoreFoundation")]
        ),
        .target(
            name: "CIOHIDTemperatureRuntime",
            path: "Sources/CIOHIDTemperatureRuntime",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "MenuMonitorCore",
            dependencies: ["CIOReportRuntime", "CIOHIDTemperatureRuntime"],
            path: "Sources/MenuMonitorCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "MenuMonitorApp",
            dependencies: ["MenuMonitorCore"],
            path: "Sources/MenuMonitorApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .target(
            name: "MenuMonitorUI",
            path: "Sources/MenuMonitorUI",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Charts"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "MenuMonitorProbe",
            dependencies: ["MenuMonitorCore"],
            path: "Sources/MenuMonitorProbe"
        ),
        .testTarget(
            name: "MenuMonitorCoreTests",
            dependencies: ["MenuMonitorCore"],
            path: "Tests/MenuMonitorCoreTests"
        )
    ]
)
