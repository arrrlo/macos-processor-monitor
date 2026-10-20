import Foundation

public enum MetricFormatter {
    static let placeholder = "—"

    /// Whole percent of a 0...1 share.
    public static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return placeholder }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    public static func temperature(_ celsius: Double?) -> String {
        guard let celsius else { return placeholder }
        return "\(Int(celsius.rounded()))°C"
    }

    /// Percent of one core: one decimal below 100, whole numbers above.
    public static func processPercent(_ percent: Double) -> String {
        let tenths = (percent * 10).rounded() / 10
        guard tenths < 100 else { return "\(Int(percent.rounded()))%" }
        return String(format: "%.1f%%", tenths)
    }

    /// The menu bar text: processor, then GPU, e.g. "23%  49°C   GPU 5%".
    public static func statusTitle(_ snapshot: MonitorSnapshot) -> String {
        "\(percent(snapshot.load?.overall.total))  \(temperature(snapshot.temperature?.average))   GPU \(percent(snapshot.gpuLoad?.device))"
    }
}

/// The text of every dynamic menu row for a snapshot.
public struct MenuText: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let title: String
        public let value: String

        public init(title: String, value: String) {
            self.title = title
            self.value = value
        }
    }

    public struct ProcessRow: Equatable, Sendable {
        public let pid: Int32
        public let row: Row

        public init(pid: Int32, row: Row) {
            self.pid = pid
            self.row = row
        }
    }

    public let load: Row
    public let user: Row
    public let system: Row
    public let idle: Row
    public let temperature: Row
    public let clusters: [Row]
    public let gpuLoad: Row
    public let processHeader: String
    public let processes: [ProcessRow]

    /// - Parameter clusterNames: the topology's clusters, so their rows exist before the first reading.
    public init(_ snapshot: MonitorSnapshot, clusterNames: [String]) {
        let overall = snapshot.load?.overall
        load = Row(title: "Processor load", value: MetricFormatter.percent(overall?.total))
        user = Row(title: "User", value: MetricFormatter.percent(overall?.user))
        system = Row(title: "System", value: MetricFormatter.percent(overall?.system))
        idle = Row(title: "Idle", value: MetricFormatter.percent(overall?.idle))
        temperature = Row(title: "Temperature", value: Self.temperatureValue(snapshot.temperature))
        clusters = clusterNames.map { name in
            Row(title: "\(name) cores", value: MetricFormatter.percent(snapshot.clusters.first { $0.name == name }?.average))
        }
        gpuLoad = Row(title: "GPU load", value: MetricFormatter.percent(snapshot.gpuLoad?.device))
        processHeader = Self.processHeader(snapshot.topProcesses?.scope)
        processes = (snapshot.topProcesses?.processes ?? []).map {
            ProcessRow(pid: $0.pid, row: Row(title: $0.name, value: MetricFormatter.processPercent($0.cpuPercent)))
        }
    }

    private static func temperatureValue(_ summary: TemperatureSummary?) -> String {
        guard let summary else { return "Unavailable" }
        return "\(MetricFormatter.temperature(summary.average)) (max \(MetricFormatter.temperature(summary.maximum)))"
    }

    private static func processHeader(_ scope: ProcessScope?) -> String {
        switch scope {
        case nil: "Top processes — measuring…"
        case .currentUser: "Top processes (your processes only)"
        case .allProcesses: "Top processes"
        }
    }
}

public enum RefreshInterval: Double, CaseIterable, Sendable {
    case one = 1
    case two = 2
    case five = 5

    public static let standard = RefreshInterval.two

    public init?(seconds: Double) {
        self.init(rawValue: seconds)
    }

    public var seconds: Double { rawValue }

    public var title: String {
        self == .one ? "1 second" : "\(Int(rawValue)) seconds"
    }
}

/// Reads `launchctl print-disabled gui/<uid>` output: `"label" => disabled` (or `=> true` on older systems).
public enum LaunchctlDisabledParser {
    public static func isDisabled(label: String, in output: String) -> Bool {
        let prefix = "\"\(label)\" =>"
        return output.split(separator: "\n").contains { line in
            let entry = line.trimmingCharacters(in: .whitespaces)
            guard entry.hasPrefix(prefix) else { return false }
            let state = entry.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return state == "disabled" || state == "true"
        }
    }
}

/// Process sampling is wanted while the menu is open or the dashboard is visible.
public final class ProcessDemand {
    private let onChange: (Bool) -> Void
    public private(set) var isActive = false

    public var menuOpen = false {
        didSet { update() }
    }

    public var dashboardVisible = false {
        didSet { update() }
    }

    public init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    private func update() {
        let active = menuOpen || dashboardVisible
        guard active != isActive else { return }
        isActive = active
        onChange(active)
    }
}

/// Decides when the menu bar text is worth redrawing. On macOS 26 every status item change costs
/// about 7–14 ms of AppKit work (a snapshot redrawn into each display's menu bar), which dominates
/// the app's running cost. Real movement shows at once; jitter waits until the title is 10 s old.
public struct StatusTitleThrottle: Sendable {
    public static let loadStep = 0.03
    public static let temperatureStep = 2.0
    /// GPU load flickers between 0% and about 25% from one tick to the next while windows are
    /// composited; at the processor's 3 points the title would redraw almost every tick.
    public static let gpuLoadStep = 0.1
    public static let maximumAge = 10.0

    /// The numbers behind the title, kept so the next reading can be compared with them.
    private struct Reading {
        let load: Double?
        let temperature: Double?
        let gpuLoad: Double?

        init(_ snapshot: MonitorSnapshot) {
            load = snapshot.load?.overall.total
            temperature = snapshot.temperature?.average
            gpuLoad = snapshot.gpuLoad?.device
        }

        func moved(from old: Reading) -> Bool {
            StatusTitleThrottle.moved(old.load, load, by: StatusTitleThrottle.loadStep)
                || StatusTitleThrottle.moved(old.temperature, temperature, by: StatusTitleThrottle.temperatureStep)
                || StatusTitleThrottle.moved(old.gpuLoad, gpuLoad, by: StatusTitleThrottle.gpuLoadStep)
        }
    }

    private var shown: (reading: Reading, time: Double)?

    public init() {}

    /// Records the reading as shown when it returns true.
    public mutating func shouldShow(_ snapshot: MonitorSnapshot, at time: Double) -> Bool {
        let reading = Reading(snapshot)
        guard let last = shown, time - last.time < Self.maximumAge, !reading.moved(from: last.reading) else {
            shown = (reading, time)
            return true
        }
        return false
    }

    private static func moved(_ old: Double?, _ new: Double?, by step: Double) -> Bool {
        switch (old, new) {
        case let (old?, new?): abs(new - old) >= step
        case (nil, nil): false
        default: true
        }
    }
}
