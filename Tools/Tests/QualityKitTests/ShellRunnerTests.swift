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
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func reportsSpawnFailures() {
        let result = ShellRunner().run("true", in: "/no/such/directory", timeout: 10)
        #expect(result.status == -1)
        #expect(result.output.hasPrefix("could not start: "))
    }

    @Test func decodesWaitStatus() {
        #expect(ShellRunner.exitCode(fromWaitStatus: 3 << 8) == 3)
        // Killed by a signal: no normal exit code.
        #expect(ShellRunner.exitCode(fromWaitStatus: 9) == -1)
    }
}
