import Foundation
import Testing
@testable import QualityKit

@Suite struct MutateCommandTests {
    let arguments = ["mutate", "--package", "/p", "--build", "build", "--test", "test", "--jobs", "1"]

    /// A package with one mutant per file; the targeted tests kill every mutant containing "!=".
    func makeWorld(killed: Bool = true) -> FakeMutationWorld {
        let world = FakeMutationWorld()
        world.setFile("/p/Sources/A/a.swift", "let a = x == y")
        world.setFile("/p/Sources/A/main.swift", "let m = x == y")
        world.setFile("/p/Sources/B/b.swift", "// mutation:disable-next-line\nlet b = x == y")
        world.setFile("/tmp/pmtools-mutation/p-0/Sources/A/a.swift", "let a = x == y")
        world.setFile("/tmp/pmtools-mutation/p-0/Sources/B/b.swift", "// mutation:disable-next-line\nlet b = x == y")
        world.respond = { command, directory, world in
            if command.hasPrefix("git diff") {
                return CommandResult(status: 0, timedOut: false, output: "Sources/B/b.swift\nREADME.md\n")
            }
            let mutated = [directory + "/Sources/A/a.swift", directory + "/Sources/B/b.swift"].contains { world.file($0)?.contains("!=") == true }
            let failing = killed && command.contains("--filter") && mutated
            return CommandResult(status: failing ? 1 : 0, timedOut: false, output: "")
        }
        return world
    }

    @Test func killsEveryMutantOutsideExcludedFiles() {
        let world = makeWorld()
        let status = CommandLineTool.run(arguments + ["--exclude", "Sources/A/main.swift"], environment: world.environment)
        #expect(status == 0)
        #expect(world.output.contains("warning: /p/Sources/B/b.swift:1: mutation:disable-next-line needs a reason"))
        #expect(world.output.contains("Found 2 mutants in 2 files"))
        #expect(world.output.contains("Mutation score: 100.0% of 2 valid mutants"))
    }

    @Test func reportsSurvivorsWithAFailingStatus() {
        let world = makeWorld(killed: false)
        let status = CommandLineTool.run(arguments + ["--file", "Sources/A/a.swift"], environment: world.environment)
        #expect(status == 1)
        #expect(world.output.contains("Found 1 mutants in 1 files"))
        #expect(world.output.last == "  Sources/A/a.swift:1:11 relational `==` → `!=`")
    }

    @Test func changedModeOnlyMutatesFilesThatDiffer() {
        let world = makeWorld()
        let status = CommandLineTool.run(arguments + ["--changed", "main"], environment: world.environment)
        #expect(status == 0)
        // New, untracked files count as changed too.
        #expect(world.commands.first?.command == "git diff --name-only 'main' -- Sources; git ls-files --others --exclude-standard -- Sources")
        #expect(world.output.contains("Found 1 mutants in 1 files"))
    }

    @Test func noMutantsIsAPass() {
        let world = makeWorld()
        let status = CommandLineTool.run(arguments + ["--file", "Sources/None.swift"], environment: world.environment)
        #expect(status == 0)
        #expect(world.output.contains("Mutation testing: 0 mutants — killed 0, timed out 0, survived 0, invalid 0"))
    }

    @Test func baselineFailureIsAnError() {
        let world = makeWorld()
        world.respond = { _, _, _ in CommandResult(status: 1, timedOut: false, output: "nope") }
        let status = CommandLineTool.run(arguments + ["--file", "Sources/A/a.swift"], environment: world.environment)
        #expect(status == 2)
        #expect(world.output.last == "error: baseline build or tests failed in a workspace:\nnope")
    }
}
