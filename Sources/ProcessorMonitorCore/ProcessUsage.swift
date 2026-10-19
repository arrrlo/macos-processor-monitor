import Foundation
import os

/// Converts Mach absolute time units to nanoseconds (`mach_timebase_info`; 125/3 on Apple Silicon).
public struct Timebase: Equatable, Sendable {
    public let numer: UInt32
    public let denom: UInt32

    public init(numer: UInt32, denom: UInt32) {
        self.numer = numer
        self.denom = denom
    }

    public func nanoseconds(_ ticks: UInt64) -> Double {
        Double(ticks) * Double(numer) / Double(denom)
    }
}

/// One process in a process-table snapshot.
public struct ProcessSample: Equatable, Sendable {
    public let pid: Int32
    /// Process start time in microseconds; with `pid` it identifies a process across PID reuse.
    public let startTime: UInt64
    public let name: String
    /// Total user + system CPU time, in Mach absolute time units.
    public let cpuTime: UInt64

    public init(pid: Int32, startTime: UInt64, name: String, cpuTime: UInt64) {
        self.pid = pid
        self.startTime = startTime
        self.name = name
        self.cpuTime = cpuTime
    }
}

public struct ProcessSnapshot: Equatable, Sendable {
    /// Monotonic nanoseconds.
    public let timestamp: UInt64
    public let processes: [ProcessSample]

    public init(timestamp: UInt64, processes: [ProcessSample]) {
        self.timestamp = timestamp
        self.processes = processes
    }
}

/// CPU usage of one process, in percent of one core (like Activity Monitor; can exceed 100).
public struct ProcessUsage: Equatable, Sendable, Codable {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double

    public init(pid: Int32, name: String, cpuPercent: Double) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
    }
}

public enum ProcessCPUCalculator {
    /// Usage of every process present in both snapshots. New processes appear from the next interval on.
    public static func usage(previous: ProcessSnapshot, current: ProcessSnapshot, timebase: Timebase) -> [ProcessUsage] {
        guard current.timestamp > previous.timestamp else { return [] }
        let elapsed = Double(current.timestamp - previous.timestamp)
        var before: [ProcessKey: UInt64] = [:]
        for process in previous.processes {
            before[ProcessKey(process)] = process.cpuTime
        }
        return current.processes.compactMap { process in
            guard let earlier = before[ProcessKey(process)] else { return nil }
            // A counter that went backwards (should not happen) counts as no usage.
            let used = max(process.cpuTime, earlier) - earlier
            return ProcessUsage(pid: process.pid, name: process.name, cpuPercent: timebase.nanoseconds(used) / elapsed * 100)
        }
    }
}

private struct ProcessKey: Hashable {
    let pid: Int32
    let startTime: UInt64

    init(_ process: ProcessSample) {
        pid = process.pid
        startTime = process.startTime
    }
}

public enum TopProcesses {
    public static func select(_ usage: [ProcessUsage], limit: Int) -> [ProcessUsage] {
        // mutation:disable-next-line PIDs are unique, so two entries never compare equal and `<=` sorts identically
        let ranked = usage.sorted { ($1.cpuPercent, $0.pid) < ($0.cpuPercent, $1.pid) }
        return Array(ranked.prefix(max(limit, 0)))
    }
}

/// Answers "top N right now" with as little sampling as possible: it measures against the
/// snapshot taken by the previous request when that is recent, and otherwise takes a short
/// measurement window. Safe to call from any thread; calls are serialized.
public final class ProcessUsageSampler: Sendable {
    private let timebase: Timebase
    private let minimumWindow: UInt64
    private let maximumBaselineAge: UInt64
    private let snapshot: @Sendable () -> ProcessSnapshot
    private let sleep: @Sendable (UInt64) -> Void
    private let baseline = OSAllocatedUnfairLock<ProcessSnapshot?>(initialState: nil)

    /// - Parameters:
    ///   - minimumWindow: shortest measurement interval, ns.
    ///   - maximumBaselineAge: older baselines are discarded, ns.
    public init(
        timebase: Timebase,
        minimumWindow: UInt64,
        maximumBaselineAge: UInt64,
        snapshot: @escaping @Sendable () -> ProcessSnapshot,
        sleep: @escaping @Sendable (UInt64) -> Void
    ) {
        self.timebase = timebase
        self.minimumWindow = minimumWindow
        self.maximumBaselineAge = maximumBaselineAge
        self.snapshot = snapshot
        self.sleep = sleep
    }

    public func top(limit: Int) -> [ProcessUsage] {
        baseline.withLock { baseline in
            var current = snapshot()
            var previous = current
            if let stored = baseline, current.timestamp - stored.timestamp <= maximumBaselineAge {
                previous = stored
            }
            let elapsed = current.timestamp - previous.timestamp
            if elapsed < minimumWindow {
                sleep(minimumWindow - elapsed)
                current = snapshot()
            }
            baseline = current
            return TopProcesses.select(ProcessCPUCalculator.usage(previous: previous, current: current, timebase: timebase), limit: limit)
        }
    }
}
