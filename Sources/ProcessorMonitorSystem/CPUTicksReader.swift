import Darwin
import ProcessorMonitorCore

/// Per-core tick counters via `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`.
public struct CPUTicksReader: Sendable {
    /// The raw kernel calls, replaceable in tests.
    public struct Source: Sendable {
        public typealias QueryResult = (status: kern_return_t, cpuCount: natural_t, info: processor_info_array_t?, infoCount: mach_msg_type_number_t)

        let query: @Sendable () -> QueryResult
        let deallocate: @Sendable (_ address: vm_address_t, _ size: vm_size_t) -> Void

        public init(
            query: @escaping @Sendable () -> QueryResult,
            deallocate: @escaping @Sendable (_ address: vm_address_t, _ size: vm_size_t) -> Void
        ) {
            self.query = query
            self.deallocate = deallocate
        }

        /// `mach_host_self()` adds a send right on every call, so it is fetched once.
        private static let host = mach_host_self()

        public static let live = Source(
            query: {
                var cpuCount: natural_t = 0
                var info: processor_info_array_t?
                var infoCount: mach_msg_type_number_t = 0
                let status = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
                return (status, cpuCount, info, infoCount)
            },
            deallocate: { address, size in
                vm_deallocate(mach_task_self_, address, size)
            }
        )
    }

    private let source: Source

    public init(source: Source = .live) {
        self.source = source
    }

    public func read() -> CPUTicksSample? {
        let result = source.query()
        guard result.status == KERN_SUCCESS, let info = result.info else { return nil }
        // The kernel allocates the array in our address space; it must be returned.
        defer {
            source.deallocate(
                vm_address_t(bitPattern: info),
                vm_size_t(result.infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }
        let stride = Int(CPU_STATE_MAX)
        let cores = (0..<Int(result.cpuCount)).map { cpu in
            let base = info + cpu * stride
            return CoreTicks(
                user: UInt32(bitPattern: base[Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: base[Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: base[Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: base[Int(CPU_STATE_NICE)])
            )
        }
        return CPUTicksSample(cores: cores)
    }
}
