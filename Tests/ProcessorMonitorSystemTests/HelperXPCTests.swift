import Foundation
import Testing
import TestSupport
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorSystem

final class Recorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Value] = []

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func append(_ value: Value) {
        lock.lock()
        stored.append(value)
        lock.unlock()
    }
}

/// Waits for a completion-handler API to deliver.
func awaitValue<T: Sendable>(_ start: (@escaping @Sendable (T) -> Void) -> Void) async -> T {
    await withCheckedContinuation { continuation in
        start { continuation.resume(returning: $0) }
    }
}

@Suite struct HelperWireTests {
    @Test func roundTripsProcessUsage() {
        let processes = [ProcessUsage(pid: 1, name: "kernel_task", cpuPercent: 12.5)]
        #expect(HelperWire.decode(HelperWire.encode(processes)) == processes)
    }

    @Test func rejectsGarbage() {
        #expect(HelperWire.decode(Data("nope".utf8)) == nil)
    }

    @Test func clampsRequestedLimit() {
        #expect(HelperWire.clamp(0) == 1)
        #expect(HelperWire.clamp(10) == 10)
        #expect(HelperWire.clamp(500) == 50)
    }

    @Test func machServiceNameMatchesTheLaunchdLabel() {
        #expect(HelperWire.machServiceName == "io.github.arrrlo.macos-processor-monitor.helper")
    }
}

@Suite(.timeLimit(.minutes(1))) struct HelperServiceTests {
    @Test func answersWithClampedTopProcessesAndReportsActivity() async {
        let limits = Recorder<Int>()
        let activity = Recorder<Bool>()
        let service = HelperService(
            top: { limit in
                limits.append(limit)
                return [ProcessUsage(pid: 9, name: "x", cpuPercent: 1)]
            },
            onActivity: { activity.append(true) }
        )
        let data = await awaitValue { reply in service.topProcesses(limit: 999, reply: reply) }
        #expect(HelperWire.decode(data) == [ProcessUsage(pid: 9, name: "x", cpuPercent: 1)])
        #expect(limits.values == [50])
        #expect(activity.values.count == 1)
    }
}

@Suite(.timeLimit(.minutes(1))) struct HelperXPCIntegrationTests {
    func makeDaemon(_ listener: NSXPCListener) -> HelperDaemon {
        // Each snapshot is 1 ns later with 1 more tick of CPU time: a fully busy process.
        let ticks = Recorder<Bool>()
        return HelperDaemon(
            listener: listener,
            sampler: ProcessUsageSampler(
                timebase: Timebase(numer: 1, denom: 1),
                minimumWindow: 1,
                maximumBaselineAge: .max,
                snapshot: {
                    ticks.append(true)
                    let now = UInt64(ticks.values.count)
                    return ProcessSnapshot(timestamp: now, processes: [ProcessSample(pid: 42, startTime: 1, name: "fake", cpuTime: now)])
                },
                sleep: { _ in }
            ),
            scheduler: FakeScheduler(),
            idleTimeout: 30,
            onIdle: {}
        )
    }

    @Test func clientReceivesProcessesAndKeepsAHealthyConnection() async throws {
        let listener = NSXPCListener.anonymous()
        let daemon = makeDaemon(listener)
        daemon.start()
        let endpoint = listener.endpoint
        let scheduler = FakeScheduler()
        let connections = Recorder<Bool>()
        let client = HelperClient(timeout: 2, scheduler: scheduler) {
            connections.append(true)
            return NSXPCConnection(listenerEndpoint: endpoint)
        }
        let processes = await awaitValue { client.topProcesses(limit: 10, completion: $0) }
        #expect(processes == [ProcessUsage(pid: 42, name: "fake", cpuPercent: 100)])
        // The reply cancelled the timeout, so expiring it must not tear the connection down.
        scheduler.advance(by: 2)
        #expect(scheduler.pending.isEmpty)
        _ = await awaitValue { client.topProcesses(limit: 10, completion: $0) }
        #expect(connections.values.count == 1)
        listener.invalidate()
    }

    @Test func unreachableHelperTimesOutAndReconnectsNextTime() async {
        let dead = NSXPCListener.anonymous()
        let endpoint = dead.endpoint
        dead.invalidate()
        let connections = Recorder<Bool>()
        let client = HelperClient(timeout: 0.2, scheduler: DispatchScheduler(queue: DispatchQueue(label: "timeout"))) {
            connections.append(true)
            return NSXPCConnection(listenerEndpoint: endpoint)
        }
        let first = await awaitValue { client.topProcesses(limit: 10, completion: $0) }
        #expect(first == nil)
        // Timing out invalidates the connection; its invalidation handler drops it asynchronously.
        try? await Task.sleep(nanoseconds: 100_000_000)
        let second = await awaitValue { client.topProcesses(limit: 10, completion: $0) }
        #expect(second == nil)
        #expect(connections.values.count == 2)
    }

    @Test func helperThatNeverRepliesTimesOut() async {
        let listener = NSXPCListener.anonymous()
        let delegate = SilentHelper()
        listener.delegate = delegate
        listener.resume()
        let endpoint = listener.endpoint
        let scheduler = FakeScheduler()
        let client = HelperClient(timeout: 2, scheduler: scheduler) { NSXPCConnection(listenerEndpoint: endpoint) }
        let result = await awaitValue { completion in
            client.topProcesses(limit: 10, completion: completion)
            scheduler.advance(by: 2)
        }
        #expect(result == nil)
        listener.invalidate()
    }

    @Test func idleTimeoutIsArmedOnStart() {
        let scheduler = FakeScheduler()
        let idle = Recorder<Bool>()
        let daemon = HelperDaemon(
            listener: NSXPCListener.anonymous(),
            sampler: ProcessUsageSampler.live(),
            scheduler: scheduler,
            idleTimeout: 30,
            onIdle: { idle.append(true) }
        )
        daemon.start()
        scheduler.advance(by: 30)
        #expect(idle.values == [true])
    }

    @Test func privilegedClientAnswersEitherWay() async {
        // Without the installed helper this fails over to nil; with it, real data arrives.
        let client = HelperClient.privileged()
        _ = await awaitValue { client.topProcesses(limit: 1, completion: $0) }
    }
}

