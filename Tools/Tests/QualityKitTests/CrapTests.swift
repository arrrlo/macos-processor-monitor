import Foundation
import Testing
@testable import QualityKit

@Suite struct CrapScoreTests {
    @Test func fullyCoveredScoreEqualsComplexity() {
        #expect(CrapScore.compute(complexity: 7, coverage: 1) == 7)
    }

    @Test func uncoveredScoreIsComplexitySquaredPlusComplexity() {
        #expect(CrapScore.compute(complexity: 3, coverage: 0) == 12)
    }

    @Test func partialCoverageFollowsTheFormula() {
        // 4² × (1 − 0.5)³ + 4 = 16 × 0.125 + 4 = 6
        #expect(CrapScore.compute(complexity: 4, coverage: 0.5) == 6)
    }
}

@Suite struct CrapAnalysisTests {
    let file = "/p/Sources/A/a.swift"

    func unit(_ name: String, lines: ClosedRange<Int>, complexity: Int, columns: (Int, Int) = (1, 2)) -> CodeUnit {
        CodeUnit(
            name: name, file: file,
            startLine: lines.lowerBound, startColumn: columns.0,
            endLine: lines.upperBound, endColumn: columns.1,
            complexity: complexity
        )
    }

    func region(_ line: Int, _ column: Int, count: Int, file: String? = nil, kind: Int = 0) -> CoverageRegion {
        CoverageRegion(
            file: file ?? self.file, lineStart: line, columnStart: column,
            lineEnd: line, columnEnd: column + 1, executionCount: count, kind: kind
        )
    }

    @Test func coverageIsFractionOfCodeRegionsInsideTheUnit() {
        let regions = [
            region(2, 5, count: 1),
            region(3, 5, count: 0),
            region(3, 5, count: 4), // same location, other instantiation ran
            region(4, 1, count: 0),
            region(5, 1, count: 0, kind: 2), // gap region: ignored
            region(9, 1, count: 0), // outside the unit
            region(3, 1, count: 0, file: "/p/Sources/B/b.swift"), // other file
        ]
        let coverage = CrapAnalysis.coverage(of: unit("f", lines: 2...5, complexity: 2), regions: regions)
        #expect(coverage == 2.0 / 3.0)
    }

    @Test func regionsMatchByColumnOnBoundaryLines() {
        let u = unit("f", lines: 3...3, complexity: 1, columns: (10, 20))
        #expect(CrapAnalysis.coverage(of: u, regions: [region(3, 9, count: 0), region(3, 12, count: 1), region(3, 21, count: 0)]) == 1)
        // Regions starting exactly on the unit's first or last position belong to it.
        #expect(CrapAnalysis.coverage(of: u, regions: [region(3, 10, count: 0), region(3, 12, count: 1)]) == 0.5)
        #expect(CrapAnalysis.coverage(of: u, regions: [region(3, 20, count: 0), region(3, 12, count: 1)]) == 0.5)
    }

    @Test func unitWithoutRegionsCountsAsUncovered() {
        #expect(CrapAnalysis.coverage(of: unit("f", lines: 1...2, complexity: 1), regions: []) == 0)
    }

    @Test func reportsOffendersAboveThresholdSortedWorstFirst() {
        let units = [
            unit("ok", lines: 1...3, complexity: 3),
            unit("bad", lines: 10...12, complexity: 5),
            unit("worse", lines: 20...22, complexity: 17),
        ]
        let regions = [region(2, 1, count: 1), region(11, 1, count: 0), region(21, 1, count: 1)]
        let report = CrapAnalysis.report(units: units, regions: regions, maximum: 16, sourceRoot: "/p/Sources")
        #expect(report.offenders.map(\.unit.name) == ["bad", "worse"])
        #expect(report.offenders.map(\.score) == [30, 17])
        #expect(report.worst.map(\.unit.name) == ["bad", "worse", "ok"])
        #expect(report.lines(limit: 2) == [
            "A/a.swift:10 bad CC=5 coverage=0% CRAP=30.0",
            "A/a.swift:20 worse CC=17 coverage=100% CRAP=17.0",
        ])
    }

    @Test func passesWhenEveryUnitIsWithinThreshold() {
        let report = CrapAnalysis.report(
            units: [unit("ok", lines: 1...3, complexity: 16)],
            regions: [region(2, 1, count: 1)],
            maximum: 16,
            sourceRoot: "/p/Sources/"
        )
        #expect(report.offenders.isEmpty)
        #expect(report.unitCount == 1)
        #expect(report.lines(limit: 5) == ["A/a.swift:1 ok CC=16 coverage=100% CRAP=16.0"])
    }
}

@Suite struct CrapCommandTests {
    @Test func passesForSimpleCoveredCode() {
        let fake = FakeEnvironment()
        let file = "/p/Sources/A/a.swift"
        fake.files[file] = Data("func f(_ a: Bool) -> Int {\n    a ? 1 : 0\n}\n".utf8)
        fake.files["c.json"] = CoverageFixtures.json(
            files: [.init(name: file)],
            functions: [.init(file: file, regions: [[1, 26, 3, 2, 3, 0]])]
        )
        fake.directories["/p/Sources"] = [file, "/p/Sources/App/main.swift"]
        let status = CommandLineTool.run(
            ["crap", "--json", "c.json", "--sources", "/p/Sources", "--max", "16", "--exclude", "App/main.swift"],
            environment: fake.environment
        )
        #expect(status == 0)
        #expect(fake.lines == [
            "CRAP gate: PASS (1 functions, max allowed 16)",
            "Highest scores:",
            "  A/a.swift:1 f CC=2 coverage=100% CRAP=2.0",
        ])
    }

    @Test func failsAndListsOffenders() {
        let fake = FakeEnvironment()
        let file = "/p/Sources/A/a.swift"
        fake.files[file] = Data("func f(_ a: Bool, _ b: Bool) {\n    if a && b { }\n}\n".utf8)
        fake.files["c.json"] = CoverageFixtures.json(files: [.init(name: file)])
        fake.directories["/p/Sources"] = [file]
        let status = CommandLineTool.run(["crap", "--json", "c.json", "--sources", "/p/Sources", "--max", "2"], environment: fake.environment)
        #expect(status == 1)
        #expect(fake.lines == [
            "CRAP gate: FAIL (1 of 1 functions above 2)",
            "  A/a.swift:1 f CC=3 coverage=0% CRAP=12.0",
        ])
    }

    @Test func defaultsMaximumToSixteenAndRejectsBadNumbers() {
        let fake = FakeEnvironment()
        fake.files["c.json"] = CoverageFixtures.json(files: [])
        fake.directories["/p/Sources"] = []
        #expect(CommandLineTool.run(["crap", "--json", "c.json", "--sources", "/p/Sources"], environment: fake.environment) == 0)
        #expect(fake.lines == ["CRAP gate: PASS (0 functions, max allowed 16)"])

        let bad = FakeEnvironment()
        bad.files["c.json"] = CoverageFixtures.json(files: [])
        bad.directories["/p/Sources"] = []
        #expect(CommandLineTool.run(["crap", "--json", "c.json", "--sources", "/p/Sources", "--max", "x"], environment: bad.environment) == 2)
        #expect(bad.lines == ["error: option --max needs a number", CommandLineTool.usage])
    }
}
