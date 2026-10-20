import Testing
@testable import ProcessorMonitorCore

@Suite struct StatusTitleThrottleTests {
    /// A snapshot carrying only what the title shows.
    func snapshot(load: Double?, temperature: Double?, gpuLoad: Double? = nil, gpuTemperature: Double? = nil) -> MonitorSnapshot {
        var snapshot = MonitorSnapshot.empty
        snapshot.load = load.map { CPULoad(overall: LoadBreakdown(user: $0, system: 0, idle: 1 - $0), cores: []) }
        snapshot.temperature = temperature.map { TemperatureSummary(average: $0, maximum: $0, sensorCount: 1) }
        snapshot.gpuLoad = gpuLoad.map { GPULoad(device: $0, renderer: 0, tiler: 0) }
        snapshot.gpuTemperature = gpuTemperature.map { TemperatureSummary(average: $0, maximum: $0, sensorCount: 1) }
        return snapshot
    }

    /// Feeds (load, temperature, time) readings in order and returns which ones were shown.
    func decisions(_ readings: [(Double?, Double?, Double)]) -> [Bool] {
        var throttle = StatusTitleThrottle()
        return readings.map { throttle.shouldShow(snapshot(load: $0.0, temperature: $0.1), at: $0.2) }
    }

    /// Feeds (GPU load, time) readings with a steady processor and returns which ones were shown.
    func gpuDecisions(_ readings: [(Double?, Double)]) -> [Bool] {
        var throttle = StatusTitleThrottle()
        return readings.map { throttle.shouldShow(snapshot(load: 0.2, temperature: 50, gpuLoad: $0.0), at: $0.1) }
    }

    @Test func firstReadingIsAlwaysShown() {
        #expect(decisions([(0.2, 50, 0)]) == [true])
    }

    @Test func smallChangesWaitUntilTheTitleIsTenSecondsOld() {
        // The clock restarts at the last title shown (t = 10).
        let readings: [(Double?, Double?, Double)] = [(0.20, 50, 0), (0.22, 51, 2), (0.18, 49, 9.9), (0.21, 50, 10), (0.21, 50, 19.9)]
        #expect(decisions(readings) == [true, false, false, true, false])
    }

    @Test func loadStepOfThreePointsIsShownAtOnce() {
        let readings: [(Double?, Double?, Double)] = [(0.20, 50, 0), (0.23, 50, 1), (0.20, 50, 2), (0.2299, 50, 3)]
        #expect(decisions(readings) == [true, true, true, false])
    }

    @Test func temperatureStepOfTwoDegreesIsShownAtOnce() {
        let readings: [(Double?, Double?, Double)] = [(0.20, 50, 0), (0.20, 52, 1), (0.20, 50, 2), (0.20, 51.99, 3)]
        #expect(decisions(readings) == [true, true, true, false])
    }

    /// GPU load flickers between 0% and about 25% from one tick to the next (window compositing),
    /// so only a 10-point move redraws at once.
    @Test func gpuLoadStepOfTenPointsIsShownAtOnce() {
        let readings: [(Double?, Double)] = [(0, 0), (0.1, 1), (0, 2), (0.0999, 3), (0.01, 9.9), (0.01, 12)]
        #expect(gpuDecisions(readings) == [true, true, true, false, false, true])
        #expect(StatusTitleThrottle.gpuLoadStep == 0.1)
    }

    @Test func gpuTemperatureStepOfTwoDegreesIsShownAtOnce() {
        var throttle = StatusTitleThrottle()
        let readings: [(Double?, Double)] = [(40, 0), (42, 1), (40, 2), (41.99, 3), (nil, 4)]
        let shown = readings.map { throttle.shouldShow(snapshot(load: 0.2, temperature: 50, gpuLoad: 0.05, gpuTemperature: $0.0), at: $0.1) }
        #expect(shown == [true, true, true, false, true])
    }

    @Test func readingsAppearingOrDisappearingAreShownAtOnce() {
        let readings: [(Double?, Double?, Double)] = [(nil, nil, 0), (nil, nil, 1), (0.2, nil, 2), (0.2, 50, 3), (nil, 50, 4), (nil, nil, 5)]
        #expect(decisions(readings) == [true, false, true, true, true, true])
        #expect(gpuDecisions([(nil, 0), (nil, 1), (0.1, 2), (nil, 3)]) == [true, false, true, true])
    }
}
