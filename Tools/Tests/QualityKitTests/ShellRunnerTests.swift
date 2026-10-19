import Foundation
import Testing
@testable import QualityKit

@Suite(.timeLimit(.minutes(1))) struct ShellRunnerTests {
    let directory = FileManager.default.temporaryDirectory.path

    @Test func capturesCombinedOutputAndExitStatus() {
        let result = ShellRunner().run("echo out; echo err >&2; exit 3", in: directory, timeout: 10)
        #expect(result == CommandResult(status: 3, timedOut: false, output: "out\nerr\n"))
    }

    @Test func runsInTheGivenDirectory() {
        // Foundation's symlink resolution maps /private/var back to /var; realpath does not.
        let resolved = realpath(directory, nil)!
        defer { free(resolved) }
        let expected = String(cString: resolved)
        #expect(ShellRunner().run("pwd -P", in: directory, timeout: 10).output == expected + "\n")
    }

    @Test func killsTheWholeProcessGroupOnTimeout() {
        let start = Date()
        let result = ShellRunner().run("sleep 30 & sleep 30; wait", in: directory, timeout: 0.3)
        #expect(result.timedOut)
        #expect(result.status == -1)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    /// SwiftPM starts its test runner in a separate process group; a timeout must still kill it.
    @Test func killsDescendantsThatLeftTheProcessGroup() async throws {
        let pidFile = directory + "/pmtools-test-\(UUID().uuidString).pid"
        defer { unlink(pidFile) }
        let result = ShellRunner().run("perl -e 'setpgrp(0, 0); sleep 30' & echo $! > \(pidFile); wait", in: directory, timeout: 0.5)
        #expect(result.timedOut)
        let text = String(decoding: try #require(FileManager.default.contents(atPath: pidFile)), as: UTF8.self)
        let pid = try #require(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        // A killed process lingers until launchd reaps it.
        for _ in 0..<100 where kill(pid, 0) == 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(kill(pid, 0) != 0)
    }

    @Test func listsDescendantsRecursively() throws {
        #expect(ShellRunner.descendants(of: 999_999).isEmpty)
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "sleep 30 & wait"]
        try shell.run()
        usleep(300_000)
        let grandchildren = ShellRunner.descendants(of: shell.processIdentifier)
        let tree = ShellRunner.descendants(of: getpid())
        grandchildren.forEach { kill($0, SIGKILL) }
        shell.terminate()
        #expect(grandchildren.count == 1)
        #expect(tree.contains(shell.processIdentifier))
        #expect(grandchildren.allSatisfy { tree.contains($0) })
    }

    @Test func listsMoreChildrenThanASmallBufferHolds() throws {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "for i in $(seq 70); do sleep 30 & done; wait"]
        try shell.run()
        var children: [pid_t] = []
        for _ in 0..<100 where children.count < 70 {
            usleep(20_000)
            children = ShellRunner.descendants(of: shell.processIdentifier)
        }
        children.forEach { kill($0, SIGKILL) }
        shell.terminate()
        #expect(children.count == 70)
    }

    @Test func reportsSpawnFailures() {
        let result = ShellRunner().run("true", in: "/no/such/directory", timeout: 10)
        #expect(result.status == -1)
        #expect(!result.timedOut)
        #expect(result.output.hasPrefix("could not start: "))
    }

    @Test func decodesWaitStatus() {
        #expect(ShellRunner.exitCode(fromWaitStatus: 3 << 8) == 3)
        // Killed by a signal: no normal exit code.
        #expect(ShellRunner.exitCode(fromWaitStatus: 9) == -1)
        #expect(ShellRunner.timedOut(waitStatus: 9))
        #expect(!ShellRunner.timedOut(waitStatus: 15))
        #expect(!ShellRunner.timedOut(waitStatus: 3 << 8))
    }

    @Test func removesItsOutputLog() throws {
        let logs = FileManager.default.temporaryDirectory.appendingPathComponent("logs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: logs) }
        #expect(ShellRunner(logDirectory: logs.path).run("echo hi", in: directory, timeout: 10).output == "hi\n")
        #expect(try FileManager.default.contentsOfDirectory(atPath: logs.path).isEmpty)
    }

    @Test func normalExitIsNotATimeout() {
        let result = ShellRunner().run("sleep 0.1", in: directory, timeout: 10)
        #expect(result == CommandResult(status: 0, timedOut: false, output: ""))
    }
}
