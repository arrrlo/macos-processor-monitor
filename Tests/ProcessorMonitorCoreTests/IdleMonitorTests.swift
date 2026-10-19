import Testing
import TestSupport
@testable import ProcessorMonitorCore

final class Counter: @unchecked Sendable {
    var value = 0
}

@Suite struct IdleMonitorTests {
    @Test func firesAfterTimeoutWithoutActivity() {
        let scheduler = FakeScheduler()
        let fired = Counter()
        let monitor = IdleMonitor(timeout: 30, scheduler: scheduler) { fired.value += 1 }
        monitor.activity()
        scheduler.advance(by: 29)
        #expect(fired.value == 0)
        scheduler.advance(by: 1)
        #expect(fired.value == 1)
    }

    @Test func activityPostponesTheTimeout() {
        let scheduler = FakeScheduler()
        let fired = Counter()
        let monitor = IdleMonitor(timeout: 30, scheduler: scheduler) { fired.value += 1 }
        monitor.activity()
        scheduler.advance(by: 20)
        monitor.activity()
        scheduler.advance(by: 20)
        #expect(fired.value == 0)
        #expect(scheduler.pending.count == 1)
        scheduler.advance(by: 10)
        #expect(fired.value == 1)
    }
}

@Suite struct FakeSchedulerTests {
    @Test func repeatingTasksFireEveryIntervalUntilCancelled() {
        let scheduler = FakeScheduler()
        let fired = Counter()
        let task = scheduler.scheduleRepeating(every: 2) { fired.value += 1 }
        scheduler.advance(by: 7)
        #expect(fired.value == 3)
        #expect(scheduler.now == 7)
        task.cancel()
        scheduler.advance(by: 10)
        #expect(fired.value == 3)
        #expect(scheduler.pending.isEmpty)
    }
}
