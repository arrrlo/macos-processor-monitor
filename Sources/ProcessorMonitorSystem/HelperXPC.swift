import Foundation
import ProcessorMonitorCore

/// The privileged helper's only operation. It is read-only and returns what `ps` already shows
/// to any user, so connections are not authenticated (ad-hoc signatures cannot be pinned anyway).
@objc(PMHelperProtocol) public protocol HelperProtocol {
    func topProcesses(limit: Int, reply: @escaping @Sendable (Data) -> Void)
}

public enum HelperWire {
    /// Also the launchd label of the helper daemon.
    public static let machServiceName = "io.github.arrrlo.macos-processor-monitor.helper"
    static let maximumLimit = 50

    static func interface() -> NSXPCInterface {
        NSXPCInterface(with: HelperProtocol.self)
    }

    static func clamp(_ limit: Int) -> Int {
        min(max(limit, 1), maximumLimit)
    }

    static func encode(_ processes: [ProcessUsage]) -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        // Encoding plain structs of strings and numbers cannot fail.
        return try! encoder.encode(processes)
    }

    static func decode(_ data: Data) -> [ProcessUsage]? {
        try? PropertyListDecoder().decode([ProcessUsage].self, from: data)
    }
}

/// The object the helper exports over XPC.
public final class HelperService: NSObject, HelperProtocol, Sendable {
    private let top: @Sendable (Int) -> [ProcessUsage]
    private let onActivity: @Sendable () -> Void

    public init(top: @escaping @Sendable (Int) -> [ProcessUsage], onActivity: @escaping @Sendable () -> Void) {
        self.top = top
        self.onActivity = onActivity
    }

    public func topProcesses(limit: Int, reply: @escaping @Sendable (Data) -> Void) {
        onActivity()
        reply(HelperWire.encode(top(HelperWire.clamp(limit))))
    }
}

/// Wires the listener, the sampler and the idle exit together. `main.swift` only adds `dispatchMain()`.
public final class HelperDaemon: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener
    private let service: HelperService
    private let idle: IdleMonitor

    public init(
        listener: NSXPCListener,
        sampler: ProcessUsageSampler,
        scheduler: any Scheduling,
        idleTimeout: Double,
        onIdle: @escaping @Sendable () -> Void
    ) {
        let idle = IdleMonitor(timeout: idleTimeout, scheduler: scheduler, onIdle: onIdle)
        self.listener = listener
        self.idle = idle
        service = HelperService(top: sampler.top, onActivity: idle.activity)
    }

    public func start() {
        listener.delegate = self
        listener.resume()
        idle.activity()
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = HelperWire.interface()
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

/// App-side connection to the helper; reconnects after the helper exits, crashes or hangs.
public final class HelperClient: @unchecked Sendable {
    private let timeout: Double
    private let scheduler: any Scheduling
    private let makeConnection: @Sendable () -> NSXPCConnection
    private let lock = NSLock()
    private var connection: NSXPCConnection?

    /// - Parameter timeout: seconds to wait for a reply. A message to a dead or hung peer
    ///   otherwise never completes.
    public init(timeout: Double, scheduler: any Scheduling, makeConnection: @escaping @Sendable () -> NSXPCConnection) {
        self.timeout = timeout
        self.scheduler = scheduler
        self.makeConnection = makeConnection
    }

    /// Talks to the root LaunchDaemon installed by the pkg.
    public static func privileged() -> HelperClient {
        HelperClient(timeout: 2, scheduler: DispatchScheduler(queue: .global(qos: .utility))) {
            NSXPCConnection(machServiceName: HelperWire.machServiceName, options: .privileged)
        }
    }

    deinit {
        connection?.invalidate()
    }

    /// `nil` when the helper is not reachable or does not answer in time.
    public func topProcesses(limit: Int, completion: @escaping @Sendable ([ProcessUsage]?) -> Void) {
        let once = OneShot(completion)
        nonisolated(unsafe) let connection = currentConnection()
        let timer = scheduler.schedule(after: timeout) {
            // A peer that does not answer in time is unhealthy: reconnect next time.
            if once.fire(nil) {
                connection.invalidate()
            }
        }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            timer.cancel()
            once.fire(nil)
        } as? HelperProtocol
        proxy?.topProcesses(limit: limit) { data in
            timer.cancel()
            once.fire(HelperWire.decode(data))
        }
    }

    private func currentConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }
        if let connection {
            return connection
        }
        let fresh = makeConnection()
        fresh.remoteObjectInterface = HelperWire.interface()
        fresh.invalidationHandler = { [weak self] in self?.dropConnection() }
        fresh.resume()
        connection = fresh
        return fresh
    }

    private func dropConnection() {
        lock.lock()
        connection = nil
        lock.unlock()
    }
}
