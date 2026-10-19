import Testing
@testable import QualityKit

@Suite struct ComplexityAnalyzerTests {
    func units(_ source: String) -> [CodeUnit] {
        ComplexityAnalyzer.units(in: source, file: "f.swift")
    }

    func complexity(_ source: String) -> Int? {
        units(source).first?.complexity
    }

    @Test func straightLineFunctionHasComplexityOne() {
        #expect(complexity("func f() { let a = 1; print(a) }") == 1)
    }

    @Test func countsBranchesAndLoops() {
        let source = """
        func f(_ x: Int) {
            if x > 0 { } else if x < 0 { } else { }
            guard x != 3 else { return }
            for _ in 0..<x { }
            while false { }
            repeat { } while false
        }
        """
        #expect(complexity(source) == 7)
    }

    @Test func countsExtraConditionsInConditionLists() {
        #expect(complexity("func f(a: Int?, b: Bool) { if let a, b, a > 1 { } }") == 4)
        #expect(complexity("func f(a: Int?) { guard let a, a > 0 else { return } }") == 3)
        #expect(complexity("func f(a: Bool, b: Bool) { while a, b { } }") == 3)
    }

    @Test func countsSwitchCasesButNotDefault() {
        let source = """
        func f(_ x: Int) -> Int {
            switch x {
            case 0, 1: return 0
            case 2: return 1
            default: return 2
            }
        }
        """
        #expect(complexity(source) == 3)
    }

    @Test func countsCatchClauses() {
        let source = """
        func f() {
            do { try g() } catch is CancellationError { } catch { }
        }
        """
        #expect(complexity(source) == 3)
    }

    @Test func countsShortCircuitAndNilCoalescingAndTernary() {
        #expect(complexity("func f(a: Bool, b: Bool, c: Int?) -> Int { a && b || a ? (c ?? 0) : 1 }") == 5)
    }

    @Test func ignoresOtherOperators() {
        #expect(complexity("func f(a: Int) -> Int { a + a * 2 == 4 ? 1 : 0 }") == 2)
    }

    @Test func closuresCountTowardTheEnclosingUnit() {
        let source = """
        func f(_ xs: [Int]) -> [Int] {
            xs.map { $0 > 0 ? $0 : 0 }.filter { x in
                if x == 1 { return false }
                return true
            }
        }
        """
        let found = units(source)
        #expect(found.count == 1)
        #expect(found[0].complexity == 3)
    }

    @Test func findsEveryKindOfUnitWithNamesAndRanges() {
        let source = """
        struct S {
            let stored = 1
            static let made = { (x: Int) in x > 0 ? 1 : 2 }(3)
            var computed: Int { stored > 0 ? 1 : 0 }
            var explicit: Int {
                get { stored }
                set { if newValue > 0 { } }
            }
            var noBody: Int { get }
            subscript(i: Int) -> Int { i }
            init() { }
            deinit { }
            func method() { }
        }
        func free() { }
        let global = 2
        """
        let found = units(source).map { "\($0.name)@\($0.startLine)-\($0.endLine)=\($0.complexity)" }
        #expect(found == [
            "S.stored@2-2=1",
            "S.made@3-3=2",
            "S.computed@4-4=2",
            "S.explicit.get@6-6=1",
            "S.explicit.set@7-7=2",
            "S.subscript@10-10=1",
            "S.init@11-11=1",
            "S.deinit@12-12=1",
            "S.method@13-13=1",
            "free@15-15=1",
            "global@16-16=1",
        ])
    }

    @Test func protocolRequirementsAndLocalVariablesAreNotUnits() {
        let source = """
        protocol P { func f(); var v: Int { get } }
        func g() { let local = 1; func nested() { if true { } }; _ = local }
        enum E { case a; case b(Int) }
        extension E { func h() -> Bool { self == .a } }
        """
        let found = units(source).map { "\($0.name)=\($0.complexity)" }
        #expect(found == ["g=2", "E.h=1"])
    }

    @Test func namesMembersOfNestedTypesAndExtensions() {
        let source = """
        enum Outer { struct Inner { func f() { } } }
        extension Outer.Inner { func g() { } }
        actor A { func h() { } }
        class C { func i() { } }
        """
        #expect(units(source).map(\.name) == ["Outer.Inner.f", "Outer.Inner.g", "A.h", "C.i"])
    }

    @Test func multipleBindingsInOneDeclarationAreSeparateUnits() {
        let found = units("struct S { var a = 1, b = true ? 1 : 2 }")
        #expect(found.map(\.name) == ["S.a", "S.b"])
        #expect(found.map(\.complexity) == [1, 2])
    }

    @Test func tuplePatternBindingIsNamedByItsPattern() {
        #expect(units("let (a, b) = (1, 2)").map(\.name) == ["(a, b)"])
    }

    @Test func recordsColumnsForRangeMatching() throws {
        let unit = try #require(units("  func f() {\n  }").first)
        #expect(unit.startLine == 1)
        #expect(unit.startColumn == 3)
        #expect(unit.endLine == 2)
        #expect(unit.endColumn == 4)
        #expect(unit.file == "f.swift")
    }
}
