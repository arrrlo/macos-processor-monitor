import SwiftParser
import SwiftSyntax

/// A function-like piece of code that CRAP is computed for.
public struct CodeUnit: Equatable, Sendable {
    public let name: String
    public let file: String
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int
    public let complexity: Int
}

/// Cyclomatic complexity per unit, following the rules documented in CLAUDE.md:
/// units are funcs, inits, deinits, subscripts, accessors and property initializers;
/// each `if`/`guard`/`while` (+1 per extra condition), `for`, `repeat`, non-default `case`,
/// `catch`, `&&`, `||`, `??` and ternary adds one; closures count toward their enclosing unit.
public enum ComplexityAnalyzer {
    public static func units(in source: String, file: String) -> [CodeUnit] {
        let tree = Parser.parse(source: source)
        let collector = UnitCollector(file: file, converter: SourceLocationConverter(fileName: file, tree: tree))
        collector.walk(tree)
        return collector.units
    }
}

private final class UnitCollector: SyntaxVisitor {
    private let file: String
    private let converter: SourceLocationConverter
    private var scope: [String] = []
    private(set) var units: [CodeUnit] = []

    init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: Scopes

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
    override func visitPost(_ node: StructDeclSyntax) { scope.removeLast() }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
    override func visitPost(_ node: ClassDeclSyntax) { scope.removeLast() }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
    override func visitPost(_ node: EnumDeclSyntax) { scope.removeLast() }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
    override func visitPost(_ node: ActorDeclSyntax) { scope.removeLast() }
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.extendedType.trimmedDescription) }
    override func visitPost(_ node: ExtensionDeclSyntax) { scope.removeLast() }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    private func enter(_ name: String) -> SyntaxVisitorContinueKind {
        scope.append(name)
        return .visitChildren
    }

    // MARK: Units

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.body != nil { record(node.name.text, node) }
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.body != nil { record("init", node) }
        return .skipChildren
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.body != nil { record("deinit", node) }
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        if let block = node.accessorBlock { recordAccessors("subscript", block, whole: Syntax(node)) }
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            let name = binding.pattern.trimmedDescription
            if let block = binding.accessorBlock {
                recordAccessors(name, block, whole: Syntax(binding))
            } else if binding.initializer != nil {
                record(name, binding)
            }
        }
        return .skipChildren
    }

    private func recordAccessors(_ name: String, _ block: AccessorBlockSyntax, whole: Syntax) {
        switch block.accessors {
        case .getter:
            record(name, whole)
        case .accessors(let accessors):
            for accessor in accessors where accessor.body != nil {
                record("\(name).\(accessor.accessorSpecifier.text)", accessor)
            }
        }
    }

    private func record(_ name: String, _ node: some SyntaxProtocol) {
        let start = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        let end = converter.location(for: node.endPositionBeforeTrailingTrivia)
        let counter = DecisionCounter(viewMode: .sourceAccurate)
        counter.walk(node)
        units.append(CodeUnit(
            name: (scope + [name]).joined(separator: "."),
            file: file,
            startLine: start.line,
            startColumn: start.column,
            endLine: end.line,
            endColumn: end.column,
            complexity: 1 + counter.decisions
        ))
    }
}

private final class DecisionCounter: SyntaxVisitor {
    private static let shortCircuitOperators: Set<String> = ["&&", "||", "??"]
    private(set) var decisions = 0

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind { add(node.conditions.count) }
    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind { add(node.conditions.count) }
    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind { add(node.conditions.count) }
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind { add(1) }
    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind { add(1) }
    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind { add(1) }
    // SwiftParser does not fold operators, so ternaries only appear in their unresolved form.
    override func visit(_ node: UnresolvedTernaryExprSyntax) -> SyntaxVisitorContinueKind { add(1) }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        if case .case = node.label { decisions += 1 }
        return .visitChildren
    }

    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if Self.shortCircuitOperators.contains(node.operator.text) { decisions += 1 }
        return .visitChildren
    }

    private func add(_ count: Int) -> SyntaxVisitorContinueKind {
        decisions += count
        return .visitChildren
    }
}
