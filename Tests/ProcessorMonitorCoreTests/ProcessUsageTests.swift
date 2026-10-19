import Testing
@testable import ProcessorMonitorCore

func process(_ pid: Int32, _ name: String, cpu: UInt64, start: UInt64 = 1) -> ProcessSample {
    ProcessSample(pid: pid, startTime: start, name: name, cpuTime: cpu)
}

@Suite struct ProcessCPUCalculatorTests {
    /// Apple Silicon: 125/3 ns per tick.
    let timebase = Timebase(numer: 125, denom: 3)

    @Test func percentOfOneCoreOverTheInterval() {
        // 1 s wall, 24_000_000 ticks × 125/3 = 1 s CPU → 100 %.
        let previous = ProcessSnapshot(timestamp: 0, processes: [process(1, "a", cpu: 0), process(2, "b", cpu: 100)])
        let current = ProcessSnapshot(timestamp: 1_000_000_000, processes: [process(1, "a", cpu: 24_000_000), process(2, "b", cpu: 12_000_100)])
        let usage = ProcessCPUCalculator.usage(previous: previous, current: current, timebase: timebase)
        #expect(usage == [ProcessUsage(pid: 1, name: "a", cpuPercent: 100), ProcessUsage(pid: 2, name: "b", cpuPercent: 50)])
    }

    @Test func skipsNewAndReusedPIDs() {
        let previous = ProcessSnapshot(timestamp: 0, processes: [process(1, "old", cpu: 0, start: 10)])
        let current = ProcessSnapshot(timestamp: 1_000_000_000, processes: [
            process(1, "reused", cpu: 5_000, start: 99),
            process(3, "new", cpu: 5_000),
        ])
        #expect(ProcessCPUCalculator.usage(previous: previous, current: current, timebase: timebase).isEmpty)
    }

    @Test func counterGoingBackwardsCountsAsZero() {
        let previous = ProcessSnapshot(timestamp: 0, processes: [process(1, "a", cpu: 500)])
        let current = ProcessSnapshot(timestamp: 1_000_000_000, processes: [process(1, "a", cpu: 100)])
        #expect(ProcessCPUCalculator.usage(previous: previous, current: current, timebase: timebase) == [ProcessUsage(pid: 1, name: "a", cpuPercent: 0)])
    }

    @Test func noElapsedTimeMeansNoUsage() {
        let snapshot = ProcessSnapshot(timestamp: 5, processes: [process(1, "a", cpu: 1)])
        #expect(ProcessCPUCalculator.usage(previous: snapshot, current: snapshot, timebase: timebase).isEmpty)
    }

    @Test func timebaseConvertsTicksToNanoseconds() {
        #expect(timebase.nanoseconds(3) == 125)
        #expect(Timebase(numer: 1, denom: 1).nanoseconds(7) == 7)
    }
}

@Suite struct TopProcessesTests {
    @Test func highestUsageFirstThenLowestPID() {
        let usage = [
            ProcessUsage(pid: 5, name: "e", cpuPercent: 1),
            ProcessUsage(pid: 2, name: "b", cpuPercent: 30),
            ProcessUsage(pid: 9, name: "i", cpuPercent: 30),
            ProcessUsage(pid: 1, name: "a", cpuPercent: 80),
        ]
        #expect(TopProcesses.select(usage, limit: 3).map(\.pid) == [1, 2, 9])
    }

    @Test func limitLargerThanInput() {
        #expect(TopProcesses.select([ProcessUsage(pid: 1, name: "a", cpuPercent: 0)], limit: 10).count == 1)
    }

    @Test func nonPositiveLimitSelectsNothing() {
        #expect(TopProcesses.select([ProcessUsage(pid: 1, name: "a", cpuPercent: 0)], limit: 0).isEmpty)
    }
}

/// Scripted snapshots and a fake clock for the sampler.
final class FakeProcessTable: @unchecked Sendable {
    var snapshots: [ProcessSnapshot]
    var sleeps: [UInt64] = []
    private(set) var taken = 0

    init(_ snapshots: [ProcessSnapshot]) {
        self.snapshots = snapshots
    }

    func next() -> ProcessSnapshot {
        defer { taken += 1 }
        return snapshots[taken]
    }
}

@Suite struct ProcessUsageSamplerTests {
    let timebase = Timebase(numer: 1, denom: 1)

    func snapshot(at time: UInt64, cpu: UInt64) -> ProcessSnapshot {
        ProcessSnapshot(timestamp: time, processes: [process(7, "p", cpu: cpu)])
    }

    func sampler(_ table: FakeProcessTable) -> ProcessUsageSampler {
        ProcessUsageSampler(
            timebase: timebase,
            minimumWindow: 250,
            maximumBaselineAge: 5_000,
            snapshot: table.next,
            sleep: { table.sleeps.append($0) }
        )
    }

    @Test func firstRequestMeasuresAShortWindow() {
        let table = FakeProcessTable([snapshot(at: 1_000, cpu: 0), snapshot(at: 1_250, cpu: 125)])
        let top = sampler(table).top(limit: 10)
        #expect(table.sleeps == [250])
        #expect(top == [ProcessUsage(pid: 7, name: "p", cpuPercent: 50)])
    }

    @Test func freshBaselineIsReusedWithoutWaiting() {
        let table = FakeProcessTable([
            snapshot(at: 1_000, cpu: 0), snapshot(at: 1_250, cpu: 0),
            snapshot(at: 3_250, cpu: 2_000),
        ])
        let sut = sampler(table)
        _ = sut.top(limit: 10)
        let top = sut.top(limit: 10)
        #expect(table.sleeps == [250])
        #expect(top == [ProcessUsage(pid: 7, name: "p", cpuPercent: 100)])
    }

    @Test func baselineYoungerThanTheWindowIsTopped() {
        let table = FakeProcessTable([
            snapshot(at: 1_000, cpu: 0), snapshot(at: 1_250, cpu: 0),
            snapshot(at: 1_300, cpu: 0), snapshot(at: 1_500, cpu: 250),
        ])
        let sut = sampler(table)
        _ = sut.top(limit: 10)
        let top = sut.top(limit: 10)
        #expect(table.sleeps == [250, 200])
        #expect(top == [ProcessUsage(pid: 7, name: "p", cpuPercent: 100)])
    }

    @Test func staleBaselineIsDiscarded() {
        let table = FakeProcessTable([
            snapshot(at: 1_000, cpu: 0), snapshot(at: 1_250, cpu: 0),
            snapshot(at: 9_000, cpu: 7_000), snapshot(at: 9_250, cpu: 7_250),
        ])
        let sut = sampler(table)
        _ = sut.top(limit: 10)
        let top = sut.top(limit: 10)
        #expect(table.sleeps == [250, 250])
        #expect(top == [ProcessUsage(pid: 7, name: "p", cpuPercent: 100)])
    }

    @Test func baselineExactlyAtTheMaximumAgeIsStillUsed() {
        let table = FakeProcessTable([
            snapshot(at: 0, cpu: 0), snapshot(at: 250, cpu: 0),
            snapshot(at: 5_250, cpu: 5_000),
        ])
        let sut = sampler(table)
        _ = sut.top(limit: 10)
        #expect(sut.top(limit: 10) == [ProcessUsage(pid: 7, name: "p", cpuPercent: 100)])
        #expect(table.sleeps == [250])
    }
}
