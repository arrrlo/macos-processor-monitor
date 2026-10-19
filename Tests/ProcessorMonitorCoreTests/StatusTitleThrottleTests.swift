import Testing
@testable import ProcessorMonitorCore

@Suite struct StatusTitleThrottleTests {
    /// Feeds (load, temperature, time) readings in order and returns which ones were shown.
    func decisions(_ readings: [(Double?, Double?, Double)]) -> [Bool] {
        var throttle = StatusTitleThrottle()
        return readings.map { throttle.shouldShow(load: $0.0, temperature: $0.1, at: $0.2) }
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

    @Test func readingsAppearingOrDisappearingAreShownAtOnce() {
        let readings: [(Double?, Double?, Double)] = [(nil, nil, 0), (nil, nil, 1), (0.2, nil, 2), (0.2, 50, 3), (nil, 50, 4), (nil, nil, 5)]
        #expect(decisions(readings) == [true, false, true, true, true, true])
    }
}
