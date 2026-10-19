import Darwin
import Foundation

public struct CommandResult: Equatable, Sendable {
    /// Exit status; -1 when the command could not start, timed out or died from a signal.
    public let status: Int32
    public let timedOut: Bool
    /// Standard output and standard error, interleaved.
    public let output: String

    public init(status: Int32, timedOut: Bool, output: String) {
        self.status = status
        self.timedOut = timedOut
        self.output = output
    }
}

public protocol CommandRunning: Sendable {
    func run(_ command: String, in directory: String, timeout: Double) -> CommandResult
}

/// Runs `/bin/sh -c command` in its own process group, so a timeout can kill everything the
/// command started (a mutant can turn a loop infinite inside a test runner child process).
public struct ShellRunner: CommandRunning {
    public init() {}

    public func run(_ command: String, in directory: String, timeout: Double) -> CommandResult {
        let log = NSTemporaryDirectory() + "pmtools-\(UUID().uuidString).log"
        defer { unlink(log) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addchdir_np(&actions, directory)
        posix_spawn_file_actions_addopen(&actions, 1, log, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)

        var pid: pid_t = 0
        let arguments = ["/bin/sh", "-c", command].map { strdup($0) } + [nil]
        defer { arguments.forEach { free($0) } }
        let spawned = posix_spawn(&pid, "/bin/sh", &actions, &attributes, arguments, environ)
        guard spawned == 0 else {
            return CommandResult(status: -1, timedOut: false, output: "could not start: \(String(cString: strerror(spawned)))")
        }
        let (status, timedOut) = wait(for: pid, timeout: timeout)
        var output = ""
        if let data = FileManager.default.contents(atPath: log) {
            output = String(decoding: data, as: UTF8.self)
        }
        return CommandResult(status: timedOut ? -1 : Self.exitCode(fromWaitStatus: status), timedOut: timedOut, output: output)
    }

    private func wait(for pid: pid_t, timeout: Double) -> (status: Int32, timedOut: Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        var status: Int32 = 0
        while waitpid(pid, &status, WNOHANG) == 0 {
            guard Date() < deadline else {
                kill(-pid, SIGKILL)
                waitpid(pid, &status, 0)
                return (status, true)
            }
            usleep(20_000)
        }
        return (status, false)
    }

    /// `WIFEXITED`/`WEXITSTATUS`, which Swift does not import.
    static func exitCode(fromWaitStatus status: Int32) -> Int32 {
        status & 0x7f == 0 ? (status >> 8) & 0xff : -1
    }
}
