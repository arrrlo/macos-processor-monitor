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
                apps: [200: AppInfo(name: "Finder", icon: testIcon)]
            )
            let size = render(model)
            #expect(size.width >= 560)
            #expect(size.height > 300)
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
            #expect(controller.isVisible)
            controller.show()
            #expect(controller.window === window)
            controller.update(DashboardModel(snapshot: .empty, clusterNames: [], apps: [:]))

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
            window.miniaturize(nil)
            controller.windowDidChangeOcclusionState(Notification(name: NSWindow.didChangeOcclusionStateNotification, object: window))
            #expect(visibility.first == true)
            window.close()
            #expect(!controller.isVisible)
        }
    }
}
