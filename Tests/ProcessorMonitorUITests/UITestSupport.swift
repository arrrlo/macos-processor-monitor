import AppKit
import Testing
import TestSupport
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorUI

/// Every AppKit suite nests in here so they run one at a time on the main actor.
@MainActor @Suite(.serialized, .timeLimit(.minutes(1))) struct AppKitTests {}

final class InMemorySettings: SettingsStore {
    var refreshInterval: RefreshInterval = .standard
}

final class FakeLoginItem: LoginItemControlling {
    var isAvailable = true
    var isEnabled = true
    private(set) var changes: [Bool] = []

    func setEnabled(_ enabled: Bool) {
        changes.append(enabled)
        isEnabled = enabled
    }
}

final class ActionLog {
    var entries: [String] = []
}

extension MonitorSnapshot {
    static let sample = MonitorSnapshot(
        load: CPULoad(overall: LoadBreakdown(user: 0.15, system: 0.08, idle: 0.77), cores: [
            LoadBreakdown(user: 0.5, system: 0.1, idle: 0.4),
            LoadBreakdown(user: 0.05, system: 0.05, idle: 0.9),
        ]),
        clusters: [
            ClusterLoad(name: "Super", average: 0.6, cores: [CoreLoad(index: 1, load: 0.6)]),
            ClusterLoad(name: "Performance", average: 0.1, cores: [CoreLoad(index: 0, load: 0.1)]),
        ],
        temperature: TemperatureSummary(average: 53.2, maximum: 58.9, sensorCount: 42),
        topProcesses: TopProcessesResult(
            processes: [
                ProcessUsage(pid: 100, name: "WindowServer", cpuPercent: 12.34),
                ProcessUsage(pid: 200, name: "Finder", cpuPercent: 3.5),
            ],
            scope: .allProcesses
        )
    )
}

let testIcon = NSImage(size: NSSize(width: 32, height: 32))

/// Gives main-actor tasks (snapshot delivery) a chance to run.
@MainActor func settle() async {
    for _ in 0..<5 {
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
}
