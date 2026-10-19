import os

/// Wraps a completion handler so that only the first of several racing callers (reply, error,
/// timeout) gets through.
public final class OneShot<Value>: Sendable {
    private let handler: OSAllocatedUnfairLock<(@Sendable (Value) -> Void)?>

    public init(_ handler: @escaping @Sendable (Value) -> Void) {
        self.handler = OSAllocatedUnfairLock(initialState: handler)
    }

    /// Returns whether this call was the one that delivered.
    @discardableResult
    public func fire(_ value: Value) -> Bool {
        let pending = handler.withLock { stored in
            defer { stored = nil }
            return stored
        }
        pending?(value)
        return pending != nil
    }
}
