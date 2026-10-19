import Testing
@testable import QualityKit

@Suite struct MutationFinderTests {
    func mutants(_ source: String) -> [String] {
        MutationFinder.scan(source, file: "/p/Sources/A/a.swift").mutants.map {
            "\($0.line):\($0.column) \($0.operatorName) \($0.original) -> \($0.replacement)"
        }
    }

    @Test func relationalOperatorsAreNegatedAndShiftedAtTheBoundary() {
        #expect(mutants("let a = x < y") == ["1:11 relational < -> >=", "1:11 relational < -> <="])
        #expect(mutants("let a = x <= y") == ["1:11 relational <= -> >", "1:11 relational <= -> <"])
        #expect(mutants("let a = x > y") == ["1:11 relational > -> <=", "1:11 relational > -> >="])
        #expect(mutants("let a = x >= y") == ["1:11 relational >= -> <", "1:11 relational >= -> >"])
        #expect(mutants("let a = x == y") == ["1:11 relational == -> !="])
        #expect(mutants("let a = x != y") == ["1:11 relational != -> =="])
    }

    @Test func logicalAndArithmeticOperatorsAreSwapped() {
        #expect(mutants("let a = x && y") == ["1:11 logical && -> ||"])
        #expect(mutants("let a = x || y") == ["1:11 logical || -> &&"])
        #expect(mutants("let a = x + y") == ["1:11 arithmetic + -> -"])
        #expect(mutants("let a = x - y") == ["1:11 arithmetic - -> +"])
        #expect(mutants("let a = x * y") == ["1:11 arithmetic * -> /"])
        #expect(mutants("let a = x / y") == ["1:11 arithmetic / -> *"])
        #expect(mutants("func f() { a += 1; b -= 1 }") == ["1:14 arithmetic += -> -=", "1:22 arithmetic -= -> +="])
    }

    @Test func booleanLiteralsAreFlippedAndNegationsRemoved() {
        #expect(mutants("let a = true") == ["1:9 boolean true -> false"])
        #expect(mutants("let a = false") == ["1:9 boolean false -> true"])
        #expect(mutants("let a = !b") == ["1:9 negation !b -> b"])
    }

    @Test func discardedCallsAreRemoved() {
        #expect(mutants("func f() {\n    g()\n    let x = h()\n    _ = i()\n}") == ["2:5 removeCall g() -> "])
        #expect(mutants("func f() { a.b.c() }") == ["1:12 removeCall a.b.c() -> "])
    }

    /// With warnings as errors, a statement-level initializer call can only be a result-builder
    /// component (a SwiftUI view), not a discarded side effect.
    @Test func resultBuilderComponentsAreNotRemoved() {
        let source = """
        var body: some View {
            VStack {
                Text("a").font(.headline)
                Card(model: m)
                Swift.print("x")
            }
        }
        """
        #expect(mutants(source) == ["5:9 removeCall Swift.print(\"x\") -> "])
    }

    @Test func otherOperatorsAreIgnored() {
        #expect(mutants("let r = 0..<n; let s = a ?? b; let t = -c; let u = a % b").isEmpty)
    }

    @Test func suppressedLinesAreSkipped() {
        let source = "// mutation:disable-next-line clamp makes < and <= equivalent\nlet a = x < y\nlet b = x == y"
        #expect(mutants(source) == ["3:11 relational == -> !="])
        #expect(MutationFinder.scan(source, file: "f").warnings.isEmpty)
    }

    @Test func suppressionWithoutReasonIsIgnoredWithAWarning() {
        let scan = MutationFinder.scan("let z = 1 // mutation:disable-next-line\nlet a = x == y", file: "/p/a.swift")
        #expect(scan.mutants.count == 1)
        #expect(scan.warnings == ["/p/a.swift:1: mutation:disable-next-line needs a reason"])
    }
}

@Suite struct MutantTests {
    let mutant = Mutant(
        file: "/p/Sources/A/a.swift", line: 1, column: 11, utf8Range: 10..<11,
        original: "<", replacement: ">=", operatorName: "relational"
    )

    @Test func applyingReplacesExactlyItsRange() {
        #expect(mutant.apply(to: "let a = x < y") == "let a = x >= y")
    }

    @Test func applyingRespectsMultibyteCharacters() {
        let source = "let é = x < y"
        let scanned = MutationFinder.scan(source, file: "f").mutants[0]
        #expect(scanned.apply(to: source) == "let é = x >= y")
    }

    @Test func describesItselfRelativeToARoot() {
        #expect(mutant.describe(root: SourceRoot("/p")) == "Sources/A/a.swift:1:11 relational `<` → `>=`")
        let long = Mutant(
            file: "/p/a.swift", line: 2, column: 1, utf8Range: 0..<1,
            original: "someObject.doSomethingVeryLong(with: argument, and: anotherArgument)", replacement: "",
            operatorName: "removeCall"
        )
        #expect(long.describe(root: SourceRoot("/p")) == "a.swift:2:1 removeCall `someObject.doSomethingVeryLong(with: argument, and: an…` → ``")
    }

    @Test func testFilterIsTheSourceTargetsTestTarget() {
        #expect(mutant.testFilter(packageRoot: SourceRoot("/p")) == "ATests")
        let outside = Mutant(file: "/p/Other/b.swift", line: 1, column: 1, utf8Range: 0..<1, original: "a", replacement: "b", operatorName: "x")
        #expect(outside.testFilter(packageRoot: SourceRoot("/p")) == nil)
    }
}
