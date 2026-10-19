import Foundation

/// Wraps a completion handler so that only the first of several racing callers (reply, error,
/// timeout) gets through.
public final class OneShot<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (Value) -> Void)?

    public init(_ handler: @escaping @Sendable (Value) -> Void) {
        self.handler = handler
    }

    /// Returns whether this call was the one that delivered.
    @discardableResult
    public func fire(_ value: Value) -> Bool {
        lock.lock()
        let pending = handler
        handler = nil
        lock.unlock()
        pending?(value)
        return pending != nil
    }
}
