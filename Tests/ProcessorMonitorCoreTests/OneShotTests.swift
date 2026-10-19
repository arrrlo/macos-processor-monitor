import Testing
@testable import ProcessorMonitorCore

final class Values<T>: @unchecked Sendable {
    var all: [T] = []
}

@Suite struct OneShotTests {
    @Test func deliversOnlyTheFirstValue() {
        let received = Values<Int>()
        let once = OneShot<Int> { received.all.append($0) }
        #expect(once.fire(1))
        #expect(!once.fire(2))
        #expect(received.all == [1])
    }
}
