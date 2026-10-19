import Foundation
import os

public struct MutationConfiguration: Sendable {
    public var packageDirectory: String
    /// Builds sources and tests, e.g. `swift build --build-tests …`.
    public var buildCommand: String
    /// Runs the tests without building, e.g. `swift test --skip-build …`; `--filter` is appended.
    public var testCommand: String
    /// Parallel workers, each with its own copy of the package.
    public var jobs: Int
    public var timeoutFactor: Double
    public var minimumTimeout: Double

    public init(packageDirectory: String, buildCommand: String, testCommand: String, jobs: Int, timeoutFactor: Double, minimumTimeout: Double) {
        self.packageDirectory = packageDirectory
        self.buildCommand = buildCommand
        self.testCommand = testCommand
        self.jobs = jobs
        self.timeoutFactor = timeoutFactor
        self.minimumTimeout = minimumTimeout
    }

    public func testTimeout(baseline: Double) -> Double {
        max(minimumTimeout, baseline * timeoutFactor)
    }
}

public enum MutantOutcome: String, Equatable, Sendable {
    case killed
    case survived
    /// Did not compile; not counted in the score.
    case invalid
    /// Tests ran past the timeout (e.g. an infinite loop); counts as killed.
    case timedOut = "timed out"
}

public struct MutantResult: Equatable, Sendable {
    public let mutant: Mutant
    public let outcome: MutantOutcome
}

/// Applies each mutant in one of `jobs` scratch copies of the package, rebuilds incrementally,
/// runs the owning target's tests and then, if those pass, the whole suite.
public final class MutationRunner: Sendable {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case baseline(String)

        public var description: String {
            switch self {
            case .baseline(let output): "baseline build or tests failed in a workspace:\n\(output)"
            }
        }
    }

    static let setupTimeout: Double = 1800

    private let configuration: MutationConfiguration
    private let environment: ToolEnvironment
    private let root: SourceRoot

    public init(configuration: MutationConfiguration, environment: ToolEnvironment) {
        self.configuration = configuration
        self.environment = environment
        root = SourceRoot(configuration.packageDirectory)
    }

    public func run(_ mutants: [Mutant]) throws -> [MutantResult] {
        guard !mutants.isEmpty else { return [] }
        let workspaces = (0..<max(configuration.jobs, 1)).map(workspacePath)
        let baselines = OSAllocatedUnfairLock<[Int: Result<Double, Failure>]>(initialState: [:])
        DispatchQueue.concurrentPerform(iterations: workspaces.count) { index in
            let result = baseline(in: workspaces[index])
            baselines.withLock { $0[index] = result }
        }
        let durations = try baselines.withLock { $0 }.sorted { $0.key < $1.key }.map { try $0.value.get() }
        let timeout = configuration.testTimeout(baseline: durations.reduce(0, max))

        let next = OSAllocatedUnfairLock(initialState: 0)
        let results = OSAllocatedUnfairLock<[Int: MutantResult]>(initialState: [:])
        DispatchQueue.concurrentPerform(iterations: workspaces.count) { worker in
            while let index = next.withLock({ Self.take(&$0, below: mutants.count) }) {
                let result = MutantResult(mutant: mutants[index], outcome: evaluate(mutants[index], in: workspaces[worker], timeout: timeout))
                let done = results.withLock { finished -> Int in
                    finished[index] = result
                    return finished.count
                }
                environment.output("[\(done)/\(mutants.count)] \(result.outcome.rawValue): \(result.mutant.describe(root: root))")
            }
        }
        return results.withLock { $0 }.sorted { $0.key < $1.key }.map(\.value)
    }

    /// Hands out 0, 1, 2… until `limit`, then `nil`.
    static func take(_ counter: inout Int, below limit: Int) -> Int? {
        guard counter < limit else { return nil }
        defer { counter += 1 }
        return counter
    }

    private func workspacePath(_ index: Int) -> String {
        let name = URL(fileURLWithPath: configuration.packageDirectory).lastPathComponent
        return "\(environment.temporaryDirectory)/pmtools-mutation/\(name)-\(index)"
    }

    /// Syncs the workspace with the package, builds it and times one full test run.
    private func baseline(in workspace: String) -> Result<Double, Failure> {
        let sync = "mkdir -p \(Self.quote(workspace)) && rsync -a --delete --exclude .build --exclude .git --exclude .swiftpm "
            + "\(Self.quote(configuration.packageDirectory + "/")) \(Self.quote(workspace + "/"))"
        for (command, directory) in [(sync, configuration.packageDirectory), (configuration.buildCommand, workspace)] {
            let result = environment.runner.run(command, in: directory, timeout: Self.setupTimeout)
            guard result.status == 0 else { return .failure(.baseline(result.output)) }
        }
        let start = environment.now()
        let tests = environment.runner.run(configuration.testCommand, in: workspace, timeout: Self.setupTimeout)
        guard tests.status == 0 else { return .failure(.baseline(tests.output)) }
        return .success(environment.now() - start)
    }

    private func evaluate(_ mutant: Mutant, in workspace: String, timeout: Double) -> MutantOutcome {
        let path = workspace + "/" + root.display(mutant.file)
        guard let original = try? environment.readFile(path) else { return .invalid }
        try? environment.writeFile(path, Data(mutant.apply(to: String(decoding: original, as: UTF8.self)).utf8))
        defer { try? environment.writeFile(path, original) }

        guard environment.runner.run(configuration.buildCommand, in: workspace, timeout: Self.setupTimeout).status == 0 else {
            return .invalid
        }
        var commands = [configuration.testCommand]
        if let filter = mutant.testFilter(packageRoot: root) {
            commands.insert("\(configuration.testCommand) --filter \(Self.quote(filter))", at: 0)
        }
        for command in commands {
            let result = environment.runner.run(command, in: workspace, timeout: timeout)
            if result.timedOut {
                return .timedOut
            }
            if result.status != 0 {
                return .killed
            }
        }
        return .survived
    }

    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct MutationReport: Equatable, Sendable {
    public let results: [MutantResult]
    let root: SourceRoot

    public init(results: [MutantResult], root: SourceRoot) {
        self.results = results
        self.root = root
    }

    private func count(_ outcome: MutantOutcome) -> Int {
        results.filter { $0.outcome == outcome }.count
    }

    private var valid: Int { results.count - count(.invalid) }

    /// Killed (including timeouts) out of all mutants that compiled.
    public var score: Double {
        valid == 0 ? 1 : Double(count(.killed) + count(.timedOut)) / Double(valid)
    }

    public var passed: Bool { count(.survived) == 0 }

    public var lines: [String] {
        var lines = [
            "Mutation testing: \(results.count) mutants — killed \(count(.killed)), timed out \(count(.timedOut)), "
                + "survived \(count(.survived)), invalid \(count(.invalid))",
            "Mutation score: \(String(format: "%.1f", score * 100))% of \(valid) valid mutants",
        ]
        let survivors = results.filter { $0.outcome == .survived }
        if !survivors.isEmpty {
            lines.append("Survivors:")
            lines += survivors.map { "  \($0.mutant.describe(root: root))" }
        }
        return lines
    }
}
