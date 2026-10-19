/// Which processes a top-N list could see.
public enum ProcessScope: Equatable, Sendable {
    /// Every process on the system, measured by the privileged helper.
    case allProcesses
    /// Only the current user's processes; the helper was unavailable.
    case currentUser
}

public struct TopProcessesResult: Equatable, Sendable {
    public let processes: [ProcessUsage]
    public let scope: ProcessScope

    public init(processes: [ProcessUsage], scope: ProcessScope) {
        self.processes = processes
        self.scope = scope
    }
}

public protocol TopProcessesProviding: Sendable {
    /// Calls `completion` exactly once, on an arbitrary queue.
    func topProcesses(limit: Int, completion: @escaping @Sendable (TopProcessesResult) -> Void)
}
