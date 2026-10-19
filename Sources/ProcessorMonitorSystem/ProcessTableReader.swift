import Darwin
import ProcessorMonitorCore

/// Snapshots CPU time of every process this caller may inspect. As a normal user that excludes
/// root-owned processes; the privileged helper runs it as root to see everything.
public struct ProcessTableReader: Sendable {
    public struct Source: Sendable {
        let listPIDs: @Sendable () -> [pid_t]
        let taskInfo: @Sendable (pid_t) -> proc_taskallinfo?
        let now: @Sendable () -> UInt64

        public init(
            listPIDs: @escaping @Sendable () -> [pid_t],
            taskInfo: @escaping @Sendable (pid_t) -> proc_taskallinfo?,
            now: @escaping @Sendable () -> UInt64
        ) {
            self.listPIDs = listPIDs
            self.taskInfo = taskInfo
            self.now = now
        }

        public static let live = Source(
            listPIDs: {
                // Headroom for processes spawned between the two calls.
                let capacity = max(Int(proc_listallpids(nil, 0)), 0) + 64
                var pids = [pid_t](repeating: 0, count: capacity)
                let filled = pids.withUnsafeMutableBufferPointer { buffer in
                    proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
                }
                return Array(pids.prefix(max(Int(filled), 0)))
            },
            taskInfo: { pid in
                var info = proc_taskallinfo()
                let size = Int32(MemoryLayout<proc_taskallinfo>.size)
                return proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, size) == size ? info : nil
            },
            now: { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
        )
    }

    private let source: Source

    public init(source: Source = .live) {
        self.source = source
    }

    public static func liveTimebase() -> Timebase {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Timebase(numer: info.numer, denom: info.denom)
    }

    public func snapshot() -> ProcessSnapshot {
        let processes = source.listPIDs().compactMap { pid in
            source.taskInfo(pid).map { Self.sample(pid: pid, info: $0) }
        }
        return ProcessSnapshot(timestamp: source.now(), processes: processes)
    }

    static func sample(pid: pid_t, info: proc_taskallinfo) -> ProcessSample {
        let longName = string(from: info.pbsd.pbi_name)
        return ProcessSample(
            pid: pid,
            startTime: info.pbsd.pbi_start_tvsec * 1_000_000 + info.pbsd.pbi_start_tvusec,
            name: longName.isEmpty ? string(from: info.pbsd.pbi_comm) : longName,
            cpuTime: info.ptinfo.pti_total_user + info.ptinfo.pti_total_system
        )
    }

    /// C `char[N]` fields arrive as tuples.
    private static func string<T>(from field: T) -> String {
        withUnsafeBytes(of: field) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
