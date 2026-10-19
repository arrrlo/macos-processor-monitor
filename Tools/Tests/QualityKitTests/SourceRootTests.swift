import Testing
@testable import QualityKit

@Suite struct SourceRootTests {
    @Test func stripsTrailingSlash() {
        #expect(SourceRoot("/p/Sources/").path == "/p/Sources")
        #expect(SourceRoot("/p/Sources").path == "/p/Sources")
    }

    @Test func relativeOnlyForFilesBelowTheRoot() {
        let root = SourceRoot("/p/Sources")
        #expect(root.relative("/p/Sources/A/a.swift") == "A/a.swift")
        #expect(root.relative("/p/SourcesX/a.swift") == nil)
        #expect(root.relative("/elsewhere/a.swift") == nil)
    }

    @Test func displayFallsBackToTheFullPath() {
        let root = SourceRoot("/p/Sources")
        #expect(root.display("/p/Sources/A/a.swift") == "A/a.swift")
        #expect(root.display("/elsewhere/a.swift") == "/elsewhere/a.swift")
    }
}
