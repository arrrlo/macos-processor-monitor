import Foundation
import ProcessorMonitorCore

public protocol LoginItemControlling: AnyObject {
    /// The pkg-installed LaunchAgent exists (false when run from a development build).
    var isAvailable: Bool { get }
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
}

public enum CommandRunner {
    /// Standard output of a command that exits with status 0, otherwise `nil`.
    public static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Launch at login through the LaunchAgent the pkg installs in /Library/LaunchAgents.
/// Turning it off records a per-user override with `launchctl disable`, which needs no admin
/// rights and survives updates; SMAppService is not used because it is unreliable for
/// ad-hoc signed apps.
public final class LaunchAgentLoginItem: LoginItemControlling {
    private let label: String
    private let plistPath: String
    private let uid: uid_t
    private let run: ([String]) -> String?
    private let fileExists: (String) -> Bool

    public init(
        label: String,
        plistPath: String,
        uid: uid_t,
        run: @escaping ([String]) -> String?,
        fileExists: @escaping (String) -> Bool
    ) {
        self.label = label
        self.plistPath = plistPath
        self.uid = uid
        self.run = run
        self.fileExists = fileExists
    }

    public static func live() -> LaunchAgentLoginItem {
        let label = "io.github.arrrlo.macos-processor-monitor"
        return LaunchAgentLoginItem(
            label: label,
            plistPath: "/Library/LaunchAgents/\(label).plist",
            uid: getuid(),
            run: { CommandRunner.run("/bin/launchctl", $0) },
            fileExists: FileManager.default.fileExists(atPath:)
        )
    }

    public var isAvailable: Bool { fileExists(plistPath) }

    public var isEnabled: Bool {
        guard let output = run(["print-disabled", "gui/\(uid)"]) else { return false }
        return !LaunchctlDisabledParser.isDisabled(label: label, in: output)
    }

    public func setEnabled(_ enabled: Bool) {
        _ = run([enabled ? "enable" : "disable", "gui/\(uid)/\(label)"])
    }
}
