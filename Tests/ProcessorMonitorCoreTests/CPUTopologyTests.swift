import Testing
@testable import ProcessorMonitorCore

@Suite struct CPUTopologyTests {
    /// M5 Max: 12 Performance cores (cluster-type M) at cpu0–11, 6 Super cores (P) at cpu12–17.
    let m5Levels = [PerformanceLevel(name: "Super", logicalCPUCount: 6), PerformanceLevel(name: "Performance", logicalCPUCount: 12)]
    var m5CPUs: [CPUDescriptor] {
        (0..<12).map { CPUDescriptor(logicalID: $0, clusterType: "M") } + (12..<18).map { CPUDescriptor(logicalID: $0, clusterType: "P") }
    }

    @Test func mapsClustersFromRegistryClusterTypes() {
        let topology = CPUTopology.build(coreCount: 18, levels: m5Levels, cpus: m5CPUs)
        #expect(topology.clusters == [
            CPUCluster(name: "Super", coreIndices: Array(12..<18)),
            CPUCluster(name: "Performance", coreIndices: Array(0..<12)),
        ])
    }

    @Test func ranksPerformanceThenMidThenEfficiency() {
        let levels = [
            PerformanceLevel(name: "P", logicalCPUCount: 1),
            PerformanceLevel(name: "M", logicalCPUCount: 1),
            PerformanceLevel(name: "E", logicalCPUCount: 1),
        ]
        let cpus = [CPUDescriptor(logicalID: 0, clusterType: "E"), CPUDescriptor(logicalID: 1, clusterType: "M"), CPUDescriptor(logicalID: 2, clusterType: "P")]
        let topology = CPUTopology.build(coreCount: 3, levels: levels, cpus: cpus)
        #expect(topology.clusters.map(\.coreIndices) == [[2], [1], [0]])
    }

    @Test func unknownClusterTypesRankAfterKnownOnesAlphabetically() {
        let levels = [
            PerformanceLevel(name: "First", logicalCPUCount: 1),
            PerformanceLevel(name: "Second", logicalCPUCount: 1),
            PerformanceLevel(name: "Third", logicalCPUCount: 1),
        ]
        let cpus = [CPUDescriptor(logicalID: 0, clusterType: "Z"), CPUDescriptor(logicalID: 1, clusterType: "X"), CPUDescriptor(logicalID: 2, clusterType: "E")]
        let topology = CPUTopology.build(coreCount: 3, levels: levels, cpus: cpus)
        #expect(topology.clusters.map(\.coreIndices) == [[2], [1], [0]])
    }

    @Test func fallsBackToHighestIndicesFirstWithoutRegistryData() {
        let topology = CPUTopology.build(coreCount: 18, levels: m5Levels, cpus: [])
        #expect(topology.clusters == [
            CPUCluster(name: "Super", coreIndices: Array(12..<18)),
            CPUCluster(name: "Performance", coreIndices: Array(0..<12)),
        ])
    }

    @Test func fallsBackWhenRegistryDisagreesWithPerfLevels() {
        // Cluster sizes don't match the perflevel counts.
        let wrongSizes = (0..<9).map { CPUDescriptor(logicalID: $0, clusterType: "M") } + (9..<18).map { CPUDescriptor(logicalID: $0, clusterType: "P") }
        #expect(CPUTopology.build(coreCount: 18, levels: m5Levels, cpus: wrongSizes).clusters[0].coreIndices == Array(12..<18))
        // Different number of cluster types than perflevels.
        let oneType = (0..<18).map { CPUDescriptor(logicalID: $0, clusterType: "M") }
        #expect(CPUTopology.build(coreCount: 18, levels: m5Levels, cpus: oneType).clusters[0].coreIndices == Array(12..<18))
        // Logical ids that are not exactly 0..<coreCount.
        let shifted = m5CPUs.map { CPUDescriptor(logicalID: $0.logicalID + 1, clusterType: $0.clusterType) }
        #expect(CPUTopology.build(coreCount: 18, levels: m5Levels, cpus: shifted).clusters[0].coreIndices == Array(12..<18))
    }

    @Test func singleClusterWithoutUsablePerfLevels() {
        let expected = [CPUCluster(name: "CPU", coreIndices: [0, 1, 2, 3])]
        #expect(CPUTopology.build(coreCount: 4, levels: [], cpus: []).clusters == expected)
        let mismatched = [PerformanceLevel(name: "P", logicalCPUCount: 3)]
        #expect(CPUTopology.build(coreCount: 4, levels: mismatched, cpus: []).clusters == expected)
    }

    @Test func dropsEmptyPerfLevels() {
        let levels = [PerformanceLevel(name: "P", logicalCPUCount: 2), PerformanceLevel(name: "Ghost", logicalCPUCount: 0)]
        #expect(CPUTopology.build(coreCount: 2, levels: levels, cpus: []).clusters == [CPUCluster(name: "P", coreIndices: [0, 1])])
    }

    @Test func noCoresMeansNoClusters() {
        #expect(CPUTopology.build(coreCount: 0, levels: [], cpus: []).clusters.isEmpty)
    }

    @Test func coreCountSumsClusters() {
        #expect(CPUTopology.build(coreCount: 18, levels: m5Levels, cpus: m5CPUs).coreCount == 18)
    }
}

@Suite struct ClusterLoadTests {
    let topology = CPUTopology(clusters: [
        CPUCluster(name: "Super", coreIndices: [2, 3]),
        CPUCluster(name: "Performance", coreIndices: [0, 1]),
    ])

    func load(_ totals: [Double]) -> CPULoad {
        CPULoad(overall: .idle, cores: totals.map { LoadBreakdown(user: $0, system: 0, idle: 1 - $0) })
    }

    @Test func averagesEachClusterAndKeepsCoreLoads() {
        let clusters = topology.clusterLoads(load([0.5, 0.25, 1.0, 0.5]))
        #expect(clusters == [
            ClusterLoad(name: "Super", average: 0.75, cores: [CoreLoad(index: 2, load: 1.0), CoreLoad(index: 3, load: 0.5)]),
            ClusterLoad(name: "Performance", average: 0.375, cores: [CoreLoad(index: 0, load: 0.5), CoreLoad(index: 1, load: 0.25)]),
        ])
    }

    @Test func ignoresCoresMissingFromTheLoad() {
        let clusters = topology.clusterLoads(load([0.5, 0.25]))
        #expect(clusters[0] == ClusterLoad(name: "Super", average: 0, cores: []))
        #expect(clusters[1].average == 0.375)
    }
}
