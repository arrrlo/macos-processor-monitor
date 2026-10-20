import os

/// Everything the UI shows, published as one value.
public struct MonitorSnapshot: Equatable, Sendable {
    public var load: CPULoad?
    public var clusters: [ClusterLoad]
    public var temperature: TemperatureSummary?
    public var topProcesses: TopProcessesResult?
    public var gpuLoad: GPULoad?

    public init(
        load: CPULoad?,
        clusters: [ClusterLoad],
        temperature: TemperatureSummary?,
        topProcesses: TopProcessesResult?,
        gpuLoad: GPULoad? = nil
    ) {
        self.load = load
        self.clusters = clusters
        self.temperature = temperature
        self.topProcesses = topProcesses
        self.gpuLoad = gpuLoad
    }

    public static let empty = MonitorSnapshot(load: nil, clusters: [], temperature: nil, topProcesses: nil)
}

/// The app's only periodic work. Each tick costs one `host_processor_info` call and one copy of the
/// GPU's statistics; temperature is read at most every `temperatureInterval` seconds; the process
/// table is only measured while someone looks at it (menu open or dashboard visible), with at most
/// one request in flight.
public final class SamplingEngine: Sendable {
    public struct Sources: Sendable {
        let cpuTicks: @Sendable () -> CPUTicksSample?
        let temperature: @Sendable () -> TemperatureSummary?
        let gpuLoad: @Sendable () -> GPULoad?
        let topProcesses: any TopProcessesProviding
        let topology: CPUTopology

        public init(
            cpuTicks: @escaping @Sendable () -> CPUTicksSample?,
            temperature: @escaping @Sendable () -> TemperatureSummary?,
            gpuLoad: @escaping @Sendable () -> GPULoad?,
            topProcesses: any TopProcessesProviding,
            topology: CPUTopology
        ) {
            self.cpuTicks = cpuTicks
            self.temperature = temperature
            self.gpuLoad = gpuLoad
            self.topProcesses = topProcesses
            self.topology = topology
        }
    }

    private struct State: Sendable {
        var interval: Double
        var timer: (any Cancellable)?
        var previousTicks: CPUTicksSample?
        var secondsSinceTemperature: Double = 0
        var snapshot = MonitorSnapshot.empty
        var processDemand = false
        var processRequestInFlight = false
    }

    private let sources: Sources
    private let scheduler: any Scheduling
    private let temperatureInterval: Double
    private let processLimit: Int
    private let publish: @Sendable (MonitorSnapshot) -> Void
    private let state: OSAllocatedUnfairLock<State>

    public init(
        sources: Sources,
        scheduler: any Scheduling,
        interval: Double,
        temperatureInterval: Double = 4,
        processLimit: Int = 10,
        publish: @escaping @Sendable (MonitorSnapshot) -> Void
    ) {
        self.sources = sources
        self.scheduler = scheduler
        self.temperatureInterval = temperatureInterval
        self.processLimit = processLimit
        self.publish = publish
        state = OSAllocatedUnfairLock(initialState: State(interval: interval))
    }

    public var interval: Double { state.withLock { $0.interval } }
    public var isRunning: Bool { state.withLock { $0.timer != nil } }

    /// Takes a fresh baseline (so a pause is not averaged into the next reading) and starts ticking.
    public func start() {
        let started = state.withLock { state -> Bool in
            guard state.timer == nil else { return false }
            state.previousTicks = sources.cpuTicks()
            state.timer = scheduleTicks(every: state.interval)
            return true
        }
        guard started else { return }
        readTemperature()
        publishSnapshot()
    }

    public func stop() {
        state.withLock { state in
            state.timer?.cancel()
            state.timer = nil
        }
    }

    public func setInterval(_ seconds: Double) {
        state.withLock { state in
            state.interval = seconds
            guard let running = state.timer else { return }
            running.cancel()
            state.timer = scheduleTicks(every: seconds)
        }
    }

    public func setProcessDemand(_ active: Bool) {
        state.withLock { $0.processDemand = active }
        requestProcessesIfNeeded()
    }

    // MARK: - Ticking

    private func scheduleTicks(every interval: Double) -> any Cancellable {
        scheduler.scheduleRepeating(every: interval) { [weak self] in self?.tick() }
    }

    private func tick() {
        updateLoad(with: sources.cpuTicks(), gpu: sources.gpuLoad())
        let temperatureDue = state.withLock { state -> Bool in
            state.secondsSinceTemperature += state.interval
            return state.secondsSinceTemperature >= temperatureInterval
        }
        if temperatureDue {
            readTemperature()
        }
        requestProcessesIfNeeded()
        publishSnapshot()
    }

    private func updateLoad(with ticks: CPUTicksSample?, gpu: GPULoad?) {
        let topology = sources.topology
        state.withLock { state in
            state.snapshot.gpuLoad = gpu
            guard let ticks else { return }
            if let previous = state.previousTicks, let load = LoadCalculator.load(from: previous, to: ticks) {
                state.snapshot.load = load
                state.snapshot.clusters = topology.clusterLoads(load)
            }
            state.previousTicks = ticks
        }
    }

    private func readTemperature() {
        let temperature = sources.temperature()
        state.withLock { state in
            state.snapshot.temperature = temperature
            state.secondsSinceTemperature = 0
        }
    }

    private func requestProcessesIfNeeded() {
        let shouldRequest = state.withLock { state -> Bool in
            guard state.processDemand, !state.processRequestInFlight else { return false }
            state.processRequestInFlight = true
            return true
        }
        guard shouldRequest else { return }
        sources.topProcesses.topProcesses(limit: processLimit) { [weak self] result in
            self?.receive(result)
        }
    }

    private func receive(_ result: TopProcessesResult) {
        state.withLock { state in
            state.processRequestInFlight = false
            state.snapshot.topProcesses = result
        }
        publishSnapshot()
    }

    private func publishSnapshot() {
        publish(state.withLock { $0.snapshot })
    }
}
