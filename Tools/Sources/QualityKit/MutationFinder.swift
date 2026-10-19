import Foundation
import SwiftParser
import SwiftSyntax

/// One small change to the source that a good test suite should notice.
public struct Mutant: Equatable, Sendable {
    public let file: String
    public let line: Int
    public let column: Int
    /// Byte range of `original` in the unmodified file.
    public let utf8Range: Range<Int>
    public let original: String
    public let replacement: String
    public let operatorName: String

    public init(file: String, line: Int, column: Int, utf8Range: Range<Int>, original: String, replacement: String, operatorName: String) {
        self.file = file
        self.line = line
        self.column = column
        self.utf8Range = utf8Range
        self.original = original
        self.replacement = replacement
        self.operatorName = operatorName
    }

    public func apply(to source: String) -> String {
        var bytes = Array(source.utf8)
        bytes.replaceSubrange(utf8Range, with: Array(replacement.utf8))
        return String(decoding: bytes, as: UTF8.self)
    }

    public func describe(root: SourceRoot) -> String {
        "\(root.display(file)):\(line):\(column) \(operatorName) `\(Self.shorten(original))` → `\(Self.shorten(replacement))`"
    }

    private static func shorten(_ text: String) -> String {
        text.count > 54 ? text.prefix(54) + "…" : text
    }

    /// Tests of the target the file belongs to (`Sources/<Target>/…` → `<Target>Tests`), run first
    /// because they are the most likely to kill the mutant quickly.
    public func testFilter(packageRoot: SourceRoot) -> String? {
        let components = packageRoot.display(file).split(separator: "/")
        guard components.count > 2, components[0] == "Sources" else { return nil }
        return "\(components[1])Tests"
    }
}

public struct MutationScan: Equatable, Sendable {
    public let mutants: [Mutant]
    public let warnings: [String]
}

/// Finds mutation points with SwiftSyntax. Operators:
/// relational (negated and boundary-shifted), logical, arithmetic and compound assignment swaps,
/// boolean literal flips, `!` removal, and removal of call statements whose result is unused.
/// A line is skipped when the line before contains `// mutation:disable-next-line <reason>`.
public enum MutationFinder {
    static let marker = "mutation:disable-next-line"

    public static func scan(_ source: String, file: String) -> MutationScan {
        let tree = Parser.parse(source: source)
        let collector = MutationCollector(file: file, converter: SourceLocationConverter(fileName: file, tree: tree))
        collector.walk(tree)
        let (suppressed, warnings) = suppressions(in: source, file: file)
        return MutationScan(mutants: collector.mutants.filter { !suppressed.contains($0.line) }, warnings: warnings)
    }

    private static func suppressions(in source: String, file: String) -> (Set<Int>, [String]) {
        var suppressed: Set<Int> = []
        var warnings: [String] = []
        for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            guard let range = line.range(of: marker) else { continue }
            let reason = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if reason.isEmpty {
                warnings.append("\(file):\(index + 1): \(marker) needs a reason")
            } else {
                suppressed.insert(index + 2)
            }
        }
        return (suppressed, warnings)
    }
}

private final class MutationCollector: SyntaxVisitor {
    private static let binaryReplacements: [String: (name: String, replacements: [String])] = [
        "<": ("relational", [">=", "<="]),
        "<=": ("relational", [">", "<"]),
        ">": ("relational", ["<=", ">="]),
        ">=": ("relational", ["<", ">"]),
        "==": ("relational", ["!="]),
        "!=": ("relational", ["=="]),
        "&&": ("logical", ["||"]),
        "||": ("logical", ["&&"]),
        "+": ("arithmetic", ["-"]),
        "-": ("arithmetic", ["+"]),
        "*": ("arithmetic", ["/"]),
        "/": ("arithmetic", ["*"]),
        "+=": ("arithmetic", ["-="]),
        "-=": ("arithmetic", ["+="]),
    ]

    private let file: String
    private let converter: SourceLocationConverter
    private(set) var mutants: [Mutant] = []

    init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if let entry = Self.binaryReplacements[node.operator.text] {
            for replacement in entry.replacements {
                add(node, replacement: replacement, name: entry.name)
            }
        }
        return .visitChildren
    }

    override func visit(_ node: BooleanLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        add(node, replacement: node.literal.text == "true" ? "false" : "true", name: "boolean")
        return .visitChildren
    }

    override func visit(_ node: PrefixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if node.operator.text == "!" {
            add(node, replacement: node.expression.trimmedDescription, name: "negation")
        }
        return .visitChildren
    }

    override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
        if let call = node.item.as(FunctionCallExprSyntax.self) {
            add(call, replacement: "", name: "removeCall")
        }
        return .visitChildren
    }

    private func add(_ node: some SyntaxProtocol, replacement: String, name: String) {
        let start = node.positionAfterSkippingLeadingTrivia
        let location = converter.location(for: start)
        mutants.append(Mutant(
            file: file,
            line: location.line,
            column: location.column,
            utf8Range: start.utf8Offset..<node.endPositionBeforeTrailingTrivia.utf8Offset,
            original: node.trimmedDescription,
            replacement: replacement,
            operatorName: name
        ))
    }
}
