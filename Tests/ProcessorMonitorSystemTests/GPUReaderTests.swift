import Foundation
import IOKit
import Testing
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorSystem

/// Stands in for the GPU's IORegistry entry, which a CI VM does not have.
final class FakeGPURegistry: @unchecked Sendable {
    var service: io_service_t = 42
    var properties: [String: Any] = [:]
    private(set) var lookups = 0
    private(set) var reads: [(io_service_t, String)] = []
    private(set) var released: [io_object_t] = []

    var source: GPUReader.Source {
        GPUReader.Source(
            service: {
                self.lookups += 1
                return self.service
            },
            property: { service, key in
                self.reads.append((service, key))
                return self.properties[key]
            },
            release: { self.released.append($0) }
        )
    }
}

@Suite struct GPUStatisticsParserTests {
    let statistics: [String: Any] = [
        "Device Utilization %": 18,
        "Renderer Utilization %": 17,
        "Tiler Utilization %": 12,
        "Alloc system memory": 3_348_938_752,
    ]

    @Test func readsTheThreeUtilizationShares() {
        #expect(GPUStatisticsParser.load(from: statistics) == GPULoad(device: 0.18, renderer: 0.17, tiler: 0.12))
    }

    @Test func needsEveryShareAsAnInteger() {
        for key in ["Device Utilization %", "Renderer Utilization %", "Tiler Utilization %"] {
            var missing = statistics
            missing[key] = nil
            #expect(GPUStatisticsParser.load(from: missing) == nil)
            var text = statistics
            text[key] = "18"
            #expect(GPUStatisticsParser.load(from: text) == nil)
        }
        #expect(GPUStatisticsParser.load(from: nil) == nil)
        #expect(GPUStatisticsParser.load(from: "not a dictionary") == nil)
    }
}

@Suite struct GPUReaderTests {
    @Test func looksTheGPUUpOnceAndReadsItsStatistics() {
        let registry = FakeGPURegistry()
        registry.properties["PerformanceStatistics"] = ["Device Utilization %": 50, "Renderer Utilization %": 40, "Tiler Utilization %": 5]
        let reader = GPUReader(source: registry.source)
        #expect(reader.read() == GPULoad(device: 0.5, renderer: 0.4, tiler: 0.05))
        registry.properties["PerformanceStatistics"] = nil
        #expect(reader.read() == nil)
        #expect(registry.lookups == 1)
        #expect(registry.reads.map(\.0) == [42, 42])
        #expect(registry.reads.map(\.1) == ["PerformanceStatistics", "PerformanceStatistics"])
    }

    @Test func releasesTheGPUWhenDone() {
        let registry = FakeGPURegistry()
        var reader: GPUReader? = GPUReader(source: registry.source)
        #expect(reader != nil)
        #expect(registry.released.isEmpty)
        reader = nil
        #expect(registry.released == [42])
    }

    /// Real Macs report 0...1; a VM has no GPU entry and reads nothing.
    @Test func liveReadIsAShareOrNothing() {
        let load = GPUReader().read()
        if let load {
            #expect((0...1).contains(load.device))
            #expect((0...1).contains(load.renderer))
            #expect((0...1).contains(load.tiler))
        }
    }
}
