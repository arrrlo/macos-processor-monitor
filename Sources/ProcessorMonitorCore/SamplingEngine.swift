import Foundation

/// Everything the UI shows, published as one value.
public struct MonitorSnapshot: Equatable, Sendable {
    public var load: CPULoad?
    public var clusters: [ClusterLoad]
    public var temperature: TemperatureSummary?
    public var topProcesses: TopProcessesResult?

    public init(load: CPULoad?, clusters: [ClusterLoad], temperature: TemperatureSummary?, topProcesses: TopProcessesResult?) {
        self.load = load
        self.clusters = clusters
        self.temperature = temperature
        self.topProcesses = topProcesses
    }

    public static let empty = MonitorSnapshot(load: nil, clusters: [], temperature: nil, topProcesses: nil)
}

/// The app's only periodic work. Each tick costs one `host_processor_info` call; temperature is
/// read at most every `temperatureInterval` seconds; the process table is only measured while
/// someone looks at it (menu open or dashboard visible), with at most one request in flight.
public final class SamplingEngine: @unchecked Sendable {
    public struct Sources: Sendable {
        let cpuTicks: @Sendable () -> CPUTicksSample?
        let temperature: @Sendable () -> TemperatureSummary?
        let topProcesses: any TopProcessesProviding
        let topology: CPUTopology

        public init(
            cpuTicks: @escaping @Sendable () -> CPUTicksSample?,
            temperature: @escaping @Sendable () -> TemperatureSummary?,
            topProcesses: any TopProcessesProviding,
            topology: CPUTopology
        ) {
            self.cpuTicks = cpuTicks
            self.temperature = temperature
            self.topProcesses = topProcesses
            self.topology = topology
        }
    }

    private let sources: Sources
    private let scheduler: any Scheduling
    private let temperatureInterval: Double
    private let processLimit: Int
    private let publish: @Sendable (MonitorSnapshot) -> Void
    private let lock = NSLock()

    private var currentInterval: Double
    private var timer: (any Cancellable)?
    private var previousTicks: CPUTicksSample?
    private var secondsSinceTemperature: Double = 0
    private var snapshot = MonitorSnapshot.empty
    private var processDemand = false
    private var processRequestInFlight = false

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
        currentInterval = interval
    }

    public var interval: Double { locked { currentInterval } }
    public var isRunning: Bool { locked { timer != nil } }

    /// Takes a fresh baseline (so a pause is not averaged into the next reading) and starts ticking.
    public func start() {
        let started = locked { () -> Bool in
            guard timer == nil else { return false }
            previousTicks = sources.cpuTicks()
            timer = scheduleTicks()
            return true
        }
        guard started else { return }
        readTemperature()
        requestProcessesIfNeeded()
        publishSnapshot()
    }

    public func stop() {
        locked {
            timer?.cancel()
            timer = nil
        }
    }

    public func setInterval(_ seconds: Double) {
        locked {
            currentInterval = seconds
            guard let running = timer else { return }
            running.cancel()
            timer = scheduleTicks()
        }
    }

    public func setProcessDemand(_ active: Bool) {
        locked { processDemand = active }
        requestProcessesIfNeeded()
    }

    // MARK: - Ticking

    /// Call with the lock held.
    private func scheduleTicks() -> any Cancellable {
        scheduler.scheduleRepeating(every: currentInterval) { [weak self] in self?.tick() }
    }

    private func tick() {
        updateLoad(with: sources.cpuTicks())
        let temperatureDue = locked { () -> Bool in
            secondsSinceTemperature += currentInterval
            return secondsSinceTemperature >= temperatureInterval
        }
        if temperatureDue {
            readTemperature()
        }
        requestProcessesIfNeeded()
        publishSnapshot()
    }

    private func updateLoad(with ticks: CPUTicksSample?) {
        locked {
            guard let ticks else { return }
            if let previous = previousTicks, let load = LoadCalculator.load(from: previous, to: ticks) {
                snapshot.load = load
                snapshot.clusters = sources.topology.clusterLoads(load)
            }
            previousTicks = ticks
        }
    }

    private func readTemperature() {
        let temperature = sources.temperature()
        locked {
            snapshot.temperature = temperature
            secondsSinceTemperature = 0
        }
    }

    private func requestProcessesIfNeeded() {
        let shouldRequest = locked { () -> Bool in
            guard processDemand, !processRequestInFlight else { return false }
            processRequestInFlight = true
            return true
        }
        guard shouldRequest else { return }
        sources.topProcesses.topProcesses(limit: processLimit) { [weak self] result in
            self?.receive(result)
        }
    }

    private func receive(_ result: TopProcessesResult) {
        locked {
            processRequestInFlight = false
            snapshot.topProcesses = result
        }
        publishSnapshot()
    }

    private func publishSnapshot() {
        publish(locked { snapshot })
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
