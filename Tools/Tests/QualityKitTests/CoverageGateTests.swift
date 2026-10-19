import Foundation
import Testing
@testable import QualityKit

@Suite struct CoverageExportTests {
    @Test func decodesFilesAndFunctions() throws {
        let data = CoverageFixtures.json(
            files: [.init(name: "/p/Sources/A/a.swift", lines: (5, 4), functions: (2, 1), regions: (3, 2))],
            functions: [.init(file: "/p/Sources/A/a.swift", regions: [[3, 5, 4, 2, 0, 0]])]
        )
        let export = try CoverageExport.decode(from: data)
        #expect(export.files.count == 1)
        #expect(export.files[0].filename == "/p/Sources/A/a.swift")
        #expect(export.files[0].summary.lines == CoverageCount(count: 5, covered: 4))
        #expect(export.files[0].summary.functions == CoverageCount(count: 2, covered: 1))
        #expect(export.files[0].summary.regions == CoverageCount(count: 3, covered: 2))
        #expect(export.functions.count == 1)
        #expect(export.functions[0].regions == [
            CoverageRegion(file: "/p/Sources/A/a.swift", lineStart: 3, columnStart: 5, lineEnd: 4, columnEnd: 2, executionCount: 0, kind: 0),
        ])
    }

    @Test func rejectsDocumentWithoutData() {
        let data = Data(#"{"type":"llvm.coverage.json.export","version":"2.0.1","data":[]}"#.utf8)
        #expect(throws: CoverageExport.DecodingFailure.noData) {
            try CoverageExport.decode(from: data)
        }
    }

    @Test func ignoresRegionsWithUnknownFileIndex() throws {
        let document = #"""
        {"data":[{"files":[],"functions":[{"name":"f","count":1,"filenames":["/a.swift"],"regions":[[1,1,2,2,0,7,0,0],[1,1,2,2,0,1,0,0]]}]}]}
        """#
        let export = try CoverageExport.decode(from: Data(document.utf8))
        #expect(export.functions[0].regions.isEmpty)
    }

    @Test func coverageCountIsCompleteOnlyWhenEverythingCovered() {
        #expect(CoverageCount(count: 3, covered: 3).isComplete)
        #expect(CoverageCount(count: 0, covered: 0).isComplete)
        #expect(!CoverageCount(count: 3, covered: 2).isComplete)
    }
}

@Suite struct CoverageGateTests {
    let root = "/p/Sources"

    @Test func passesWhenEveryFileIsFullyCovered() throws {
        let export = try CoverageExport.decode(from: CoverageFixtures.json(files: [
            .init(name: "/p/Sources/A/a.swift"),
            .init(name: "/p/Tests/ATests/aTests.swift", lines: (5, 1)),
        ]))
        let result = CoverageGate(sourceRoot: root).evaluate(export, sourceFiles: ["/p/Sources/A/a.swift"])
        #expect(result.failures.isEmpty)
        #expect(result.passed)
    }

    @Test func reportsEachIncompleteMetric() throws {
        let export = try CoverageExport.decode(from: CoverageFixtures.json(files: [
            .init(name: "/p/Sources/A/a.swift", lines: (10, 9), functions: (2, 1), regions: (4, 3)),
        ]))
        let result = CoverageGate(sourceRoot: root).evaluate(export, sourceFiles: ["/p/Sources/A/a.swift"])
        #expect(!result.passed)
        #expect(result.failures == [
            "A/a.swift: lines 9/10",
            "A/a.swift: functions 1/2",
            "A/a.swift: regions 3/4",
        ])
    }

    @Test func failsWhenSourceFileIsMissingFromExport() throws {
        let export = try CoverageExport.decode(from: CoverageFixtures.json(files: [.init(name: "/p/Sources/A/a.swift")]))
        let result = CoverageGate(sourceRoot: root).evaluate(
            export,
            sourceFiles: ["/p/Sources/A/a.swift", "/p/Sources/A/b.swift"]
        )
        #expect(result.failures == ["A/b.swift: missing from coverage data (not linked into any test target?)"])
    }

    @Test func excludedFilesAreNeitherRequiredNorChecked() throws {
        let export = try CoverageExport.decode(from: CoverageFixtures.json(files: [
            .init(name: "/p/Sources/App/main.swift", lines: (3, 0)),
        ]))
        let gate = CoverageGate(sourceRoot: root, excludedFiles: ["App/main.swift", "Helper/main.swift"])
        let result = gate.evaluate(export, sourceFiles: ["/p/Sources/App/main.swift", "/p/Sources/Helper/main.swift"])
        #expect(result.passed)
    }

    @Test func listsUncoveredCodeRegionsSortedAndDeduplicated() throws {
        let file = "/p/Sources/A/a.swift"
        let export = try CoverageExport.decode(from: CoverageFixtures.json(
            files: [.init(name: file, regions: (4, 2))],
            functions: [
                .init(name: "g", file: file, regions: [[9, 1, 9, 5, 0, 0], [3, 7, 3, 9, 0, 0]]),
                // Same region in another generic instantiation that did run: covered.
                .init(name: "g2", file: file, regions: [[9, 1, 9, 5, 2, 0], [3, 7, 3, 9, 0, 0]]),
                // Gap / skipped regions (kind != 0) are not code.
                .init(name: "h", file: file, regions: [[12, 1, 12, 5, 0, 2]]),
                // Regions outside the source root are ignored.
                .init(name: "t", file: "/p/Tests/x.swift", regions: [[1, 1, 1, 5, 0, 0]]),
            ]
        ))
        let result = CoverageGate(sourceRoot: root).evaluate(export, sourceFiles: [file])
        #expect(result.uncoveredRegions == ["A/a.swift:3:7"])
    }

    @Test func sortsUncoveredRegionsByFileThenLineThenColumn() throws {
        let a = "/p/Sources/A/a.swift"
        let b = "/p/Sources/B/b.swift"
        let export = try CoverageExport.decode(from: CoverageFixtures.json(
            files: [.init(name: a), .init(name: b)],
            functions: [
                .init(file: b, regions: [[1, 1, 1, 2, 0, 0]]),
                .init(file: a, regions: [[5, 9, 5, 10, 0, 0], [5, 2, 5, 3, 0, 0], [2, 4, 2, 5, 0, 0]]),
            ]
        ))
        let result = CoverageGate(sourceRoot: root).evaluate(export, sourceFiles: [a, b])
        #expect(result.uncoveredRegions == ["A/a.swift:2:4", "A/a.swift:5:2", "A/a.swift:5:9", "B/b.swift:1:1"])
    }

    @Test func acceptsSourceRootWithTrailingSlash() throws {
        let export = try CoverageExport.decode(from: CoverageFixtures.json(files: [.init(name: "/p/Sources/A/a.swift")]))
        let gate = CoverageGate(sourceRoot: "/p/Sources/")
        #expect(gate.sourceRoot == "/p/Sources")
        #expect(gate.evaluate(export, sourceFiles: ["/p/Sources/A/a.swift"]).passed)
    }
}
