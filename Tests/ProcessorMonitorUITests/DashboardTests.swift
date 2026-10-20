import AppKit
import SwiftUI
import Testing
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorUI

extension AppKitTests {
    @MainActor @Suite struct ProcessIdentityResolverTests {
        @Test func looksUpEachProcessOnceWhileItStaysListed() {
            var lookups: [pid_t] = []
            let resolver = ProcessIdentityResolver { pid in
                lookups.append(pid)
                return pid == 200 ? AppInfo(name: "Finder", icon: testIcon) : nil
            }
            let processes = MonitorSnapshot.sample.topProcesses!.processes
            #expect(resolver.resolve(processes).keys.sorted() == [200])
            #expect(resolver.resolve(processes)[200]?.name == "Finder")
            #expect(lookups == [100, 200])

            _ = resolver.resolve([])
            _ = resolver.resolve(processes)
            #expect(lookups == [100, 200, 100, 200])
        }

        @Test func liveLookupFindsRunningApplications() throws {
            #expect(ProcessIdentityResolver.runningApplication(999_999) == nil)
            let app = try #require(NSWorkspace.shared.runningApplications.first { $0.localizedName != nil && $0.icon != nil })
            #expect(ProcessIdentityResolver.runningApplication(app.processIdentifier)?.name == app.localizedName)
            #expect(!ProcessIdentityResolver.live().resolve([ProcessUsage(pid: app.processIdentifier, name: "x", cpuPercent: 1)]).isEmpty)
        }
    }

    @MainActor @Suite struct DashboardViewTests {
        func render(_ model: DashboardModel) -> NSSize {
            let host = NSHostingView(rootView: DashboardView(model: model))
            host.layout()
            return host.fittingSize
        }

        @Test func rendersAllSectionsWithData() {
            let model = DashboardModel(
                snapshot: .sample,
                clusterNames: ["Super", "Performance"],
                apps: [200: AppInfo(name: "Finder", icon: testIcon)],
                gpu: GPUInfo(name: "Apple M5 Max", coreCount: 32)
            )
            let size = render(model)
            // Two rows of four cards: narrower than a 13-inch screen (1470 pt) and far shorter than one.
            #expect(size.width > 1300)
            #expect(size.width < 1470)
            #expect(size.height > 500)
            #expect(size.height < 720)
        }

        @Test func rendersPlaceholdersWithoutData() {
            let size = render(DashboardModel(snapshot: .empty, clusterNames: ["CPU"], apps: [:]))
            #expect(size.height > 100)
        }

        @Test func rendersTheLimitedScopeNote() {
            var snapshot = MonitorSnapshot.sample
            snapshot.topProcesses = TopProcessesResult(processes: [], scope: .currentUser)
            #expect(render(DashboardModel(snapshot: snapshot, clusterNames: [], apps: [:])).height > 100)
        }

        @Test func modelPresentation() {
            let model = DashboardModel(snapshot: .sample, clusterNames: ["Super", "Performance"], apps: [:])
            #expect(model.text.load.value == "23%")
            #expect(model.coreLoads(for: "Super") == [CoreLoad(index: 1, load: 0.6)])
            #expect(model.coreLoads(for: "Missing").isEmpty)
            #expect(DashboardModel.barWidth(0.5, of: 200) == 100)
            #expect(DashboardModel.barWidth(2, of: 200) == 200)
            #expect(DashboardModel.barWidth(-1, of: 200) == 0)
        }

        @Test func gpuPresentation() {
            let model = DashboardModel(snapshot: .sample, clusterNames: [], apps: [:], gpu: GPUInfo(name: "Apple M5 Max", coreCount: 32))
            #expect(model.gpu == GPUInfo(name: "Apple M5 Max", coreCount: 32))
            #expect(model.gpuCaption == "Apple M5 Max · 32 GPU cores")
            #expect(model.gpuSplit == "Renderer 17% · Tiler 12%")
            let empty = DashboardModel(snapshot: .empty, clusterNames: [], apps: [:])
            #expect(empty.gpu == nil)
            #expect(empty.gpuCaption == "No GPU found")
            #expect(empty.gpuSplit == "Renderer — · Tiler —")
        }

        @Test func barsFillTheOccupancyAndActivityCards() {
            // The load card holds the 250 pt load bar inside 14 pt padding on each side.
            #expect(DashboardView.loadWidth == 278)
            #expect(DashboardView.barsWidth == 356)
            #expect(DashboardModel.coreBarWidth(count: 12) == 26)
            #expect(DashboardModel.coreBarWidth(count: 6) == 56)
            #expect(DashboardModel.coreBarWidth(count: 1) == 356)
            #expect(DashboardModel.coreBarWidth(count: 0) == 0)
            #expect(DashboardModel.historyBarWidth == 8)
            for count in [6, 12, GPULoadHistory.capacity] {
                let row = DashboardModel.coreBarWidth(count: count) * CGFloat(count) + DashboardView.barSpacing * CGFloat(count - 1)
                #expect(row == DashboardView.barsWidth)
            }
        }

