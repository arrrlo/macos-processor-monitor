import Darwin
import Foundation
import Testing
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorSystem

@Suite struct ProcessTableReaderTests {
    @Test func liveSnapshotContainsThisProcess() throws {
        let snapshot = ProcessTableReader().snapshot()
        let me = try #require(snapshot.processes.first { $0.pid == getpid() })
        #expect(!me.name.isEmpty)
        #expect(me.cpuTime > 0)
        #expect(me.startTime > 0)
        #expect(snapshot.timestamp > 0)
    }

    @Test func liveSnapshotSkipsProcessesItCannotRead() {
        // Run as a normal user, root-owned processes such as launchd (pid 1) are not readable.
        let pids = Set(ProcessTableReader().snapshot().processes.map(\.pid))
        #expect(!pids.contains(1) || geteuid() == 0)
        #expect(ProcessTableReader.Source.live.taskInfo(1) == nil || geteuid() == 0)
    }

    @Test func liveListIncludesLaunchd() {
        #expect(ProcessTableReader.Source.live.listPIDs().contains(1))
    }

    @Test func buildsSamplesFromTaskInfo() {
        var info = proc_taskallinfo()
        info.pbsd.pbi_start_tvsec = 3
        info.pbsd.pbi_start_tvusec = 4
        info.ptinfo.pti_total_user = 10
        info.ptinfo.pti_total_system = 5
        setName(&info.pbsd.pbi_name, "LongerName")
        setName(&info.pbsd.pbi_comm, "short")
        let named = info
        var unnamed = info
        setName(&unnamed.pbsd.pbi_name, "")
        let commOnly = unnamed

        let source = ProcessTableReader.Source(
            listPIDs: { [10, 11, 12] },
            taskInfo: { pid in [10: named, 11: commOnly][pid] },
            now: { 77 }
        )
        let snapshot = ProcessTableReader(source: source).snapshot()
        #expect(snapshot == ProcessSnapshot(timestamp: 77, processes: [
            ProcessSample(pid: 10, startTime: 3_000_004, name: "LongerName", cpuTime: 15),
            ProcessSample(pid: 11, startTime: 3_000_004, name: "short", cpuTime: 15),
        ]))
    }

    @Test func liveTimebaseIsPositive() {
        let timebase = ProcessTableReader.liveTimebase()
        #expect(timebase.numer > 0)
        #expect(timebase.denom > 0)
    }

    @Test func liveClockIsMonotonic() {
        let first = ProcessTableReader.Source.live.now()
        let second = ProcessTableReader.Source.live.now()
        #expect(second >= first)
    }
}

private func setName<T>(_ field: inout T, _ name: String) {
    withUnsafeMutableBytes(of: &field) { buffer in
        buffer.initializeMemory(as: UInt8.self, repeating: 0)
        for (index, byte) in name.utf8.prefix(buffer.count - 1).enumerated() {
            buffer[index] = byte
        }
    }
}
