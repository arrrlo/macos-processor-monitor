import Foundation
import Testing
@testable import QualityKit

/// Collects tool output and serves in-memory files.
final class FakeEnvironment: @unchecked Sendable {
    var files: [String: Data] = [:]
    var directories: [String: [String]] = [:]
    var lines: [String] = []

    var environment: ToolEnvironment {
        ToolEnvironment(
            readFile: { path in
                guard let data = self.files[path] else { throw CocoaError(.fileNoSuchFile) }
                return data
            },
            swiftFiles: { directory in
                guard let files = self.directories[directory] else { throw CocoaError(.fileNoSuchFile) }
                return files
            },
            output: { self.lines.append($0) }
        )
    }
}

@Suite struct ArgumentListTests {
    @Test func parsesSubcommandAndOptions() throws {
        let list = try ArgumentList(["coverage", "--json", "a.json", "--exclude", "x", "--exclude", "y"])
        #expect(list.subcommand == "coverage")
        #expect(try list.value(for: "json") == "a.json")
        #expect(list.values(for: "exclude") == ["x", "y"])
        #expect(list.values(for: "missing").isEmpty)
        #expect(list.optionalValue(for: "missing") == nil)
        #expect(list.optionalValue(for: "json") == "a.json")
    }

    @Test func rejectsMissingSubcommand() {
        #expect(throws: ArgumentList.Failure.missingSubcommand) { try ArgumentList([]) }
        #expect(throws: ArgumentList.Failure.missingSubcommand) { try ArgumentList(["--json", "a"]) }
    }

    @Test func rejectsOptionWithoutValue() {
        #expect(throws: ArgumentList.Failure.missingValue("json")) { try ArgumentList(["coverage", "--json"]) }
    }

    @Test func rejectsStrayPositionalArgument() {
        #expect(throws: ArgumentList.Failure.unexpected("oops")) { try ArgumentList(["coverage", "oops"]) }
    }

    @Test func requiredValueThrowsWhenAbsent() throws {
        let list = try ArgumentList(["coverage"])
        #expect(throws: ArgumentList.Failure.missingOption("json")) { try list.value(for: "json") }
    }

    @Test func failuresDescribeThemselves() {
        #expect(ArgumentList.Failure.missingSubcommand.description == "missing subcommand")
        #expect(ArgumentList.Failure.missingValue("a").description == "option --a needs a value")
        #expect(ArgumentList.Failure.missingOption("a").description == "missing required option --a")
        #expect(ArgumentList.Failure.unexpected("z").description == "unexpected argument 'z'")
    }
}

@Suite struct CommandLineToolTests {
    let fullyCovered = CoverageFixtures.json(files: [.init(name: "/p/Sources/A/a.swift")])

    @Test func printsUsageForBadArguments() {
        let fake = FakeEnvironment()
        #expect(CommandLineTool.run([], environment: fake.environment) == 2)
        #expect(fake.lines == ["error: missing subcommand", CommandLineTool.usage])
    }

    @Test func rejectsUnknownSubcommand() {
        let fake = FakeEnvironment()
        #expect(CommandLineTool.run(["frobnicate"], environment: fake.environment) == 2)
        #expect(fake.lines == ["error: unknown subcommand 'frobnicate'", CommandLineTool.usage])
    }

    @Test func coveragePassesAndSummarises() {
        let fake = FakeEnvironment()
        fake.files["c.json"] = fullyCovered
        fake.directories["/p/Sources"] = ["/p/Sources/A/a.swift", "/p/Sources/App/main.swift"]
        let status = CommandLineTool.run(
            ["coverage", "--json", "c.json", "--sources", "/p/Sources", "--exclude", "App/main.swift"],
            environment: fake.environment
        )
        #expect(status == 0)
        #expect(fake.lines == ["Coverage gate: PASS (1 files, 100% lines/functions/regions)"])
    }

    @Test func coverageFailsAndListsProblems() {
        let fake = FakeEnvironment()
        let file = "/p/Sources/A/a.swift"
        fake.files["c.json"] = CoverageFixtures.json(
            files: [.init(name: file, lines: (2, 1))],
            functions: [.init(file: file, regions: [[4, 2, 4, 3, 0, 0]])]
        )
        fake.directories["/p/Sources"] = [file]
        let status = CommandLineTool.run(["coverage", "--json", "c.json", "--sources", "/p/Sources"], environment: fake.environment)
        #expect(status == 1)
        #expect(fake.lines == [
            "Coverage gate: FAIL",
            "  A/a.swift: lines 1/2",
            "Uncovered regions:",
            "  A/a.swift:4:2",
        ])
    }

    @Test func coverageReportsUnreadableInput() {
        let fake = FakeEnvironment()
        let status = CommandLineTool.run(["coverage", "--json", "nope.json", "--sources", "/p/Sources"], environment: fake.environment)
        #expect(status == 2)
        #expect(fake.lines.count == 1)
        #expect(fake.lines[0].hasPrefix("error: "))
    }

    @Test func coverageReportsMissingOption() {
        let fake = FakeEnvironment()
        let status = CommandLineTool.run(["coverage", "--sources", "/p"], environment: fake.environment)
        #expect(status == 2)
        #expect(fake.lines == ["error: missing required option --json", CommandLineTool.usage])
    }
}

@Suite struct LiveEnvironmentTests {
    @Test func readsFilesAndListsSwiftSourcesRecursively() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("qk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("A/B")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("top.swift"))
        try Data("y".utf8).write(to: nested.appendingPathComponent("deep.swift"))
        try Data("z".utf8).write(to: nested.appendingPathComponent("notes.md"))

        let live = ToolEnvironment.live
        let files = try live.swiftFiles(root.path)
        #expect(files == [nested.appendingPathComponent("deep.swift").path, root.appendingPathComponent("top.swift").path].sorted())
        #expect(try live.readFile(root.appendingPathComponent("top.swift").path) == Data("x".utf8))
        live.output("live output smoke test")
    }

    @Test func listingMissingDirectoryThrows() {
        #expect(throws: (any Error).self) { try ToolEnvironment.live.swiftFiles("/definitely/not/here-\(UUID().uuidString)") }
    }
}
