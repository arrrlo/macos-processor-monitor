import Foundation
import IOKit
import Testing
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorSystem

/// The GPU's user clients as the registry lists them, with every object it hands out tracked so a
/// test can check all of them are released.
final class FakeGPUClients: @unchecked Sendable {
    private(set) var outstanding: Set<io_object_t> = []
    private var nextObject: io_object_t = 100
    var service: io_service_t?
    var clients: [[String: Any]] = []
    var time: UInt64 = 7_000_000_000
    private var pending: [[String: Any]] = []
    private var properties: [io_object_t: [String: Any]] = [:]

    private func make() -> io_object_t {
        nextObject += 1
        outstanding.insert(nextObject)
        return nextObject
    }

    var source: GPUProcessTableReader.Source {
        GPUProcessTableReader.Source(
            service: {
                self.pending = self.clients
                return self.service ?? self.make()
            },
            children: { _ in self.make() },
            next: { _ in
                guard !self.pending.isEmpty else { return 0 }
                let client = self.make()
                self.properties[client] = self.pending.removeFirst()
                return client
            },
            property: { object, key in self.properties[object]?[key] },
            release: { self.outstanding.remove($0) },
            now: { self.time }
        )
    }

    static func client(_ creator: String, _ times: [UInt64]) -> [String: Any] {
        ["IOUserClientCreator": creator, "AppUsage": times.map { ["API": "Metal", "accumulatedGPUTime": NSNumber(value: $0)] }]
    }
}

@Suite struct GPUClientParserTests {
    @Test func readsTheCreatingProcess() throws {
        let process = try #require(GPUClientParser.process("pid 405, WindowServer"))
        #expect(process.pid == 405)
        #expect(process.name == "WindowServer")
        #expect(GPUClientParser.process("pid 7, Name, with, commas")?.name == "Name, with, commas")
    }

    @Test func rejectsOtherCreators() {
        #expect(GPUClientParser.process("pid 405") == nil)
        #expect(GPUClientParser.process("pid x, WindowServer") == nil)
        #expect(GPUClientParser.process("405, WindowServer") == nil)
    }

    @Test func addsUpTheTimeOfEveryQueue() throws {
        let usage = try #require(GPUClientParser.usage(
            creator: "pid 405, WindowServer",
            appUsage: [["accumulatedGPUTime": NSNumber(value: 300)], ["API": "Metal"], ["accumulatedGPUTime": NSNumber(value: 45)]]
        ))
        #expect(usage.pid == 405)
        #expect(usage.name == "WindowServer")
        #expect(usage.time == 345)
        #expect(GPUClientParser.usage(creator: "pid 1, launchd", appUsage: [[String: Any]]())?.time == 0)
    }

    @Test func needsACreatorAndAUsageList() {
        #expect(GPUClientParser.usage(creator: nil, appUsage: [[String: Any]]()) == nil)
        #expect(GPUClientParser.usage(creator: "pid 1, launchd", appUsage: nil) == nil)
        #expect(GPUClientParser.usage(creator: "launchd", appUsage: [[String: Any]]()) == nil)
    }
}

@Suite struct GPUProcessTableReaderTests {
    @Test func sumsEachProcessesClientsAndReleasesEverything() {
        let registry = FakeGPUClients()
        registry.clients = [
            FakeGPUClients.client("pid 405, WindowServer", [300, 45]),
            ["IOUserClientCreator": "pid 9, broken"],
            FakeGPUClients.client("pid 405, WindowServer", [655]),
            FakeGPUClients.client("pid 6844, ghostty", [20]),
        ]
        let snapshot = GPUProcessTableReader(source: registry.source).snapshot()
        #expect(snapshot.timestamp == 7_000_000_000)
        #expect(snapshot.processes.sorted { $0.pid < $1.pid } == [
            ProcessSample(pid: 405, startTime: 0, name: "WindowServer", cpuTime: 1_000),
            ProcessSample(pid: 6844, startTime: 0, name: "ghostty", cpuTime: 20),
        ])
        #expect(registry.outstanding.isEmpty)
    }

    @Test func noGPUEntryMeansNoProcesses() {
        let registry = FakeGPUClients()
        registry.service = 0
        #expect(GPUProcessTableReader(source: registry.source).snapshot().processes.isEmpty)
    }

    /// Every Mac with a GPU entry has WindowServer drawing through it; a VM has neither.
    @Test func liveSnapshotListsGPUClients() {
        let snapshot = GPUProcessTableReader().snapshot()
        guard GPUReader().read() != nil else { return }
        #expect(!snapshot.processes.isEmpty)
        #expect(snapshot.timestamp > 0)
    }
}