        @Test func gpuActivityPresentation() {
            var snapshot = MonitorSnapshot.sample
            snapshot.gpuHistory = GPULoadHistory().appending(0.1).appending(0.5)
            let model = DashboardModel(snapshot: snapshot, clusterNames: [], apps: [:], refreshInterval: 2)
            // Oldest on the left; slots not yet filled stay empty.
            #expect(model.historyBars.count == 30)
            #expect(model.historyBars.prefix(28).allSatisfy { $0 == nil })
            #expect(model.historyBars.suffix(2) == [0.1, 0.5])
            #expect(model.historySpan == "Last 60 s")
            #expect(DashboardModel(snapshot: .empty, clusterNames: [], apps: [:], refreshInterval: 5).historySpan == "Last 150 s")
            #expect(DashboardModel(snapshot: .empty, clusterNames: [], apps: [:]).historySpan == "Last 60 s")
            #expect(DashboardModel(snapshot: .empty, clusterNames: [], apps: [:]).historyBars == Array(repeating: nil, count: 30))
        }

        @Test func processListsForBothProcessors() {
            var snapshot = MonitorSnapshot.sample
            snapshot.topGPUProcesses = TopProcessesResult(processes: [ProcessUsage(pid: 405, name: "WindowServer", cpuPercent: 3.2)], scope: .allProcesses)
            let model = DashboardModel(snapshot: snapshot, clusterNames: [], apps: [:])
            #expect(model.cpuProcessesTitle == "Top CPU processes")
            #expect(model.gpuProcessesTitle == "Top GPU processes")
            #expect(model.gpuProcessRows == [MenuText.ProcessRow(pid: 405, row: MenuText.Row(title: "WindowServer", value: "3.2%"))])
            let empty = DashboardModel(snapshot: .empty, clusterNames: [], apps: [:])
            #expect(empty.cpuProcessesTitle == "Top CPU processes — measuring…")
            #expect(empty.gpuProcessesTitle == "Top GPU processes — measuring…")
            #expect(empty.gpuProcessRows.isEmpty)
            var limited = MonitorSnapshot.sample
            limited.topProcesses = TopProcessesResult(processes: [], scope: .currentUser)
            #expect(DashboardModel(snapshot: limited, clusterNames: [], apps: [:]).cpuProcessesTitle == "Top CPU processes (your processes only)")
        }
    }

    @MainActor @Suite struct DashboardWindowControllerTests {
        @Test func createsTheWindowOnDemandAndReleasesItOnClose() throws {
            var visibility: [Bool] = []
            let controller = DashboardWindowController { visibility.append($0) }
            #expect(controller.window == nil)
            controller.update(DashboardModel(snapshot: .sample, clusterNames: [], apps: [:]))
            #expect(controller.window == nil)

            controller.show()
            let window = try #require(controller.window)
            #expect(window.title == "macOS Processor Monitor")
            #expect(window.styleMask == [.titled, .closable, .miniaturizable])
            #expect(window.frame.height > 300)
            let screen = try #require(window.screen ?? NSScreen.main)
            #expect(abs(window.frame.midX - screen.visibleFrame.midX) <= 1)
            #expect(controller.isVisible)
            #expect(controller.model.snapshot == .sample)
            controller.show()
            #expect(controller.window === window)
            controller.update(DashboardModel(snapshot: .empty, clusterNames: [], apps: [:]))
            #expect(controller.model.snapshot == .empty)

            window.close()
            #expect(controller.window == nil)
            #expect(!controller.isVisible)
            #expect(visibility == [true, false])
        }

        @Test func occlusionChangesUpdateVisibility() throws {
            var visibility: [Bool] = []
            let controller = DashboardWindowController { visibility.append($0) }
            controller.show()
            let window = try #require(controller.window)
            window.orderOut(nil)
            controller.windowDidChangeOcclusionState(Notification(name: NSWindow.didChangeOcclusionStateNotification, object: window))
            // Without a running app the window server never reports the window as visible,
            // so this normally takes the "hidden" path; either way state must follow occlusion.
            let shown = window.occlusionState.contains(.visible)
            #expect(controller.isVisible == shown)
            #expect(visibility == (shown ? [true] : [true, false]))
            window.close()
            #expect(!controller.isVisible)
        }
    }
}
