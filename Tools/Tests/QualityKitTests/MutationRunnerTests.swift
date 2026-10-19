import Foundation
import Testing
@testable import QualityKit

/// Thread-safe in-memory files plus a scripted command runner.
final class FakeMutationWorld: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private(set) var commands: [(command: String, directory: String)] = []
    private(set) var output: [String] = []
    var respond: @Sendable (_ command: String, _ directory: String, _ world: FakeMutationWorld) -> CommandResult = { _, _, _ in
        CommandResult(status: 0, timedOut: false, output: "")
    }
    var clock: Double = 0

    func file(_ path: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return files[path].map { String(decoding: $0, as: UTF8.self) }
    }

    func setFile(_ path: String, _ text: String) {
        lock.lock()
        files[path] = Data(text.utf8)
        lock.unlock()
    }

    var environment: ToolEnvironment {
        ToolEnvironment(
            readFile: { path in
                guard let text = self.file(path) else { throw CocoaError(.fileNoSuchFile) }
                return Data(text.utf8)
            },
            swiftFiles: { directory in
                self.lock.lock()
                defer { self.lock.unlock() }
                return self.files.keys.filter { $0.hasPrefix(directory + "/") && $0.hasSuffix(".swift") }.sorted()
            },
            output: { line in
                self.lock.lock()
                self.output.append(line)
                self.lock.unlock()
            },
            writeFile: { path, data in self.setFile(path, String(decoding: data, as: UTF8.self)) },
            runner: FakeRunner(world: self),
            temporaryDirectory: "/tmp",
            now: {
                self.lock.lock()
                defer { self.lock.unlock() }
                self.clock += 1
                return self.clock
            }
        )
    }

    func record(_ command: String, _ directory: String) -> CommandResult {
        lock.lock()
        commands.append((command, directory))
        lock.unlock()
        return respond(command, directory, self)
    }
}

struct FakeRunner: CommandRunning {
    let world: FakeMutationWorld

    func run(_ command: String, in directory: String, timeout: Double) -> CommandResult {
        world.record(command, directory)
    }
}

@Suite struct MutationRunnerTests {
    let package = "/p"
    let configuration = MutationConfiguration(
        packageDirectory: "/p",
        buildCommand: "build",
        testCommand: "test",
        jobs: 1,
        timeoutFactor: 3,
        minimumTimeout: 30
    )

    func mutant(_ replacement: String, file: String = "/p/Sources/A/a.swift") -> Mutant {
        Mutant(file: file, line: 1, column: 9, utf8Range: 8..<9, original: "x", replacement: replacement, operatorName: "test")
    }

    /// Workspace files mirror the package; commands react to what the mutated file contains.
    func makeWorld() -> FakeMutationWorld {
        let world = FakeMutationWorld()
        world.setFile("/tmp/pmtools-mutation/p-0/Sources/A/a.swift", "let a = x")
        world.setFile("/tmp/pmtools-mutation/p-0/Other/b.swift", "let b = x")
        world.setFile("/tmp/pmtools-mutation/p-1/Sources/A/a.swift", "let a = x")
        world.respond = { command, directory, world in
            let source = (world.file(directory + "/Sources/A/a.swift") ?? "") + (world.file(directory + "/Other/b.swift") ?? "")
            switch command {
            case "build" where source.contains("BROKEN"):
                return CommandResult(status: 1, timedOut: false, output: "error")
            case "test --filter 'ATests'" where source.contains("KILLED"),
                 "test" where source.contains("FULL"):
                return CommandResult(status: 1, timedOut: false, output: "failed")
            case "test --filter 'ATests'" where source.contains("HANG"):
                return CommandResult(status: -1, timedOut: true, output: "")
            default:
                return CommandResult(status: 0, timedOut: false, output: "")
            }
        }
        return world
    }