@Suite(.timeLimit(.minutes(1))) struct GPUProcessesServiceTests {
    func top(_ snapshots: [ProcessSnapshot], executablePath: @escaping @Sendable (Int32) -> String? = { _ in nil }) async -> TopProcessesResult {
        let remaining = ScriptedSnapshots(snapshots)
        let sampler = ProcessUsageSampler(
            timebase: Timebase(numer: 1, denom: 1),
            minimumWindow: 1, // any window: the second scripted snapshot is the "after" one
            maximumBaselineAge: 5_000_000_000,
            snapshot: { remaining.next() },
            sleep: { _ in }
        )
        let service = GPUProcessesService(sampler: sampler, executablePath: executablePath)
        return await withCheckedContinuation { continuation in
            service.topProcesses(limit: 2) { continuation.resume(returning: $0) }
        }
    }

    /// GPU time is already in nanoseconds: 0.5 s of GPU time in 1 s is 50% of the GPU.
    @Test func ranksBusyProcessesAndLeavesOutIdleOnes() async {
        let before = ProcessSnapshot(timestamp: 1_000_000_000, processes: [
            ProcessSample(pid: 405, startTime: 0, name: "WindowServer", cpuTime: 100),
            ProcessSample(pid: 412, startTime: 0, name: "runningboardd", cpuTime: 0),
            ProcessSample(pid: 6844, startTime: 0, name: "ghostty", cpuTime: 0),
        ])
        let after = ProcessSnapshot(timestamp: 2_000_000_000, processes: [
            ProcessSample(pid: 405, startTime: 0, name: "WindowServer", cpuTime: 100 + 200_000_000),
            ProcessSample(pid: 412, startTime: 0, name: "runningboardd", cpuTime: 0),
            ProcessSample(pid: 6844, startTime: 0, name: "ghostty", cpuTime: 500_000_000),
        ])
        let result = await top([before, after]) { $0 == 6844 ? "/Applications/Ghostty.app/Contents/MacOS/ghostty-full-name" : nil }
        #expect(result.scope == .allProcesses)
        #expect(result.processes == [
            ProcessUsage(pid: 6844, name: "ghostty-full-name", cpuPercent: 50),
            ProcessUsage(pid: 405, name: "WindowServer", cpuPercent: 20),
        ])
    }

    @Test func anIdleGPUListsNothing() async {
        let idle = ProcessSnapshot(timestamp: 1_000_000_000, processes: [ProcessSample(pid: 405, startTime: 0, name: "WindowServer", cpuTime: 100)])
        let later = ProcessSnapshot(timestamp: 2_000_000_000, processes: idle.processes)
        #expect(await top([idle, later]).processes.isEmpty)
    }

    @Test func liveSamplerMeasuresAQuarterSecondWindow() {
        let start = Date()
        _ = ProcessUsageSampler.gpu().top(limit: 1)
        #expect(Date().timeIntervalSince(start) >= 0.2)
    }

    @Test func liveServiceAnswers() async {
        let service = GPUProcessesService.live()
        let result = await withCheckedContinuation { continuation in
            service.topProcesses(limit: 10) { continuation.resume(returning: $0) }
        }
        #expect(result.scope == .allProcesses)
        #expect(result.processes.count <= 10)
        #expect(result.processes.allSatisfy { $0.cpuPercent > 0 })
    }
}

/// Hands out scripted snapshots in order, repeating the last one.
final class ScriptedSnapshots: @unchecked Sendable {
    private var snapshots: [ProcessSnapshot]
    private let lock = NSLock()

    init(_ snapshots: [ProcessSnapshot]) {
        self.snapshots = snapshots
    }

    func next() -> ProcessSnapshot {
        lock.withLock {
            snapshots.count > 1 ? snapshots.removeFirst() : snapshots[0]
        }
    }
}
