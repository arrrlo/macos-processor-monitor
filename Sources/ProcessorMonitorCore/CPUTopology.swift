/// One `hw.perflevelN` entry; perflevel 0 is the fastest core type.
public struct PerformanceLevel: Equatable, Sendable {
    public let name: String
    public let logicalCPUCount: Int

    public init(name: String, logicalCPUCount: Int) {
        self.name = name
        self.logicalCPUCount = logicalCPUCount
    }
}

/// A core as described by `IODeviceTree:/cpus/cpuN`.
public struct CPUDescriptor: Equatable, Sendable {
    public let logicalID: Int
    /// "P" (performance), "M" (mid, e.g. M5 "Performance" next to "Super"), "E" (efficiency).
    public let clusterType: String

    public init(logicalID: Int, clusterType: String) {
        self.logicalID = logicalID
        self.clusterType = clusterType
    }
}

public struct CPUCluster: Equatable, Sendable {
    public let name: String
    /// Logical CPU indices into `CPUTicksSample.cores`, ascending.
    public let coreIndices: [Int]

    public init(name: String, coreIndices: [Int]) {
        self.name = name
        self.coreIndices = coreIndices
    }
}

/// Core clusters, fastest first. CPU index order does not follow perflevel order
/// (on M5 Max cpu0–11 are "Performance" and cpu12–17 "Super"), so the registry decides.
public struct CPUTopology: Equatable, Sendable {
    public let clusters: [CPUCluster]

    public init(clusters: [CPUCluster]) {
        self.clusters = clusters
    }

    public var coreCount: Int { clusters.reduce(0) { $0 + $1.coreIndices.count } }

    public static func build(coreCount: Int, levels: [PerformanceLevel], cpus: [CPUDescriptor]) -> CPUTopology {
        let levels = levels.filter { $0.logicalCPUCount > 0 }
        guard coreCount > 0 else { return CPUTopology(clusters: []) }
        guard !levels.isEmpty, levels.reduce(0, { $0 + $1.logicalCPUCount }) == coreCount else {
            return CPUTopology(clusters: [CPUCluster(name: "CPU", coreIndices: Array(0..<coreCount))])
        }
        let groups = registryGroups(coreCount: coreCount, levels: levels, cpus: cpus) ?? highestIndicesFirst(levels)
        return CPUTopology(clusters: zip(levels, groups).map { CPUCluster(name: $0.name, coreIndices: $1) })
    }

    /// Groups the registry's CPUs by cluster type, fastest type first; `nil` if they don't line up with the perflevels.
    private static func registryGroups(coreCount: Int, levels: [PerformanceLevel], cpus: [CPUDescriptor]) -> [[Int]]? {
        guard Set(cpus.map(\.logicalID)) == Set(0..<coreCount) else { return nil }
        let groups = Dictionary(grouping: cpus, by: \.clusterType)
            .sorted { fasterClusterType($0.key, $1.key) }
            .map { $0.value.map(\.logicalID).sorted() }
        guard groups.map(\.count) == levels.map(\.logicalCPUCount) else { return nil }
        return groups
    }

    private static func fasterClusterType(_ lhs: String, _ rhs: String) -> Bool {
        let known = ["P", "M", "E"]
        let lhsRank = known.firstIndex(of: lhs) ?? known.count
        let rhsRank = known.firstIndex(of: rhs) ?? known.count
        return (lhsRank, lhs) < (rhsRank, rhs)
    }

    /// Apple Silicon lists slower cores first, so perflevel 0 takes the highest indices.
    private static func highestIndicesFirst(_ levels: [PerformanceLevel]) -> [[Int]] {
        var upperBound = levels.reduce(0) { $0 + $1.logicalCPUCount }
        return levels.map { level in
            let lowerBound = upperBound - level.logicalCPUCount
            defer { upperBound = lowerBound }
            return Array(lowerBound..<upperBound)
        }
    }

    public func clusterLoads(_ load: CPULoad) -> [ClusterLoad] {
        clusters.map { cluster in
            let cores = cluster.coreIndices
                .filter(load.cores.indices.contains)
                .map { CoreLoad(index: $0, load: load.cores[$0].total) }
            let average = cores.isEmpty ? 0 : cores.reduce(0) { $0 + $1.load } / Double(cores.count)
            return ClusterLoad(name: cluster.name, average: average, cores: cores)
        }
    }
}

public struct CoreLoad: Equatable, Sendable {
    public let index: Int
    /// Busy share 0...1.
    public let load: Double

    public init(index: Int, load: Double) {
        self.index = index
        self.load = load
    }
}

public struct ClusterLoad: Equatable, Sendable {
    public let name: String
    public let average: Double
    public let cores: [CoreLoad]

    public init(name: String, average: Double, cores: [CoreLoad]) {
        self.name = name
        self.average = average
        self.cores = cores
    }
}
