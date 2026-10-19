/// Cumulative scheduler ticks of one logical core, as reported by `host_processor_info`.
/// The kernel counters are 32-bit and wrap around.
public struct CoreTicks: Equatable, Sendable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// Tick counters for every logical core, indexed by logical CPU id.
public struct CPUTicksSample: Equatable, Sendable {
    public let cores: [CoreTicks]

    public init(cores: [CoreTicks]) {
        self.cores = cores
    }
}

/// Share of elapsed time spent in user code (including nice), the kernel, and idle. Sums to 1.
public struct LoadBreakdown: Equatable, Sendable {
    public let user: Double
    public let system: Double
    public let idle: Double

    public init(user: Double, system: Double, idle: Double) {
        self.user = user
        self.system = system
        self.idle = idle
    }

    public static let idle = LoadBreakdown(user: 0, system: 0, idle: 1)

    /// Busy share (user + system), 0...1.
    public var total: Double { user + system }
}

public struct CPULoad: Equatable, Sendable {
    public let overall: LoadBreakdown
    /// Per logical core, same order as `CPUTicksSample.cores`.
    public let cores: [LoadBreakdown]

    public init(overall: LoadBreakdown, cores: [LoadBreakdown]) {
        self.overall = overall
        self.cores = cores
    }
}

public enum LoadCalculator {
    /// Load between two samples; `nil` when the samples don't describe the same set of cores.
    public static func load(from previous: CPUTicksSample, to current: CPUTicksSample) -> CPULoad? {
        guard !current.cores.isEmpty, previous.cores.count == current.cores.count else { return nil }
        let deltas = zip(previous.cores, current.cores).map { TickDelta(previous: $0, current: $1) }
        let overall = deltas.reduce(TickDelta.zero, +)
        return CPULoad(overall: overall.breakdown, cores: deltas.map(\.breakdown))
    }
}

private struct TickDelta {
    let user: UInt64
    let system: UInt64
    let idle: UInt64

    static let zero = TickDelta(user: 0, system: 0, idle: 0)

    init(user: UInt64, system: UInt64, idle: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
    }

    init(previous: CoreTicks, current: CoreTicks) {
        self.init(
            user: UInt64(current.user &- previous.user) + UInt64(current.nice &- previous.nice),
            system: UInt64(current.system &- previous.system),
            idle: UInt64(current.idle &- previous.idle)
        )
    }

    static func + (lhs: TickDelta, rhs: TickDelta) -> TickDelta {
        TickDelta(user: lhs.user + rhs.user, system: lhs.system + rhs.system, idle: lhs.idle + rhs.idle)
    }

    var breakdown: LoadBreakdown {
        let total = user + system + idle
        guard total > 0 else { return .idle }
        let elapsed = Double(total)
        return LoadBreakdown(user: Double(user) / elapsed, system: Double(system) / elapsed, idle: Double(idle) / elapsed)
    }
}
