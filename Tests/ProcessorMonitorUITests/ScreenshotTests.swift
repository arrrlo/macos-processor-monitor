import AppKit
import SwiftUI
import Testing
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorSystem
@testable import ProcessorMonitorUI

/// Renders README images from live readings of this Mac: `make screenshots`.
/// Skipped unless PM_SCREENSHOT_DIR is set, so it never runs in the normal suite.
extension AppKitTests {
    @MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["PM_SCREENSHOT_DIR"] != nil))
    struct ScreenshotTests {
        static let interval: UInt64 = 1
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PM_SCREENSHOT_DIR"] ?? "/tmp")

        func liveSnapshot() async -> (MonitorSnapshot, CPUTopology, GPUInfo?) {
            let ticks = CPUTicksReader()
            let topology = TopologyReader().read(coreCount: ProcessInfo.processInfo.processorCount)
            let first = ticks.read()!
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let load = LoadCalculator.load(from: first, to: ticks.read()!)!
            // Kept alive until the reply arrives: releasing the client closes its connection.
            let service = TopProcessesService.live()
            let processes = await withCheckedContinuation { continuation in
                service.topProcesses(limit: 10) { continuation.resume(returning: $0) }
            }
            withExtendedLifetime(service) {}
            // 30 GPU readings 1 s apart, as the app collects them at the 1 s interval (AppKit suites have a
            // one-minute time limit, too short for the default 2 s).
            let gpu = GPUReader()
            var history = GPULoadHistory()
            for _ in 0..<GPULoadHistory.capacity {
                if let reading = gpu.read() {
                    history = history.appending(reading.device)
                }
                try? await Task.sleep(nanoseconds: Self.interval * 1_000_000_000)
            }
            let gpuService = GPUProcessesService.live()
            let gpuProcesses = await withCheckedContinuation { continuation in
                gpuService.topProcesses(limit: 10) { continuation.resume(returning: $0) }
            }
            var snapshot = MonitorSnapshot(
                load: load,
                clusters: topology.clusterLoads(load),
                temperature: CPUTemperatureReader.live().read(),
                topProcesses: processes,
                gpuLoad: gpu.read(),
                gpuTemperature: GPUTemperatureReader.live().read()
            )
            snapshot.gpuHistory = history
            snapshot.topGPUProcesses = gpuProcesses
            return (snapshot, topology, gpu.info())
        }

        func write(_ view: NSView, to name: String, appearance: NSAppearance.Name) throws {
            view.appearance = NSAppearance(named: appearance)
            view.layoutSubtreeIfNeeded()
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent(name))
        }

        @Test func dashboard() async throws {
            let (snapshot, topology, gpu) = await liveSnapshot()
            let apps = ProcessIdentityResolver.live().resolve(snapshot.topProcesses?.processes ?? [])
            let model = DashboardModel(snapshot: snapshot, clusterNames: topology.clusters.map(\.name), apps: apps, gpu: gpu, refreshInterval: Double(Self.interval))
            for (name, appearance) in [("dashboard-dark.png", NSAppearance.Name.darkAqua), ("dashboard-light.png", .aqua)] {
                let view = NSHostingView(rootView: DashboardView(model: model).background(Color(nsColor: .windowBackgroundColor)))
                view.frame = NSRect(origin: .zero, size: view.fittingSize)
                try write(view, to: name, appearance: appearance)
            }
        }
    }
}
