import Darwin
import Foundation
import ProcessorMonitorCore

/// The kernel keeps only the first 32 characters of a process name (`pbi_name`), which cuts off
/// names like `com.apple.Virtualization.VirtualMachine`. The executable path has the full name and
/// is readable for every user's processes, so the few listed processes are renamed from it.
public enum ProcessNames {
    static func refine(_ processes: [ProcessUsage], executablePath: (Int32) -> String?) -> [ProcessUsage] {
        processes.map { process in
            guard let path = executablePath(process.pid) else { return process }
            return ProcessUsage(pid: process.pid, name: URL(fileURLWithPath: path).lastPathComponent, cpuPercent: process.cpuPercent)
        }
    }

    /// `nil` for processes without an executable (kernel_task) or that no longer exist.
    static func executablePath(_ pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE (4 × MAXPATHLEN) is not imported into Swift.
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }
}
