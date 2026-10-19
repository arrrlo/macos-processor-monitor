import Dispatch
import ProcessorMonitorCore

/// `Scheduling` on GCD timers. Leeway lets the kernel coalesce our wake-ups with others.
public struct DispatchScheduler: Scheduling {
    private let queue: DispatchQueue
    private let leewayFraction: Double

    public init(queue: DispatchQueue, leewayFraction: Double = 0.2) {
        self.queue = queue
        self.leewayFraction = leewayFraction
    }

    public func schedule(after delay: Double, _ action: @escaping @Sendable () -> Void) -> any Cancellable {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay, leeway: Self.leeway(for: delay, fraction: leewayFraction))
        let handle = TimerHandle(timer)
        timer.setEventHandler {
            action()
            handle.cancel()
        }
        timer.resume()
        return handle
    }

    public func scheduleRepeating(every interval: Double, _ action: @escaping @Sendable () -> Void) -> any Cancellable {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: Self.leeway(for: interval, fraction: leewayFraction))
        timer.setEventHandler(handler: action)
        timer.resume()
        return TimerHandle(timer)
    }

    static func leeway(for seconds: Double, fraction: Double) -> DispatchTimeInterval {
        .nanoseconds(Int(seconds * fraction * 1_000_000_000))
    }
}

/// Dispatch sources are thread-safe; cancelling also breaks the handler's reference to the timer.
private final class TimerHandle: Cancellable, @unchecked Sendable {
    private let timer: DispatchSourceTimer

    init(_ timer: DispatchSourceTimer) {
        self.timer = timer
    }

    func cancel() {
        timer.cancel()
    }
}
