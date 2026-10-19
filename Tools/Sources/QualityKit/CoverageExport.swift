import Foundation

/// Covered/total pair from an llvm-cov summary.
public struct CoverageCount: Equatable, Sendable, Decodable {
    public let count: Int
    public let covered: Int

    public init(count: Int, covered: Int) {
        self.count = count
        self.covered = covered
    }

    public var isComplete: Bool { covered == count }
}

public struct CoverageSummary: Equatable, Sendable, Decodable {
    public let lines: CoverageCount
    public let functions: CoverageCount
    public let regions: CoverageCount
}

public struct CoverageFile: Equatable, Sendable, Decodable {
    public let filename: String
    public let summary: CoverageSummary
}

/// One mapping region of a function, already resolved to its file.
public struct CoverageRegion: Equatable, Hashable, Sendable {
    public let file: String
    public let lineStart: Int
    public let columnStart: Int
    public let lineEnd: Int
    public let columnEnd: Int
    public let executionCount: Int
    /// 0 = code region; other kinds (expansion, skipped, gap, branch) are not executable code.
    public let kind: Int

    public var isCode: Bool { kind == 0 }
}

public struct CoverageFunction: Equatable, Sendable {
    public let name: String
    public let regions: [CoverageRegion]
}

/// The subset of `llvm-cov export` JSON the quality gates need.
public struct CoverageExport: Sendable {
    public enum DecodingFailure: Error, Equatable {
        case noData
    }

    public let files: [CoverageFile]
    public let functions: [CoverageFunction]

    public static func decode(from data: Data) throws -> CoverageExport {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard let payload = document.data.first else { throw DecodingFailure.noData }
        return CoverageExport(files: payload.files, functions: payload.functions.map(\.resolved))
    }

    private struct Document: Decodable {
        let data: [Payload]
    }

    private struct Payload: Decodable {
        let files: [CoverageFile]
        let functions: [RawFunction]
    }

    private struct RawFunction: Decodable {
        let name: String
        let filenames: [String]
        let regions: [[Int]]

        var resolved: CoverageFunction {
            let regions = regions.compactMap { raw -> CoverageRegion? in
                let fileIndex = raw[5]
                guard fileIndex < filenames.count else { return nil }
                return CoverageRegion(
                    file: filenames[fileIndex],
                    lineStart: raw[0],
                    columnStart: raw[1],
                    lineEnd: raw[2],
                    columnEnd: raw[3],
                    executionCount: raw[4],
                    kind: raw[7]
                )
            }
            return CoverageFunction(name: name, regions: regions)
        }
    }
}
