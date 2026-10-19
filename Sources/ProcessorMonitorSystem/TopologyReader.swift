import ProcessorMonitorCore

/// Builds the core cluster layout from `hw.perflevel*` sysctls and the device tree.
public struct TopologyReader: Sendable {
    public struct Source: Sendable {
        let int: @Sendable (String) -> Int?
        let string: @Sendable (String) -> String?
        let registryCPUs: @Sendable () -> [CPUDescriptor]

        public init(
            int: @escaping @Sendable (String) -> Int?,
            string: @escaping @Sendable (String) -> String?,
            registryCPUs: @escaping @Sendable () -> [CPUDescriptor]
        ) {
            self.int = int
            self.string = string
            self.registryCPUs = registryCPUs
        }

        public static let live = Source(int: Sysctl.int, string: Sysctl.string, registryCPUs: IORegistryCPUs.read)
    }

    private let source: Source

    public init(source: Source = .live) {
        self.source = source
    }

    public func read(coreCount: Int) -> CPUTopology {
        let levelCount = source.int("hw.nperflevels") ?? 0
        let levels = (0..<max(levelCount, 0)).compactMap { level -> PerformanceLevel? in
            guard let name = source.string("hw.perflevel\(level).name"),
                  let cpus = source.int("hw.perflevel\(level).logicalcpu") else { return nil }
            return PerformanceLevel(name: name, logicalCPUCount: cpus)
        }
        return CPUTopology.build(coreCount: coreCount, levels: levels, cpus: source.registryCPUs())
    }
}
