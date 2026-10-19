import Foundation

/// Change Risk Anti-Patterns: `CC² × (1 − coverage)³ + CC`.
public enum CrapScore {
    public static func compute(complexity: Int, coverage: Double) -> Double {
        let cc = Double(complexity)
        let uncovered = 1 - coverage
        return cc * cc * uncovered * uncovered * uncovered + cc
    }
}

public struct CrapEntry: Equatable, Sendable {
    public let unit: CodeUnit
    public let coverage: Double
    public let score: Double
}

public struct CrapReport: Equatable, Sendable {
    /// Every unit, highest score first.
    public let worst: [CrapEntry]
    public let offenders: [CrapEntry]
    let root: SourceRoot

    public var unitCount: Int { worst.count }

    public func lines(limit: Int) -> [String] {
        worst.prefix(limit).map(describe)
    }

    func describe(_ entry: CrapEntry) -> String {
        let file = root.display(entry.unit.file)
        let percent = Int((entry.coverage * 100).rounded())
        let score = String(format: "%.1f", entry.score)
        return "\(file):\(entry.unit.startLine) \(entry.unit.name) CC=\(entry.unit.complexity) coverage=\(percent)% CRAP=\(score)"
    }
}

public enum CrapAnalysis {
    /// Fraction of distinct code regions starting inside the unit that executed at least once.
    /// A unit without any region (never compiled into the test binary) counts as uncovered.
    public static func coverage(of unit: CodeUnit, regions: [CoverageRegion]) -> Double {
        let start = (unit.startLine, unit.startColumn)
        let end = (unit.endLine, unit.endColumn)
        var executed: [RegionKey: Bool] = [:]
        for region in regions where region.isCode && region.file == unit.file {
            let position = (region.lineStart, region.columnStart)
            guard position >= start, position <= end else { continue }
            let key = RegionKey(region)
            executed[key] = executed[key, default: false] || region.executionCount > 0
        }
        guard !executed.isEmpty else { return 0 }
        return Double(executed.values.filter { $0 }.count) / Double(executed.count)
    }

    public static func report(units: [CodeUnit], regions: [CoverageRegion], maximum: Int, sourceRoot: String) -> CrapReport {
        let entries = units.map { unit in
            let coverage = coverage(of: unit, regions: regions)
            return CrapEntry(unit: unit, coverage: coverage, score: CrapScore.compute(complexity: unit.complexity, coverage: coverage))
        }
        let worst = entries.sorted { lhs, rhs in
            (-lhs.score, lhs.unit.file, lhs.unit.startLine) < (-rhs.score, rhs.unit.file, rhs.unit.startLine)
        }
        return CrapReport(
            worst: worst,
            offenders: worst.filter { $0.score > Double(maximum) },
            root: SourceRoot(sourceRoot)
        )
    }
}

private struct RegionKey: Hashable {
    let lineStart: Int
    let columnStart: Int
    let lineEnd: Int
    let columnEnd: Int

    init(_ region: CoverageRegion) {
        lineStart = region.lineStart
        columnStart = region.columnStart
        lineEnd = region.lineEnd
        columnEnd = region.columnEnd
    }
}
