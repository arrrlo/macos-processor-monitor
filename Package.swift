// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProcessorMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ProcessorMonitor", targets: ["ProcessorMonitor"]),
        .executable(name: "ProcessorMonitorHelper", targets: ["ProcessorMonitorHelper"]),
    ],
    targets: [
        // Declarations for the private IOHIDEventSystemClient API (symbols are exported by IOKit)
        // and the AppleSMC user client's parameter block.
        .target(name: "CSystemShims", linkerSettings: [.linkedFramework("IOKit")]),
        // Pure logic, no system calls.
        .target(name: "ProcessorMonitorCore"),
        // Thin adapters over Mach, libproc, IOKit, launchctl and XPC.
        .target(
            name: "ProcessorMonitorSystem",
            dependencies: ["ProcessorMonitorCore", "CSystemShims"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // AppKit status item, menu and SwiftUI dashboard.
        .target(name: "ProcessorMonitorUI", dependencies: ["ProcessorMonitorCore", "ProcessorMonitorSystem"]),
        .executableTarget(name: "ProcessorMonitor", dependencies: ["ProcessorMonitorUI"]),
        .executableTarget(name: "ProcessorMonitorHelper", dependencies: ["ProcessorMonitorSystem"]),
        // Fakes shared by the test targets. Lives under Tests/, so the coverage gate ignores it.
        .target(name: "TestSupport", dependencies: ["ProcessorMonitorCore"], path: "Tests/TestSupport"),
        .testTarget(name: "ProcessorMonitorCoreTests", dependencies: ["ProcessorMonitorCore", "TestSupport"]),
        .testTarget(name: "ProcessorMonitorSystemTests", dependencies: ["ProcessorMonitorSystem", "TestSupport"]),
        .testTarget(name: "ProcessorMonitorUITests", dependencies: ["ProcessorMonitorUI", "TestSupport"]),
    ]
)