@Suite(.timeLimit(.minutes(1))) struct TopProcessesServiceTests {
    @Test func usesTheHelperWhenItAnswers() async {
        let service = TopProcessesService(
            helper: { _, completion in completion([ProcessUsage(pid: 1, name: "root", cpuPercent: 3)]) },
            local: ProcessUsageSampler.live()
        )
        let result = await awaitValue { service.topProcesses(limit: 5, completion: $0) }
        #expect(result == TopProcessesResult(processes: [ProcessUsage(pid: 1, name: "root", cpuPercent: 3)], scope: .allProcesses))
    }

    @Test func fallsBackToTheCurrentUsersProcesses() async {
        let service = TopProcessesService(helper: { _, completion in completion(nil) }, local: ProcessUsageSampler.live())
        let result = await awaitValue { service.topProcesses(limit: 5, completion: $0) }
        #expect(result.scope == .currentUser)
        #expect(result.processes.count == 5)
    }

    @Test func liveServiceAnswers() async {
        let result = await awaitValue { TopProcessesService.live().topProcesses(limit: 3, completion: $0) }
        #expect(result.processes.count <= 3)
    }
}

@Suite(.timeLimit(.minutes(1))) struct DispatchSchedulerTests {
    @Test func oneShotFiresOnce() async {
        let scheduler = DispatchScheduler(queue: DispatchQueue(label: "test"))
        let fired = Recorder<Bool>()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _ = scheduler.schedule(after: 0.01) {
                fired.append(true)
                continuation.resume()
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fired.values.count == 1)
    }

    @Test func repeatingFiresUntilCancelled() async {
        let scheduler = DispatchScheduler(queue: DispatchQueue(label: "test"))
        let fired = Recorder<Bool>()
        let task = scheduler.scheduleRepeating(every: 0.01) { fired.append(true) }
        try? await Task.sleep(nanoseconds: 80_000_000)
        task.cancel()
        let count = fired.values.count
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(count >= 2)
        #expect(fired.values.count == count)
    }

    @Test func cancelledOneShotNeverFires() async {
        let scheduler = DispatchScheduler(queue: DispatchQueue(label: "test"))
        let fired = Recorder<Bool>()
        scheduler.schedule(after: 0.01) { fired.append(true) }.cancel()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fired.values.isEmpty)
    }
}

/// Accepts connections but never answers.
final class SilentHelper: NSObject, NSXPCListenerDelegate, HelperProtocol {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = HelperWire.interface()
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func topProcesses(limit: Int, reply: @escaping @Sendable (Data) -> Void) {}
}