    @Test func classifiesEveryOutcomeAndRestoresTheSource() throws {
        let world = makeWorld()
        let runner = MutationRunner(configuration: configuration, environment: world.environment)
        let results = try runner.run([
            mutant("KILLED"), mutant("SURVIVOR"), mutant("BROKEN"), mutant("HANG"), mutant("FULL"),
            mutant("MISSING", file: "/p/Sources/A/missing.swift"),
            mutant("FULL", file: "/p/Other/b.swift"),
        ])
        #expect(results.map(\.outcome) == [.killed, .survived, .invalid, .timedOut, .killed, .invalid, .killed])
        #expect(world.file("/tmp/pmtools-mutation/p-0/Sources/A/a.swift") == "let a = x")
        #expect(world.file("/tmp/pmtools-mutation/p-0/Other/b.swift") == "let b = x")
        // Mutants outside Sources/<Target>/ skip the targeted run and go straight to the full suite.
        #expect(world.commands.suffix(2).map(\.command) == ["build", "test"])
    }

    @Test func preparesAWorkspacePerJobAndChecksTheBaseline() throws {
        let world = makeWorld()
        var parallel = configuration
        parallel.jobs = 2
        _ = try MutationRunner(configuration: parallel, environment: world.environment).run([mutant("KILLED"), mutant("SURVIVOR")])
        let prepares = world.commands.filter { $0.command.hasPrefix("mkdir -p") }
        #expect(prepares.count == 2)
        #expect(prepares[0].command.contains("rsync -a --delete --exclude .build --exclude .git --exclude .swiftpm '/p/' '/tmp/pmtools-mutation/p-"))
        #expect(world.commands.filter { $0.command == "build" }.count == 4)
    }

    @Test func failingBaselineStopsTheRun() {
        let world = makeWorld()
        world.respond = { command, _, _ in
            CommandResult(status: command == "test" ? 1 : 0, timedOut: false, output: "baseline broke")
        }
        let runner = MutationRunner(configuration: configuration, environment: world.environment)
        #expect(throws: MutationRunner.Failure.baseline("baseline broke")) {
            try runner.run([mutant("KILLED")])
        }
    }

    @Test func failingBaselineBuildStopsTheRun() {
        let world = makeWorld()
        world.respond = { command, _, _ in
            CommandResult(status: command == "build" ? 1 : 0, timedOut: false, output: "does not compile")
        }
        #expect(throws: MutationRunner.Failure.baseline("does not compile")) {
            try MutationRunner(configuration: configuration, environment: world.environment).run([mutant("KILLED")])
        }
    }

    @Test func noMutantsMeansNoWork() throws {
        let world = makeWorld()
        #expect(try MutationRunner(configuration: configuration, environment: world.environment).run([]).isEmpty)
        #expect(world.commands.isEmpty)
    }

    @Test func testTimeoutScalesWithTheBaseline() {
        #expect(configuration.testTimeout(baseline: 2) == 30)
        #expect(configuration.testTimeout(baseline: 20) == 60)
    }

    @Test func failureDescription() {
        #expect(MutationRunner.Failure.baseline("x").description == "baseline build or tests failed in a workspace:\nx")
    }

    @Test func shellQuoting() {
        #expect(MutationRunner.quote("/a b/it's") == "'/a b/it'\\''s'")
    }
}

@Suite struct MutationReportTests {
    func result(_ outcome: MutantOutcome, _ line: Int = 1) -> MutantResult {
        MutantResult(
            mutant: Mutant(file: "/p/Sources/A/a.swift", line: line, column: 2, utf8Range: 0..<1, original: "<", replacement: ">=", operatorName: "relational"),
            outcome: outcome
        )
    }

    @Test func summarisesAndListsSurvivors() {
        let report = MutationReport(results: [result(.killed), result(.timedOut), result(.invalid), result(.survived, 7)], root: SourceRoot("/p"))
        #expect(report.score == 2.0 / 3.0)
        #expect(!report.passed)
        #expect(report.lines == [
            "Mutation testing: 4 mutants — killed 1, timed out 1, survived 1, invalid 1",
            "Mutation score: 66.7% of 3 valid mutants",
            "Survivors:",
            "  Sources/A/a.swift:7:2 relational `<` → `>=`",
        ])
    }

    @Test func allValidMutantsKilledPasses() {
        let report = MutationReport(results: [result(.killed), result(.invalid)], root: SourceRoot("/p"))
        #expect(report.passed)
        #expect(report.lines.last == "Mutation score: 100.0% of 1 valid mutants")
    }

    @Test func nothingValidScoresFull() {
        #expect(MutationReport(results: [], root: SourceRoot("/p")).score == 1)
    }
}
