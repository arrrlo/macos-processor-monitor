/// Requires 100% line, function and region coverage for every source file under `sourceRoot`.
public struct CoverageGate: Sendable {
    public struct Result: Equatable, Sendable {
        public let failures: [String]
        public let uncoveredRegions: [String]

        public var passed: Bool { failures.isEmpty }
    }

    public let root: SourceRoot
    /// Paths relative to `sourceRoot` that cannot run under tests (entry points).
    public let excludedFiles: Set<String>

    public init(sourceRoot: String, excludedFiles: Set<String> = []) {
        root = SourceRoot(sourceRoot)
        self.excludedFiles = excludedFiles
    }

    public var sourceRoot: String { root.path }

    public func evaluate(_ export: CoverageExport, sourceFiles: [String]) -> Result {
        var measured: [String: CoverageSummary] = [:]
        for file in export.files {
            guard let path = relativePath(file.filename) else { continue }
            measured[path] = file.summary
        }
        var failures: [String] = []
        for path in sourceFiles.compactMap(relativePath).sorted() where !excludedFiles.contains(path) {
            guard let summary = measured[path] else {
                failures.append("\(path): missing from coverage data (not linked into any test target?)")
                continue
            }
            failures += incompleteMetrics(summary).map { "\(path): \($0)" }
        }
        return Result(failures: failures, uncoveredRegions: uncoveredRegions(export))
    }

    private func incompleteMetrics(_ summary: CoverageSummary) -> [String] {
        let metrics = [("lines", summary.lines), ("functions", summary.functions), ("regions", summary.regions)]
        return metrics.filter { !$0.1.isComplete }.map { "\($0.0) \($0.1.covered)/\($0.1.count)" }
    }

    private func uncoveredRegions(_ export: CoverageExport) -> [String] {
        let codeRegions = export.functions.flatMap(\.regions).filter(\.isCode)
        let covered = Set(codeRegions.filter { $0.executionCount > 0 }.map(Location.init))
        let uncovered = Set(codeRegions.map(Location.init)).subtracting(covered)
        return uncovered
            .compactMap { location in relativePath(location.file).map { Location(file: $0, line: location.line, column: location.column) } }
            .filter { !excludedFiles.contains($0.file) }
            .sorted()
            .map(\.description)
    }

    func relativePath(_ path: String) -> String? {
        root.relative(path)
    }
}

private struct Location: Hashable, Comparable, CustomStringConvertible {
    let file: String
    let line: Int
    let column: Int

    init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }

    init(_ region: CoverageRegion) {
        self.init(file: region.file, line: region.lineStart, column: region.columnStart)
    }

    static func < (lhs: Location, rhs: Location) -> Bool {
        (lhs.file, lhs.line, lhs.column) < (rhs.file, rhs.line, rhs.column)
    }

    var description: String { "\(file):\(line):\(column)" }
}
