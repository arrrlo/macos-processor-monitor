import AppKit
import ProcessorMonitorCore

/// Display name and icon of a GUI application.
public struct AppInfo {
    public let name: String
    public let icon: NSImage

    public init(name: String, icon: NSImage) {
        self.name = name
        self.icon = icon
    }
}

/// Maps listed processes to their applications. Lookups are cached for as long as a process
/// stays in the list, so an open menu does not query LaunchServices every tick.
@MainActor
public final class ProcessIdentityResolver {
    private struct Key: Hashable {
        let pid: Int32
        let name: String
    }

    private let lookup: (pid_t) -> AppInfo?
    private var cache: [Key: AppInfo?] = [:]

    public init(lookup: @escaping (pid_t) -> AppInfo?) {
        self.lookup = lookup
    }

    public static func live() -> ProcessIdentityResolver {
        ProcessIdentityResolver(lookup: runningApplication)
    }

    static func runningApplication(_ pid: pid_t) -> AppInfo? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let name = app.localizedName,
              let icon = app.icon else { return nil }
        return AppInfo(name: name, icon: icon)
    }

    /// Apps among `processes`, by PID. Forgets processes that are no longer listed.
    public func resolve(_ processes: [ProcessUsage]) -> [Int32: AppInfo] {
        var kept: [Key: AppInfo?] = [:]
        var apps: [Int32: AppInfo] = [:]
        for process in processes {
            let key = Key(pid: process.pid, name: process.name)
            let info = cache[key] ?? lookup(process.pid)
            kept[key] = .some(info)
            apps[process.pid] = info
        }
        cache = kept
        return apps
    }
}
