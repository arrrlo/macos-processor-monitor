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
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PM_SCREENSHOT_DIR"] ?? "/tmp")

        func liveSnapshot() async -> (MonitorSnapshot, CPUTopology) {
            let ticks = CPUTicksReader()
            let topology = TopologyReader().read(coreCount: ProcessInfo.processInfo.processorCount)
            let first = ticks.read()!
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let load = LoadCalculator.load(from: first, to: ticks.read()!)!
            let processes = await withCheckedContinuation { continuation in
                TopProcessesService.live().topProcesses(limit: 10) { continuation.resume(returning: $0) }
            }
            let snapshot = MonitorSnapshot(
                load: load,
                clusters: topology.clusterLoads(load),
                temperature: CPUTemperatureReader.live().read(),
                topProcesses: processes
            )
            return (snapshot, topology)
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
            let (snapshot, topology) = await liveSnapshot()
            let apps = ProcessIdentityResolver.live().resolve(snapshot.topProcesses?.processes ?? [])
            let model = DashboardModel(snapshot: snapshot, clusterNames: topology.clusters.map(\.name), apps: apps)
            for (name, appearance) in [("dashboard-dark.png", NSAppearance.Name.darkAqua), ("dashboard-light.png", .aqua)] {
                let view = NSHostingView(rootView: DashboardView(model: model).background(Color(nsColor: .windowBackgroundColor)))
                view.frame = NSRect(origin: .zero, size: view.fittingSize)
                try write(view, to: name, appearance: appearance)
            }
        }

        @Test func statusItem() async throws {
            let (snapshot, _) = await liveSnapshot()
            let controller = StatusItemController(statusBar: NSStatusBar(), menu: NSMenu())
            controller.update(title: MetricFormatter.statusTitle(snapshot))
            let button = try #require(controller.item.button)
            try write(button, to: "status-item.png", appearance: .darkAqua)
            controller.remove()
        }
    }
}
