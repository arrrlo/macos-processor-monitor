import Testing
import TestSupport
@testable import ProcessorMonitorCore

final class Published: @unchecked Sendable {
    var snapshots: [MonitorSnapshot] = []
    var last: MonitorSnapshot? { snapshots.last }
}

@Suite struct SamplingEngineTests {
    let topology = CPUTopology(clusters: [CPUCluster(name: "Super", coreIndices: [0])])
    let warm = TemperatureSummary(average: 50, maximum: 55, sensorCount: 2)
    let hot = TemperatureSummary(average: 80, maximum: 90, sensorCount: 2)
    let result = TopProcessesResult(processes: [ProcessUsage(pid: 1, name: "a", cpuPercent: 5)], scope: .allProcesses)

    func makeEngine(_ sources: FakeSources, _ scheduler: FakeScheduler, interval: Double = 2, published: Published) -> SamplingEngine {
        SamplingEngine(
            sources: SamplingEngine.Sources(
                cpuTicks: sources.readTicks,
                temperature: sources.readTemperature,
                topProcesses: sources.processes,
                topology: topology
            ),
            scheduler: scheduler,
            interval: interval,
            publish: { published.snapshots.append($0) }
        )
    }

    @Test func startPublishesTemperatureAtOnceAndLoadAfterTheFirstTick() throws {
        let sources = FakeSources()
        sources.ticks = FakeSources.ticks(busy: [25])
        sources.temperatures = [warm]
        let scheduler = FakeScheduler()
        let published = Published()
        let engine = makeEngine(sources, scheduler, published: published)

        engine.start()
        #expect(published.last == MonitorSnapshot(load: nil, clusters: [], temperature: warm, topProcesses: nil))

        scheduler.advance(by: 2)
        let snapshot = try #require(published.last)
        #expect(snapshot.load?.overall.total == 0.25)
        #expect(snapshot.clusters == [ClusterLoad(name: "Super", average: 0.25, cores: [CoreLoad(index: 0, load: 0.25)])])
        #expect(engine.isRunning)
    }

    @Test func readsTemperatureAtMostEveryFourSeconds() {
        let sources = FakeSources()
        sources.ticks = FakeSources.ticks(busy: [1, 2, 3, 4, 5, 6, 7, 8])
        sources.temperatures = [warm, hot]
        let scheduler = FakeScheduler()
        let published = Published()
        let engine = makeEngine(sources, scheduler, interval: 1, published: published)

        engine.start()
        scheduler.advance(by: 3)
        #expect(sources.temperatureReads == 1)
        scheduler.advance(by: 1)
        #expect(sources.temperatureReads == 2)
        #expect(published.last?.temperature == hot)
        scheduler.advance(by: 4)
        #expect(sources.temperatureReads == 3)
    }

    @Test func slowIntervalsReadTemperatureEveryTick() {
        let sources = FakeSources()
        sources.ticks = FakeSources.ticks(busy: [1, 2])
        sources.temperatures = [warm]
        let scheduler = FakeScheduler()
        let engine = makeEngine(sources, scheduler, interval: 5, published: Published())
        engine.start()
        scheduler.advance(by: 10)
        #expect(sources.temperatureReads == 3)
    }

    @Test func missingTickSampleKeepsTheLastLoad() {
        let sources = FakeSources()
        sources.ticks = FakeSources.ticks(busy: [50]) + [nil] + [CPUTicksSample(cores: [CoreTicks(user: 150, system: 0, idle: 50, nice: 0)])]
        let scheduler = FakeScheduler()
        let published = Published()
        let engine = makeEngine(sources, scheduler, published: published)
        engine.start()
        scheduler.advance(by: 2)
        scheduler.advance(by: 2)
        #expect(published.last?.load?.overall.total == 0.5)
        // The next sample is measured against the last good one: +100 busy, +0 idle.
        scheduler.advance(by: 2)
        #expect(published.last?.load?.overall.total == 1)
    }

    @Test func processesAreOnlyRequestedWhileSomeoneLooks() {
        let sources = FakeSources()
        sources.ticks = FakeSources.ticks(busy: [1, 2, 3, 4, 5])
        let scheduler = FakeScheduler()
        let published = Published()
        let engine = makeEngine(sources, scheduler, published: published)
        engine.start()
        scheduler.advance(by: 4)
        #expect(sources.processes.requests.isEmpty)

        engine.setProcessDemand(true)
        #expect(sources.processes.requests == [10])
        // A tick while the request is in flight does not start another one.
        scheduler.advance(by: 2)
        #expect(sources.processes.requests.count == 1)

        sources.processes.complete(with: result)
        #expect(published.last?.topProcesses == result)
        scheduler.advance(by: 2)
        #expect(sources.processes.requests.count == 2)

        sources.processes.complete(with: result)
        engine.setProcessDemand(false)
        scheduler.advance(by: 4)
        #expect(sources.processes.requests.count == 2)
        #expect(published.last?.topProcesses == result)
    }

    @Test func intervalChangeReschedulesTheTimer() {
        let sources = FakeSources()
        sources.ticks = FakeSources.ticks(busy: [1, 2, 3])
        let scheduler = FakeScheduler()
        let engine = makeEngine(sources, scheduler, published: Published())
        engine.start()
        engine.setInterval(5)
        #expect(engine.interval == 5)
        #expect(scheduler.pending.count == 1)
        scheduler.advance(by: 4)
        #expect(sources.tickReads == 1)
        scheduler.advance(by: 1)
        #expect(sources.tickReads == 2)
    }

    @Test func intervalChangeWhileStoppedOnlyStoresIt() {
        let scheduler = FakeScheduler()
        let engine = makeEngine(FakeSources(), scheduler, published: Published())
        engine.setInterval(1)
        #expect(engine.interval == 1)
        #expect(scheduler.pending.isEmpty)
    }

    @Test func stopCancelsAndRestartTakesAFreshBaseline() {
        let sources = FakeSources()
        sources.ticks = FakeSources.ticks(busy: [10, 90, 90])
        let scheduler = FakeScheduler()
        let published = Published()
        let engine = makeEngine(sources, scheduler, published: published)
        engine.start()
        scheduler.advance(by: 2)
        engine.stop()
        #expect(!engine.isRunning)
        #expect(scheduler.pending.isEmpty)
        scheduler.advance(by: 10)
        #expect(sources.tickReads == 2)

        engine.start()
        #expect(sources.tickReads == 3)
        scheduler.advance(by: 2)
        #expect(published.last?.load?.overall.total == 0.9)
    }

    @Test func startTwiceAndStopTwiceAreHarmless() {
        let scheduler = FakeScheduler()
        let sources = FakeSources()
        let published = Published()
        let engine = makeEngine(sources, scheduler, published: published)
        engine.start()
        engine.start()
        #expect(scheduler.pending.count == 1)
        #expect(sources.tickReads == 1)
        #expect(sources.temperatureReads == 1)
        #expect(published.snapshots.count == 1)
        engine.stop()
        engine.stop()
        #expect(scheduler.pending.isEmpty)
    }

    @Test func processResultArrivingAfterDemandEndsIsStillShownNextTime() {
        let sources = FakeSources()
        let scheduler = FakeScheduler()
        let published = Published()
        let engine = makeEngine(sources, scheduler, published: published)
        engine.start()
        engine.setProcessDemand(true)
        engine.setProcessDemand(false)
        sources.processes.complete(with: result)
        #expect(published.last?.topProcesses == result)
    }

    @Test func emptySnapshot() {
        #expect(MonitorSnapshot.empty == MonitorSnapshot(load: nil, clusters: [], temperature: nil, topProcesses: nil))
    }
}
