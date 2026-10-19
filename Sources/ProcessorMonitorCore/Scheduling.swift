import os

public protocol Cancellable: Sendable {
    func cancel()
}

/// Timer abstraction so all timing logic can be tested with a manual clock.
public protocol Scheduling: Sendable {
    /// Runs `action` once after `delay` seconds unless cancelled.
    func schedule(after delay: Double, _ action: @escaping @Sendable () -> Void) -> any Cancellable
    /// Runs `action` every `interval` seconds, first after one interval, until cancelled.
    func scheduleRepeating(every interval: Double, _ action: @escaping @Sendable () -> Void) -> any Cancellable
}

/// Calls `onIdle` once `timeout` seconds pass without `activity()`. The helper uses it to exit
/// when nobody asks for data, so it costs nothing while the menu and dashboard are closed.
public final class IdleMonitor: Sendable {
    private let timeout: Double
    private let scheduler: any Scheduling
    private let onIdle: @Sendable () -> Void
    private let pending = OSAllocatedUnfairLock<(any Cancellable)?>(initialState: nil)

    public init(timeout: Double, scheduler: any Scheduling, onIdle: @escaping @Sendable () -> Void) {
        self.timeout = timeout
        self.scheduler = scheduler
        self.onIdle = onIdle
    }

    public func activity() {
        pending.withLock { pending in
            pending?.cancel()
            pending = scheduler.schedule(after: timeout, onIdle)
        }
    }
}
