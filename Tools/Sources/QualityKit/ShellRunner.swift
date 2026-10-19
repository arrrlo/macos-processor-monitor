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
    private let logDirectory: String

    public init(logDirectory: String = NSTemporaryDirectory()) {
        self.logDirectory = logDirectory
    }

    public func run(_ command: String, in directory: String, timeout: Double) -> CommandResult {
        let log = logDirectory + "/pmtools-\(UUID().uuidString).log"
        defer { unlink(log) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        // mutation:disable-next-line frees libc's small action list; a leak is not observable in tests
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addchdir_np(&actions, directory)
        posix_spawn_file_actions_addopen(&actions, 1, log, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        // mutation:disable-next-line frees libc's small attribute object; a leak is not observable in tests
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        // mutation:disable-next-line 0 is already the default group, meaning "a new group led by the child"
        posix_spawnattr_setpgroup(&attributes, 0)

        var pid: pid_t = 0
        let spawned = "/bin/sh".withCString { shell in
            "-c".withCString { flag in
                command.withCString { script in
                    let arguments = [UnsafeMutablePointer(mutating: shell), UnsafeMutablePointer(mutating: flag), UnsafeMutablePointer(mutating: script), nil]
                    return posix_spawn(&pid, shell, &actions, &attributes, arguments, environ)
                }
            }
        }
        guard spawned == 0 else {
            return CommandResult(status: -1, timedOut: false, output: "could not start: \(String(cString: strerror(spawned)))")
        }
        let status = wait(for: pid, timeout: timeout)
        var output = ""
        if let data = FileManager.default.contents(atPath: log) {
            output = String(decoding: data, as: UTF8.self)
        }
        return CommandResult(status: Self.exitCode(fromWaitStatus: status), timedOut: Self.timedOut(waitStatus: status), output: output)
    }

    /// Polls until the process exits, killing its whole group once the deadline passes.
    private func wait(for pid: pid_t, timeout: Double) -> Int32 {
        let deadline = Date().addingTimeInterval(timeout)
        var status: Int32 = 0
        while waitpid(pid, &status, WNOHANG) == 0 {
            // mutation:disable-next-line a continuous clock never lands exactly on the deadline
            if Date() > deadline {
                // Collected first: once a parent dies, its children are re-parented to launchd.
                let tree = Self.descendants(of: pid)
                kill(-pid, SIGKILL)
                tree.forEach { kill($0, SIGKILL) }
            }
            // mutation:disable-next-line only the polling interval; without it the loop spins but behaves the same
            usleep(20_000)
        }
        return status
    }

    /// Every process started below `pid`. SwiftPM runs tests in their own process group, so killing
    /// the group is not enough.
    static func descendants(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 1024)
        let count = buffer.withUnsafeMutableBufferPointer {
            proc_listchildpids(pid, $0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
        }
        let children = Array(buffer.prefix(max(Int(count), 0)))
        return children + children.flatMap(descendants)
    }

    /// `WIFEXITED`/`WEXITSTATUS`, which Swift does not import.
    static func exitCode(fromWaitStatus status: Int32) -> Int32 {
        status & 0x7f == 0 ? (status >> 8) & 0xff : -1
    }

    /// Only the timeout sends SIGKILL to the group.
    static func timedOut(waitStatus status: Int32) -> Bool {
        status & 0x7f == SIGKILL
    }
}
