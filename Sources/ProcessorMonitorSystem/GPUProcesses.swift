import Darwin
import Dispatch
import Foundation
import IOKit
import ProcessorMonitorCore

/// Reads every process's accumulated GPU time from the graphics driver's user clients: each client
/// under `AGXAccelerator` (service plane) names the process that opened it and counts the
/// nanoseconds its queues ran on the GPU. The registry is readable without root, for every user's
/// processes. One snapshot walks about 70 clients in about 1 ms.
public struct GPUProcessTableReader: Sendable {
    /// The registry calls, so tests can stand in for a GPU a VM does not have and check that every
    /// object is released.
    public struct Source: Sendable {
        let service: @Sendable () -> io_service_t
        let children: @Sendable (io_registry_entry_t) -> io_iterator_t
        let next: @Sendable (io_iterator_t) -> io_object_t
        let property: @Sendable (io_registry_entry_t, String) -> Any?
        let release: @Sendable (io_object_t) -> Void
        let now: @Sendable () -> UInt64

        public static let live = Source(
            service: GPUReader.Source.live.service,
            children: { entry in
                var iterator: io_iterator_t = 0
                IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator)
                return iterator
            },
            next: RegistryAccess.live.next,
            property: GPUReader.Source.live.property,
            release: RegistryAccess.live.release,
            now: { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
        )
    }

    private let source: Source

    public init(source: Source = .live) {
        self.source = source
    }

    /// One sample per process, its GPU time in nanoseconds in `cpuTime`. A process can hold several
    /// clients, which are added up. `startTime` is 0: a PID reused within the sampler's 5 s baseline
    /// is too unlikely to matter.
    public func snapshot() -> ProcessSnapshot {
        let service = source.service()
        defer { source.release(service) }
        let clients = source.children(service)
        defer { source.release(clients) }
        var processes: [Int32: (name: String, time: UInt64)] = [:]
        while case let client = source.next(clients), client != 0 {
            defer { source.release(client) }
            let usage = GPUClientParser.usage(
                creator: source.property(client, "IOUserClientCreator"),
                appUsage: source.property(client, "AppUsage")
            )
            if let usage {
                processes[usage.pid] = (usage.name, (processes[usage.pid]?.time ?? 0) + usage.time)
            }
        }
        return ProcessSnapshot(timestamp: source.now(), processes: processes.map { pid, process in
            ProcessSample(pid: pid, startTime: 0, name: process.name, cpuTime: process.time)
        })
    }
}

/// Reads one GPU client's properties.
enum GPUClientParser {
    /// `IOUserClientCreator` reads "pid 405, WindowServer".
    static func process(_ creator: String) -> (pid: Int32, name: String)? {
        let parts = creator.split(separator: ", ", maxSplits: 1)
        guard parts.count == 2, parts[0].hasPrefix("pid "), let pid = Int32(parts[0].dropFirst(4)) else { return nil }
        return (pid, String(parts[1]))
    }

    /// The creating process and the GPU time of all its queues (`AppUsage`), in nanoseconds.
    static func usage(creator: Any?, appUsage: Any?) -> (pid: Int32, name: String, time: UInt64)? {
        guard let creator = creator as? String, let queues = appUsage as? [[String: Any]], let process = process(creator) else { return nil }
        let time = queues.reduce(UInt64(0)) { total, queue in
            total + ((queue["accumulatedGPUTime"] as? NSNumber)?.uint64Value ?? 0)
        }
        return (process.pid, process.name, time)
    }
}

extension ProcessUsageSampler {
    /// Samples GPU time per process. It is already in nanoseconds, hence the 1:1 timebase; the
    /// windows match the CPU sampler's (250 ms first window, baselines reused for up to 5 s).
    public static func gpu(reader: GPUProcessTableReader = GPUProcessTableReader()) -> ProcessUsageSampler {
        ProcessUsageSampler(
            timebase: Timebase(numer: 1, denom: 1),
            minimumWindow: 250_000_000,
            maximumBaselineAge: 5_000_000_000,
            snapshot: reader.snapshot,
            sleep: pause
        )
    }
}

/// The processes using the GPU most, measured in-process: no helper is needed because the
/// registry is readable by everyone. `cpuPercent` holds each process's share of the GPU's time.
public final class GPUProcessesService: TopProcessesProviding {
    private let sampler: ProcessUsageSampler
    private let executablePath: @Sendable (Int32) -> String?
    private let queue = DispatchQueue(label: "io.github.arrrlo.macos-processor-monitor.gpu-processes", qos: .utility)

    public init(sampler: ProcessUsageSampler, executablePath: @escaping @Sendable (Int32) -> String?) {
        self.sampler = sampler
        self.executablePath = executablePath
    }

    public static func live() -> GPUProcessesService {
        GPUProcessesService(sampler: .gpu(), executablePath: ProcessNames.executablePath)
    }

    /// Processes that did not use the GPU in the window are left out, so an idle GPU lists nothing.
    public func topProcesses(limit: Int, completion: @escaping @Sendable (TopProcessesResult) -> Void) {
        let sampler = sampler
        let executablePath = executablePath
        queue.async {
            let busy = sampler.top(limit: limit).filter { $0.cpuPercent > 0 }
            completion(TopProcessesResult(processes: ProcessNames.refine(busy, executablePath: executablePath), scope: .allProcesses))
        }
    }
}
