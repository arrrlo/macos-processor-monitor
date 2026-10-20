import AppKit
import Testing
import TestSupport
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorUI

extension AppKitTests {
    @MainActor @Suite struct AppControllerTests {
        /// Two clusters, matching the menu indices used in StatusMenuControllerTests.
        let topology = CPUTopology(clusters: [CPUCluster(name: "Super", coreIndices: [0]), CPUCluster(name: "Performance", coreIndices: [])])

        struct Harness {
            let controller: AppController
            let sources: FakeSources
            let scheduler: FakeScheduler
            let settings: InMemorySettings
            let loginItem: FakeLoginItem
            let workspace: NotificationCenter
            let log: ActionLog
        }

        func makeHarness() -> Harness {
            let sources = FakeSources()
            sources.ticks = FakeSources.ticks(busy: [25, 50, 75])
            sources.temperatures = [TemperatureSummary(average: 48.6, maximum: 52, sensorCount: 1)]
            sources.gpuLoads = [GPULoad(device: 0.05, renderer: 0.04, tiler: 0.01)]
            sources.gpuTemperatures = [TemperatureSummary(average: 41.6, maximum: 43, sensorCount: 8)]
            let scheduler = FakeScheduler()
            let settings = InMemorySettings()
            let loginItem = FakeLoginItem()
            let workspace = NotificationCenter()
            let log = ActionLog()
            let topology = topology
            let controller = AppController(
                topology: topology,
                gpu: GPUInfo(name: "Apple M5 Max", coreCount: 32),
                settings: settings,
                loginItem: loginItem,
                identities: ProcessIdentityResolver { _ in nil },
                statusBar: NSStatusBar(),
                workspaceCenter: workspace,
                actions: AppActions(
                    activate: { log.entries.append("activate") },
                    showAbout: { log.entries.append("about") },
                    quit: { log.entries.append("quit") }
                ),
                now: { scheduler.now },
                makeEngine: { publish in
                    SamplingEngine(
                        sources: SamplingEngine.Sources(
                            cpuTicks: sources.readTicks,
                            temperature: sources.readTemperature,
                            gpuLoad: sources.readGPULoad,
                            gpuTemperature: sources.readGPUTemperature,
                            topProcesses: sources.processes,
                            gpuProcesses: sources.gpuProcesses,
                            topology: topology
                        ),
                        scheduler: scheduler,
                        interval: settings.refreshInterval.seconds,
                        publish: publish
                    )
                }
            )
            return Harness(controller: controller, sources: sources, scheduler: scheduler, settings: settings, loginItem: loginItem, workspace: workspace, log: log)
        }

        @Test func startShowsReadingsInTheStatusItem() async throws {
            let harness = makeHarness()
            harness.controller.start()
            #expect(harness.controller.isRunning)
            await settle()
            let button = try #require(harness.controller.statusItem.item.button)
            #expect(button.title == "CPU —  49°C   GPU —  42°C")
            harness.scheduler.advance(by: 2)
            await settle()
            #expect(button.title == "CPU 25%  49°C   GPU 5%  42°C")
            harness.controller.stop()
            #expect(!harness.controller.isRunning)
            #expect(button.window?.isVisible == false)
        }

        @Test func smallChangesWaitBeforeRedrawingTheMenuBar() async throws {
            let harness = makeHarness()
            harness.sources.ticks = FakeSources.ticks(busy: [25, 26, 26, 26, 26, 26, 26])
            harness.controller.start()
            harness.scheduler.advance(by: 2)
            await settle()
            let button = try #require(harness.controller.statusItem.item.button)
            #expect(button.title == "CPU 25%  49°C   GPU 5%  42°C")
            harness.scheduler.advance(by: 2)
            await settle()
            #expect(button.title == "CPU 25%  49°C   GPU 5%  42°C")
            harness.scheduler.advance(by: 10)
            await settle()
            #expect(button.title == "CPU 26%  49°C   GPU 5%  42°C")
            harness.controller.stop()
        }

        @Test func openingTheMenuRequestsProcessesAndFillsIt() async {
            let harness = makeHarness()
            harness.controller.start()
            let menu = harness.controller.menu.menu
            harness.controller.menu.menuWillOpen(menu)
            #expect(harness.sources.processes.requests == [10])
            // The menu has no GPU list.
            #expect(harness.sources.gpuProcesses.requests.isEmpty)
            harness.sources.processes.complete(with: MonitorSnapshot.sample.topProcesses!)
            await settle()
            #expect(menu.items[10].attributedTitle?.string == "Top processes")
            #expect(menu.items[11].attributedTitle?.string == "WindowServer\t12.3%")

            harness.controller.menu.menuDidClose(menu)
            harness.scheduler.advance(by: 2)
            await settle()
            #expect(harness.sources.processes.requests.count == 1)
            harness.controller.stop()
        }

        @Test func menuShowsTheLatestReadingWhenOpened() async {
            let harness = makeHarness()
            harness.controller.start()
            harness.scheduler.advance(by: 2)
            await settle()
            let menu = harness.controller.menu.menu
            #expect(menu.items[0].attributedTitle?.string == "Processor load\t—")
            harness.controller.menu.menuWillOpen(menu)
            #expect(menu.items[0].attributedTitle?.string == "Processor load\t25%")
            harness.controller.stop()
        }

