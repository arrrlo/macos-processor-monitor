import Foundation
import IOKit
import Testing
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorSystem

@Suite struct SysctlTests {
    @Test func readsIntegersAndStrings() throws {
        let cpus = try #require(Sysctl.int("hw.logicalcpu"))
        #expect(cpus == ProcessInfo.processInfo.processorCount)
        #expect(Sysctl.string("kern.ostype") == "Darwin")
    }

    @Test func readsSixtyFourBitIntegers() throws {
        let memory = try #require(Sysctl.int("hw.memsize"))
        #expect(UInt64(memory) == ProcessInfo.processInfo.physicalMemory)
    }

    @Test func unknownNamesReturnNil() {
        #expect(Sysctl.int("hw.definitely_not_here") == nil)
        #expect(Sysctl.string("hw.definitely_not_here") == nil)
    }

    @Test func rejectsValuesOfUnexpectedWidth() {
        // kern.ostype is a string; reading it as an integer has the wrong width.
        #expect(Sysctl.int("kern.ostype") == nil)
    }
}

@Suite struct RegistryCPUParserTests {
    @Test func parsesLogicalIDAndClusterType() {
        let properties: [String: Any] = ["logical-cpu-id": NSNumber(value: 12), "cluster-type": Data([0x50, 0x00])]
        #expect(RegistryCPUParser.descriptor(from: properties) == CPUDescriptor(logicalID: 12, clusterType: "P"))
    }

    @Test func rejectsIncompleteEntries() {
        #expect(RegistryCPUParser.descriptor(from: ["cluster-type": Data([0x50])]) == nil)
        #expect(RegistryCPUParser.descriptor(from: ["logical-cpu-id": NSNumber(value: 1)]) == nil)
        #expect(RegistryCPUParser.descriptor(from: ["logical-cpu-id": NSNumber(value: 1), "cluster-type": Data([0x00])]) == nil)
    }

    @Test func liveRegistryListsEveryCore() {
        let cpus = IORegistryCPUs.read()
        // CI VMs may expose no device tree CPUs; when present they must cover every core.
        if !cpus.isEmpty {
            #expect(Set(cpus.map(\.logicalID)) == Set(0..<ProcessInfo.processInfo.processorCount))
        }
    }

    @Test func missingRegistryPathYieldsNothing() {
        #expect(IORegistryCPUs.childProperties(path: "IODeviceTree:/no-such-node").isEmpty)
    }
}

@Suite struct TopologyReaderTests {
    @Test func readsPerfLevelsAndRegistry() {
        let values: [String: Int] = ["hw.nperflevels": 2, "hw.perflevel0.logicalcpu": 1, "hw.perflevel1.logicalcpu": 2]
        let names = ["hw.perflevel0.name": "Super", "hw.perflevel1.name": "Performance"]
        let source = TopologyReader.Source(
            int: { values[$0] },
            string: { names[$0] },
            registryCPUs: { [CPUDescriptor(logicalID: 0, clusterType: "M"), CPUDescriptor(logicalID: 1, clusterType: "M"), CPUDescriptor(logicalID: 2, clusterType: "P")] }
        )
        let topology = TopologyReader(source: source).read(coreCount: 3)
        #expect(topology.clusters == [CPUCluster(name: "Super", coreIndices: [2]), CPUCluster(name: "Performance", coreIndices: [0, 1])])
    }

    @Test func skipsIncompletePerfLevels() {
        let values: [String: Int] = ["hw.nperflevels": 2, "hw.perflevel0.logicalcpu": 2]
        let source = TopologyReader.Source(int: { values[$0] }, string: { _ in "X" }, registryCPUs: { [] })
        #expect(TopologyReader(source: source).read(coreCount: 2).clusters == [CPUCluster(name: "X", coreIndices: [0, 1])])
    }

    @Test func missingPerfLevelCountMeansSingleCluster() {
        let source = TopologyReader.Source(int: { _ in nil }, string: { _ in nil }, registryCPUs: { [] })
        #expect(TopologyReader(source: source).read(coreCount: 2).clusters == [CPUCluster(name: "CPU", coreIndices: [0, 1])])
    }

    @Test func liveTopologyCoversEveryCore() {
        let count = ProcessInfo.processInfo.processorCount
        let topology = TopologyReader().read(coreCount: count)
        #expect(topology.coreCount == count)
        #expect(Set(topology.clusters.flatMap(\.coreIndices)) == Set(0..<count))
    }
}

/// Hands out numbered objects and tracks which are still unreleased.
final class FakeRegistry: @unchecked Sendable {
    private(set) var outstanding: Set<io_object_t> = []
    private var nextObject: io_object_t = 100
    var childCount = 2

    func make() -> io_object_t {
        nextObject += 1
        outstanding.insert(nextObject)
        return nextObject
    }

    var access: RegistryAccess {
        RegistryAccess(
            entry: { _ in self.make() },
            childIterator: { _ in self.make() },
            next: { _ in
                guard self.childCount > 0 else { return 0 }
                self.childCount -= 1
                return self.make()
            },
            properties: { object in ["object": NSNumber(value: object)] },
            release: { self.outstanding.remove($0) }
        )
    }
}

/// Serialized: iterating the root takes references on its children, which the retain-count tests measure.
@Suite(.serialized) struct IORegistryTraversalTests {
    /// The device tree root always has children, even in VMs, so the traversal loop is exercised everywhere.
    @Test func listsChildrenOfTheDeviceTreeRoot() {
        #expect(!IORegistryCPUs.childProperties(path: "IODeviceTree:/").isEmpty)
    }

    @Test func releasesEveryObjectItObtains() {
        let registry = FakeRegistry()
        let children = IORegistryCPUs.childProperties(path: "any", access: registry.access)
        #expect(children.count == 2)
        #expect(registry.outstanding.isEmpty)
    }

    // Retain counts are per registry entry, so each live test uses a node no other test touches.
    @Test func liveReleaseDropsAReference() {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/options")
        let extra = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/options")
        let before = IOObjectGetUserRetainCount(entry)
        RegistryAccess.live.release(extra)
        #expect(IOObjectGetUserRetainCount(entry) == before - 1)
        IOObjectRelease(entry)
    }

    @Test func liveTraversalLeavesNoReferencesBehind() {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen")
        let before = IOObjectGetUserRetainCount(entry)
        _ = IORegistryCPUs.childProperties(path: "IODeviceTree:/chosen")
        #expect(IOObjectGetUserRetainCount(entry) == before)
        IOObjectRelease(entry)
    }
}
