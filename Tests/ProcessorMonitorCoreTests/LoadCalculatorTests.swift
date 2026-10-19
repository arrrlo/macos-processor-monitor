import Testing
@testable import ProcessorMonitorCore

@Suite struct LoadCalculatorTests {
    func sample(_ cores: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)]) -> CPUTicksSample {
        CPUTicksSample(cores: cores.map { CoreTicks(user: $0.user, system: $0.system, idle: $0.idle, nice: $0.nice) })
    }

    @Test func computesPerCoreAndOverallBreakdown() throws {
        let previous = sample([(100, 50, 850, 0), (0, 0, 0, 0)])
        let current = sample([(130, 60, 900, 10), (25, 25, 50, 0)])
        let load = try #require(LoadCalculator.load(from: previous, to: current))

        // core 0: user 30 + nice 10 = 40, system 10, idle 50 → 100 ticks
        #expect(load.cores[0] == LoadBreakdown(user: 0.4, system: 0.1, idle: 0.5))
        // core 1: 25 / 25 / 50
        #expect(load.cores[1] == LoadBreakdown(user: 0.25, system: 0.25, idle: 0.5))
        // overall: user 65, system 35, idle 100 → 200 ticks
        #expect(load.overall == LoadBreakdown(user: 0.325, system: 0.175, idle: 0.5))
        #expect(load.overall.total == 0.5)
    }

    @Test func coreWithoutElapsedTicksCountsAsIdle() throws {
        let same = sample([(10, 10, 10, 0)])
        let load = try #require(LoadCalculator.load(from: same, to: same))
        #expect(load.cores == [.idle])
        #expect(load.overall == .idle)
    }

    @Test func handlesThirtyTwoBitCounterWraparound() throws {
        let previous = sample([(UInt32.max - 9, 0, UInt32.max - 49, 0)])
        let current = sample([(10, 0, 50, 0)])
        let load = try #require(LoadCalculator.load(from: previous, to: current))
        // user advanced 20, idle advanced 100
        #expect(load.cores[0].user == 20.0 / 120.0)
        #expect(load.cores[0].idle == 100.0 / 120.0)
    }

    @Test func returnsNilWhenCoreCountChanges() {
        #expect(LoadCalculator.load(from: sample([(1, 1, 1, 1)]), to: sample([])) == nil)
    }

    @Test func returnsNilForEmptySamples() {
        #expect(LoadCalculator.load(from: sample([]), to: sample([])) == nil)
    }

    @Test func idleBreakdownIsAllIdle() {
        #expect(LoadBreakdown.idle == LoadBreakdown(user: 0, system: 0, idle: 1))
        #expect(LoadBreakdown.idle.total == 0)
    }
}
