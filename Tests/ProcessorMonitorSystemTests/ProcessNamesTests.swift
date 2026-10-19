import Darwin
import Testing
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorSystem

@Suite struct ProcessNamesTests {
    @Test func replacesTruncatedNamesWithTheExecutableName() {
        let processes = [
            ProcessUsage(pid: 1, name: "com.apple.Virtualization.Virtua", cpuPercent: 25),
            ProcessUsage(pid: 0, name: "kernel_task", cpuPercent: 3),
        ]
        let refined = ProcessNames.refine(processes) { pid in
            pid == 1 ? "/System/Library/Frameworks/Virtualization.framework/XPCServices/com.apple.Virtualization.VirtualMachine" : nil
        }
        #expect(refined == [
            ProcessUsage(pid: 1, name: "com.apple.Virtualization.VirtualMachine", cpuPercent: 25),
            ProcessUsage(pid: 0, name: "kernel_task", cpuPercent: 3),
        ])
    }

    @Test func liveExecutablePath() throws {
        let path = try #require(ProcessNames.executablePath(getpid()))
        #expect(path.hasPrefix("/"))
        #expect(ProcessNames.executablePath(1) == "/sbin/launchd")
        #expect(ProcessNames.executablePath(0) == nil)
        #expect(ProcessNames.executablePath(999_999) == nil)
    }
}
