/// Entry point shared by `pmtools` and the tests. Exit codes: 0 pass, 1 gate failed, 2 usage/input error.
public enum CommandLineTool {
    public static let usage = """
    usage: pmtools coverage --json <codecov.json> --sources <dir> [--exclude <relative path>]...
           pmtools crap --json <codecov.json> --sources <dir> [--exclude <relative path>]... [--max 16]
    """

    public static func run(_ arguments: [String], environment: ToolEnvironment) -> Int32 {
        do {
            let list = try ArgumentList(arguments)
            switch list.subcommand {
            case "coverage":
                return try runCoverage(list, environment: environment)
            case "crap":
                return try runCrap(list, environment: environment)
            default:
                environment.output("error: unknown subcommand '\(list.subcommand)'")
                environment.output(usage)
                return 2
            }
        } catch let failure as ArgumentList.Failure {
            environment.output("error: \(failure.description)")
            environment.output(usage)
            return 2
        } catch {
            environment.output("error: \(error)")
            return 2
        }
    }

    private static func runCoverage(_ list: ArgumentList, environment: ToolEnvironment) throws -> Int32 {
        let export = try CoverageExport.decode(from: environment.readFile(list.value(for: "json")))
        let sources = try list.value(for: "sources")
        let gate = CoverageGate(sourceRoot: sources, excludedFiles: Set(list.values(for: "exclude")))
        let files = try environment.swiftFiles(sources)
        let result = gate.evaluate(export, sourceFiles: files)
        guard result.passed else {
            environment.output("Coverage gate: FAIL")
            result.failures.forEach { environment.output("  \($0)") }
            environment.output("Uncovered regions:")
            result.uncoveredRegions.forEach { environment.output("  \($0)") }
            return 1
        }
        let checked = files.compactMap(gate.relativePath).filter { !gate.excludedFiles.contains($0) }.count
        environment.output("Coverage gate: PASS (\(checked) files, 100% lines/functions/regions)")
        return 0
    }

    private static func runCrap(_ list: ArgumentList, environment: ToolEnvironment) throws -> Int32 {
        let maximum = try list.intValue(for: "max", default: 16)
        let export = try CoverageExport.decode(from: environment.readFile(list.value(for: "json")))
        let sources = try list.value(for: "sources")
        let root = SourceRoot(sources)
        let excluded = Set(list.values(for: "exclude"))
        var units: [CodeUnit] = []
        for file in try environment.swiftFiles(sources) where !excluded.contains(root.display(file)) {
            let source = String(decoding: try environment.readFile(file), as: UTF8.self)
            units += ComplexityAnalyzer.units(in: source, file: file)
        }
        let report = CrapAnalysis.report(
            units: units,
            regions: export.functions.flatMap(\.regions),
            maximum: maximum,
            sourceRoot: sources
        )
        guard report.offenders.isEmpty else {
            environment.output("CRAP gate: FAIL (\(report.offenders.count) of \(report.unitCount) functions above \(maximum))")
            report.offenders.map(report.describe).forEach { environment.output("  \($0)") }
            return 1
        }
        environment.output("CRAP gate: PASS (\(report.unitCount) functions, max allowed \(maximum))")
        if report.unitCount > 0 {
            environment.output("Highest scores:")
            report.lines(limit: 5).forEach { environment.output("  \($0)") }
        }
        return 0
    }
}