        @Test func menuActionsReachSettingsLoginItemAndApp() throws {
            let harness = makeHarness()
            harness.controller.start()
            let menu = harness.controller.menu.menu
            #expect(menu.items[24].state == .on)

            let submenu = try #require(menu.items[23].submenu)
            #expect(submenu.items[1].state == .on)
            #expect(harness.scheduler.pending.map(\.interval) == [2])
            submenu.performActionForItem(at: 0)
            #expect(harness.settings.refreshInterval == .one)
            #expect(submenu.items[0].state == .on)
            #expect(harness.scheduler.pending.map(\.interval) == [1])

            menu.performActionForItem(at: 24)
            #expect(harness.loginItem.changes == [false])
            #expect(menu.items[24].state == .off)

            menu.performActionForItem(at: 26)
            menu.performActionForItem(at: 27)
            #expect(harness.log.entries == ["about", "quit"])
            harness.controller.stop()
        }

        @Test func dashboardShowsDataAndCreatesDemandWhileVisible() async throws {
            let harness = makeHarness()
            harness.controller.start()
            await settle()
            harness.controller.menu.menu.performActionForItem(at: 22)
            #expect(harness.log.entries == ["activate"])
            let window = try #require(harness.controller.dashboard.window)
            // Opening shows the latest reading at once, without waiting for a tick.
            #expect(harness.controller.dashboard.model.snapshot.temperature?.average == 48.6)
            #expect(harness.controller.dashboard.model.clusterNames == ["Super", "Performance"])
            #expect(harness.controller.dashboard.model.gpu == GPUInfo(name: "Apple M5 Max", coreCount: 32))
            #expect(harness.controller.dashboard.model.snapshot.gpuTemperature?.average == 41.6)
            #expect(harness.sources.processes.requests == [10])
            #expect(harness.sources.gpuProcesses.requests == [10])
            harness.sources.processes.complete(with: MonitorSnapshot.sample.topProcesses!)
            harness.sources.gpuProcesses.complete(with: MonitorSnapshot.sample.topProcesses!)
            await settle()
            #expect(harness.controller.dashboard.model.snapshot.topProcesses == MonitorSnapshot.sample.topProcesses)
            #expect(harness.controller.dashboard.model.snapshot.topGPUProcesses == MonitorSnapshot.sample.topProcesses)
            harness.scheduler.advance(by: 2)
            await settle()
            #expect(harness.controller.dashboard.model.snapshot.load?.overall.total == 0.25)
            window.close()
            harness.scheduler.advance(by: 2)
            #expect(harness.sources.processes.requests.count == 2)
            #expect(harness.sources.gpuProcesses.requests.count == 2)
            harness.scheduler.advance(by: 4)
            #expect(harness.sources.gpuProcesses.requests.count == 2)
            harness.controller.stop()
        }

        @Test func displaySleepPausesSampling() async {
            let harness = makeHarness()
            harness.controller.start()
            harness.workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
            #expect(harness.scheduler.pending.isEmpty)
            harness.workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            #expect(harness.scheduler.pending.count == 1)
            harness.controller.stop()
            harness.workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            #expect(harness.scheduler.pending.isEmpty)
        }

        @Test func liveControllerStartsAndStops() async {
            let controller = AppController.live(
                statusBar: NSStatusBar(),
                actions: AppActions(activate: {}, showAbout: {}, quit: {})
            )
            controller.start()
            await settle()
            controller.stop()
        }
    }

    @MainActor @Suite struct AppDelegateTests {
        @Test func startsTheControllerWhenNoOtherInstanceRuns() {
            var made = 0
            var terminated = 0
            let delegate = AppDelegate(
                makeController: {
                    made += 1
                    return AppController.live(statusBar: NSStatusBar(), actions: AppActions(activate: {}, showAbout: {}, quit: {}))
                },
                otherInstances: { [] },
                terminate: { terminated += 1 }
            )
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            #expect(made == 1)
            #expect(delegate.controller?.isRunning == true)
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            #expect(delegate.controller?.isRunning == false)
            #expect(terminated == 0)
        }

        @Test func quitsWhenAlreadyRunning() {
            var terminated = 0
            let delegate = AppDelegate(
                makeController: { fatalError() },
                otherInstances: { [42] },
                terminate: { terminated += 1 }
            )
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            #expect(terminated == 1)
            #expect(delegate.controller == nil)
        }
    }

    @MainActor @Suite struct SingleInstanceTests {
        @Test func othersExcludeTheCurrentProcess() {
            #expect(SingleInstance.others(bundleIdentifier: "x", currentPID: 5, running: { _ in [5, 7] }) == [7])
            #expect(SingleInstance.others(bundleIdentifier: nil, currentPID: 5, running: { _ in [7] }) == [])
        }

        @Test func runningPIDsComeFromLaunchServices() throws {
            let app = try #require(NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier != nil })
            let pids = SingleInstance.runningPIDs(bundleIdentifier: try #require(app.bundleIdentifier))
            #expect(pids.contains(app.processIdentifier))
            #expect(SingleInstance.runningPIDs(bundleIdentifier: "io.invalid.nothing").isEmpty)
            #expect(SingleInstance.otherInstances(bundleIdentifier: app.bundleIdentifier) == pids)
            #expect(SingleInstance.otherInstances(bundleIdentifier: nil).isEmpty)
        }
    }
}
