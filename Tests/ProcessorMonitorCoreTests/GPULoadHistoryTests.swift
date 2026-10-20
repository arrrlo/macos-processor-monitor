import Testing
@testable import ProcessorMonitorCore

@Suite struct GPULoadHistoryTests {
    @Test func keepsReadingsOldestFirst() {
        let history = GPULoadHistory().appending(0.1).appending(0.5)
        #expect(history.values == [0.1, 0.5])
        #expect(GPULoadHistory().values.isEmpty)
    }

    /// 30 readings are a minute at the default 2 s interval.
    @Test func dropsTheOldestBeyondThirty() {
        #expect(GPULoadHistory.capacity == 30)
        let history = (1...32).reduce(GPULoadHistory()) { $0.appending(Double($1)) }
        #expect(history.values == (3...32).map(Double.init))
    }
}
