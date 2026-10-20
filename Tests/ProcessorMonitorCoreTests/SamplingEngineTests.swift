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
                gpuLoad: sources.readGPULoad,
                gpuTemperature: sources.readGPUTemperature,
                topProcesses: sources.processes,
                gpuProcesses: sources.gpuProcesses,
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

    @Test func gpuLoadIsReadOnEveryTick() {
        let busy = GPULoad(device: 0.4, renderer: 0.3, tiler: 0.1)
        let idle = GPULoad(device: 0, renderer: 0, tiler: 0)
        let sources = FakeSources()
        sources.gpuLoads = [busy, idle, nil]
        let scheduler = FakeScheduler()
        let published = Published()
        let engine = makeEngine(sources, scheduler, published: published)

        engine.start()
        #expect(sources.gpuLoadReads == 0)
        #expect(published.last?.gpuLoad == nil)
        scheduler.advance(by: 2)
        #expect(published.last?.gpuLoad == busy)
        scheduler.advance(by: 2)
        #expect(published.last?.gpuLoad == idle)
        // A tick without CPU ticks still updates the GPU, and a failed read clears it.
        scheduler.advance(by: 2)
        #expect(published.last?.gpuLoad == nil)
        #expect(sources.gpuLoadReads == 3)
    }

    @Test func gpuTemperatureIsReadWithTheProcessorTemperature() {
        let cool = TemperatureSummary(average: 40, maximum: 41, sensorCount: 8)
        let sources = FakeSources()
        sources.ticks = FakeSources.ticks(busy: [1, 2, 3, 4, 5])
        sources.temperatures = [warm]
        sources.gpuTemperatures = [cool, hot]
        let scheduler = FakeScheduler()
        let published = Published()
        let engine = makeEngine(sources, scheduler, interval: 1, published: published)

        engine.start()
        #expect(sources.gpuTemperatureReads == 1)
        #expect(published.last?.gpuTemperature == cool)
        scheduler.advance(by: 3)
        #expect(sources.gpuTemperatureReads == 1)
        scheduler.advance(by: 1)
        #expect(sources.gpuTemperatureReads == 2)
        #expect(sources.temperatureReads == 2)
        #expect(published.last?.gpuTemperature == hot)
        #expect(published.last?.temperature == warm)
    }

    @Test func gpuHistoryCollectsEverySuccessfulRead() {
        let sources = FakeSources()
        sources.gpuLoads = [0.1, 0.2, nil, 0.4].map { $0.map { GPULoad(device: $0, renderer: 0, tiler: 0) } }
        let scheduler = FakeScheduler()
        let published = Published()
        let engine = makeEngine(sources, scheduler, published: published)
        engine.start()
        #expect(published.last?.gpuHistory.values == [])
        scheduler.advance(by: 8)
        #expect(published.last?.gpuHistory.values == [0.1, 0.2, 0.4])
    }

    /// A fresh start (display wake) or a new interval would otherwise draw a gap or mixed spacing.
    @Test func gpuHistoryRestartsWithTheEngineAndOnANewInterval() {
        let sources = FakeSources()
        sources.gpuLoads = [GPULoad(device: 0.3, renderer: 0, tiler: 0)]
        let scheduler = FakeScheduler()
        let published = Published()
        let engine = makeEngine(sources, scheduler, published: published)
        engine.start()
        scheduler.advance(by: 4)
        #expect(published.last?.gpuHistory.values == [0.3, 0.3])
        engine.stop()
        engine.start()
        #expect(published.last?.gpuHistory.values == [])
        scheduler.advance(by: 2)
        #expect(published.last?.gpuHistory.values == [0.3])
        engine.setInterval(1)
        scheduler.advance(by: 1)
        #expect(published.last?.gpuHistory.values == [0.3])
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

    /// The GPU list is only on the dashboard, so it has its own demand, separate from the menu's.
    @Test func gpuProcessesAreAnIndependentFeed() {
        let gpuResult = TopProcessesResult(processes: [ProcessUsage(pid: 405, name: "WindowServer", cpuPercent: 3)], scope: .allProcesses)
        let sources = FakeSources()
        let scheduler = FakeScheduler()
        let published = Published()
        let engine = makeEngine(sources, scheduler, published: published)
        engine.start()
        engine.setProcessDemand(true)
        scheduler.advance(by: 2)
        #expect(sources.gpuProcesses.requests.isEmpty)

        engine.setGPUProcessDemand(true)
        #expect(sources.gpuProcesses.requests == [10])
        #expect(sources.processes.requests == [10])
        // In flight: a tick does not ask again.
        scheduler.advance(by: 2)
        #expect(sources.gpuProcesses.requests.count == 1)

        sources.gpuProcesses.complete(with: gpuResult)
        #expect(published.last?.topGPUProcesses == gpuResult)
        #expect(published.last?.topProcesses == nil)
        scheduler.advance(by: 2)
        #expect(sources.gpuProcesses.requests.count == 2)

        sources.gpuProcesses.complete(with: gpuResult)
        engine.setGPUProcessDemand(false)
        scheduler.advance(by: 4)
        #expect(sources.gpuProcesses.requests.count == 2)
        sources.processes.complete(with: result)
        #expect(published.last?.topProcesses == result)
        #expect(published.last?.topGPUProcesses == gpuResult)
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
        #expect(MonitorSnapshot.empty.gpuLoad == nil)
        #expect(MonitorSnapshot.empty.gpuTemperature == nil)
        #expect(MonitorSnapshot.empty.gpuHistory == GPULoadHistory())
        #expect(MonitorSnapshot.empty.topGPUProcesses == nil)
    }
}
