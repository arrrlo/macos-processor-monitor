import Foundation
@testable import QualityKit

/// Builds llvm-cov export JSON documents for tests.
enum CoverageFixtures {
    struct FileSpec {
        var name: String
        var lines: (count: Int, covered: Int) = (10, 10)
        var functions: (count: Int, covered: Int) = (2, 2)
        var regions: (count: Int, covered: Int) = (4, 4)
    }

    struct FunctionSpec {
        var name: String = "f"
        var file: String
        /// [lineStart, colStart, lineEnd, colEnd, count, kind]
        var regions: [[Int]]
    }

    static func json(files: [FileSpec], functions: [FunctionSpec] = []) -> Data {
        let fileObjects: [[String: Any]] = files.map { file in
            [
                "filename": file.name,
                "segments": [],
                "summary": [
                    "lines": summary(file.lines),
                    "functions": summary(file.functions),
                    "regions": summary(file.regions),
                ],
            ]
        }
        let functionObjects: [[String: Any]] = functions.map { function in
            [
                "name": function.name,
                "count": 1,
                "filenames": [function.file],
                "regions": function.regions.map { r in [r[0], r[1], r[2], r[3], r[4], 0, 0, r[5]] },
            ]
        }
        let document: [String: Any] = [
            "type": "llvm.coverage.json.export",
            "version": "2.0.1",
            "data": [["files": fileObjects, "functions": functionObjects]],
        ]
        return try! JSONSerialization.data(withJSONObject: document)
    }

    private static func summary(_ value: (count: Int, covered: Int)) -> [String: Int] {
        ["count": value.count, "covered": value.covered]
    }
}
