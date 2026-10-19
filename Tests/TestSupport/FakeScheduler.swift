import Foundation
import ProcessorMonitorCore

/// A manual clock: nothing runs until the test advances time.
public final class FakeScheduler: Scheduling, @unchecked Sendable {
    public final class Task: Cancellable, @unchecked Sendable {
        public fileprivate(set) var due: Double
        public let interval: Double?
        let action: @Sendable () -> Void
        public private(set) var isCancelled = false

        init(due: Double, interval: Double?, action: @escaping @Sendable () -> Void) {
            self.due = due
            self.interval = interval
            self.action = action
        }

        public func cancel() {
            isCancelled = true
        }
    }

    public private(set) var now: Double = 0
    private var tasks: [Task] = []

    public init() {}

    /// Scheduled and not cancelled.
    public var pending: [Task] { tasks.filter { !$0.isCancelled } }

    public func schedule(after delay: Double, _ action: @escaping @Sendable () -> Void) -> any Cancellable {
        add(Task(due: now + delay, interval: nil, action: action))
    }

    public func scheduleRepeating(every interval: Double, _ action: @escaping @Sendable () -> Void) -> any Cancellable {
        add(Task(due: now + interval, interval: interval, action: action))
    }

    /// Runs everything due up to `now + seconds` in time order; repeating tasks fire once per interval.
    public func advance(by seconds: Double) {
        let end = now + seconds
        while let next = pending.filter({ $0.due <= end }).min(by: { $0.due < $1.due }) {
            now = next.due
            if let interval = next.interval {
                next.due += interval
            } else {
                tasks.removeAll { $0 === next }
            }
            next.action()
        }
        now = end
    }

    private func add(_ task: Task) -> Task {
        tasks.append(task)
        return task
    }
}
