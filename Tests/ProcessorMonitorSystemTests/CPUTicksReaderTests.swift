import Darwin
import Foundation
import Testing
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorSystem

/// Records what the reader hands back to `vm_deallocate`.
final class DeallocationLog: @unchecked Sendable {
    var calls: [(address: vm_address_t, size: vm_size_t)] = []
}

@Suite struct CPUTicksReaderTests {
    @Test func liveReadReturnsOneEntryPerLogicalCPU() throws {
        let sample = try #require(CPUTicksReader().read())
        #expect(sample.cores.count == ProcessInfo.processInfo.processorCount)
    }

    @Test func liveTicksAdvance() throws {
        let reader = CPUTicksReader()
        let first = try #require(reader.read())
        usleep(30_000)
        let second = try #require(reader.read())
        let elapsed = zip(first.cores, second.cores).reduce(UInt64(0)) { sum, pair in
            sum + UInt64(pair.1.user &- pair.0.user) + UInt64(pair.1.system &- pair.0.system) + UInt64(pair.1.idle &- pair.0.idle)
        }
        #expect(elapsed > 0)
    }

    @Test func parsesCountersAndDeallocatesTheKernelBuffer() throws {
        let values: [integer_t] = [1, 2, 3, 4, 10, 20, -1, 40]
        nonisolated(unsafe) let buffer = UnsafeMutablePointer<integer_t>.allocate(capacity: values.count)
        buffer.initialize(from: values, count: values.count)
        let log = DeallocationLog()
        let source = CPUTicksReader.Source(
            query: { (KERN_SUCCESS, 2, buffer, mach_msg_type_number_t(values.count)) },
            deallocate: { address, size in
                log.calls.append((address, size))
                UnsafeMutablePointer<integer_t>(bitPattern: address)?.deallocate()
            }
        )
        let sample = try #require(CPUTicksReader(source: source).read())
        #expect(sample.cores == [
            CoreTicks(user: 1, system: 2, idle: 3, nice: 4),
            CoreTicks(user: 10, system: 20, idle: UInt32.max, nice: 40),
        ])
        #expect(log.calls.count == 1)
        #expect(log.calls.first?.size == vm_size_t(values.count * MemoryLayout<integer_t>.stride))
    }

    @Test func failedQueryReturnsNilWithoutDeallocating() {
        let log = DeallocationLog()
        let source = CPUTicksReader.Source(query: { (KERN_FAILURE, 0, nil, 0) }, deallocate: { log.calls.append(($0, $1)) })
        #expect(CPUTicksReader(source: source).read() == nil)
        #expect(log.calls.isEmpty)
    }

    @Test func successWithoutBufferReturnsNil() {
        let source = CPUTicksReader.Source(query: { (KERN_SUCCESS, 1, nil, 0) }, deallocate: { _, _ in })
        #expect(CPUTicksReader(source: source).read() == nil)
    }
}
