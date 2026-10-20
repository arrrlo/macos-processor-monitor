import Foundation
import ProcessorMonitorCore

/// Scripted hardware readings and a manually completed process provider.
public final class FakeSources: @unchecked Sendable {
    public var ticks: [CPUTicksSample?] = []
    public var temperatures: [TemperatureSummary?] = []
    public var gpuLoads: [GPULoad?] = []
    public private(set) var tickReads = 0
    public private(set) var temperatureReads = 0
    public private(set) var gpuLoadReads = 0
    public let processes = FakeTopProcesses()

    public init() {}

    /// One core whose busy ticks grow by `busy` out of 100 per sample.
    public static func ticks(busy: [UInt32]) -> [CPUTicksSample?] {
        var user: UInt32 = 0
        var idle: UInt32 = 0
        return [CPUTicksSample(cores: [CoreTicks(user: 0, system: 0, idle: 0, nice: 0)])] + busy.map { busy in
            user += busy
            idle += 100 - busy
            return CPUTicksSample(cores: [CoreTicks(user: user, system: 0, idle: idle, nice: 0)])
        }
    }

    public func readTicks() -> CPUTicksSample? {
        defer { tickReads += 1 }
        return tickReads < ticks.count ? ticks[tickReads] : ticks.last ?? nil
    }

    public func readTemperature() -> TemperatureSummary? {
        defer { temperatureReads += 1 }
        return temperatureReads < temperatures.count ? temperatures[temperatureReads] : temperatures.last ?? nil
    }

    public func readGPULoad() -> GPULoad? {
        defer { gpuLoadReads += 1 }
        return gpuLoadReads < gpuLoads.count ? gpuLoads[gpuLoadReads] : gpuLoads.last ?? nil
    }
}

public final class FakeTopProcesses: TopProcessesProviding, @unchecked Sendable {
    public private(set) var requests: [Int] = []
    private var completions: [@Sendable (TopProcessesResult) -> Void] = []

    public init() {}

    public func topProcesses(limit: Int, completion: @escaping @Sendable (TopProcessesResult) -> Void) {
        requests.append(limit)
        completions.append(completion)
    }

    public func complete(with result: TopProcessesResult) {
        completions.removeFirst()(result)
    }
}
