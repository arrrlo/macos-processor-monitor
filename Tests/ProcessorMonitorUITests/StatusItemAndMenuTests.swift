import AppKit
import Testing
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorUI

extension AppKitTests {
    @MainActor @Suite struct StatusItemControllerTests {
        @Test func showsPlaceholderThenUpdatesOnlyOnChange() throws {
            let bar = NSStatusBar()
            let menu = NSMenu()
            let controller = StatusItemController(statusBar: bar, menu: menu)
            let button = try #require(controller.item.button)
            #expect(button.title == "—  —   GPU —")
            #expect(controller.item.menu === menu)
            #expect(button.image != nil)
            #expect(button.font == StatusItemController.font)
            #expect(StatusItemController.font == NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular))

            // A fixed length means a changing reading never resizes the item, which on macOS
            // re-lays out the menu bar and sends a scene update to the system on every tick.
            let widest = ("100%  100°C   GPU 100%" as NSString).size(withAttributes: [.font: StatusItemController.font]).width
            #expect(controller.item.length == StatusItemController.length)
            #expect(StatusItemController.length >= widest + 16)
            #expect(StatusItemController.length <= widest + 40)
            controller.update(title: "100%  100°C   GPU 100%")
            #expect(controller.item.length == StatusItemController.length)
            controller.update(title: "23%  49°C")
            controller.update(title: "23%  49°C")
            #expect(button.title == "23%  49°C")
            #expect(controller.titleChanges == 3)
            #expect(button.window?.isVisible == true)
            controller.remove()
            #expect(button.window?.isVisible == false)
        }
    }

    @MainActor @Suite struct StatusMenuControllerTests {
        func makeController(log: ActionLog, clusters: [String] = ["Super", "Performance"]) -> StatusMenuController {
            StatusMenuController(clusterNames: clusters, actions: StatusMenuController.Actions(
                openDashboard: { log.entries.append("dashboard") },
                selectInterval: { log.entries.append("interval \($0.seconds)") },
                toggleLaunchAtLogin: { log.entries.append("login") },
                showAbout: { log.entries.append("about") },
                quit: { log.entries.append("quit") },
                menuVisibilityChanged: { log.entries.append("visible \($0)") }
            ))
        }

        @Test func hasTheExactLayout() {
            let menu = makeController(log: ActionLog()).menu
            let titles = menu.items.map { $0.isSeparatorItem ? "---" : $0.attributedTitle?.string ?? $0.title }
            #expect(titles == [
                "Processor load\t—", "User\t—", "System\t—", "Idle\t—", "Temperature\tUnavailable",
                "Super cores\t—", "Performance cores\t—",
                "GPU load\t—",
                "---",
                "Top processes — measuring…", "", "", "", "", "", "", "", "", "", "",
                "---",
                "Open Dashboard…", "Refresh Interval", "Launch at Login",
                "---",
                "About macOS Processor Monitor", "Quit macOS Processor Monitor",
            ])
            // load, user, system, idle, temperature, 2 clusters, GPU load, separator, header, 10 processes, …
            #expect(menu.items.map(\.indentationLevel) == [0, 1, 1, 1, 0, 0, 0, 0, 0, 0] + Array(repeating: 1, count: 10) + Array(repeating: 0, count: 7))
            #expect(menu.items[10...19].allSatisfy { $0.isHidden })
            #expect(menu.items[21].keyEquivalent == "d")
            #expect(menu.items[26].keyEquivalent == "q")
            #expect(menu.items[22].submenu?.items.map(\.title) == ["1 second", "2 seconds", "5 seconds"])
            #expect(!menu.autoenablesItems)
            #expect(!menu.items[0].isEnabled)
            #expect(menu.items[21].isEnabled)
        }

        @Test func updatesRowsInPlace() {
            let controller = makeController(log: ActionLog())
            let menu = controller.menu
            let before = menu.items.map(ObjectIdentifier.init)
            controller.update(MenuText(.sample, clusterNames: ["Super", "Performance"]), apps: [200: AppInfo(name: "Finder", icon: testIcon)])
            #expect(menu.items.map(ObjectIdentifier.init) == before)
            #expect(menu.items[0].attributedTitle?.string == "Processor load\t23%")
            #expect(menu.items[4].attributedTitle?.string == "Temperature\t53°C (max 59°C)")
            #expect(menu.items[5].attributedTitle?.string == "Super cores\t60%")
            #expect(menu.items[7].attributedTitle?.string == "GPU load\t18%")
            #expect(menu.items[9].attributedTitle?.string == "Top processes")
            #expect(menu.items[10].attributedTitle?.string == "WindowServer\t12.3%")
            #expect(menu.items[10].image == nil)
            #expect(menu.items[11].attributedTitle?.string == "Finder\t3.5%")
            #expect(menu.items[11].image?.size == NSSize(width: 16, height: 16))
            #expect(!menu.items[11].isHidden)
            #expect(menu.items[12].isHidden)
        }

        @Test func itemsTriggerTheirActions() throws {
            let log = ActionLog()
            let controller = makeController(log: log)
            let menu = controller.menu
            menu.performActionForItem(at: 21)
            let submenu = try #require(menu.items[22].submenu)
            submenu.performActionForItem(at: 2)
            menu.performActionForItem(at: 23)
            menu.performActionForItem(at: 25)
            menu.performActionForItem(at: 26)
            controller.menuWillOpen(menu)
            controller.menuDidClose(menu)
            #expect(log.entries == ["dashboard", "interval 5.0", "login", "about", "quit", "visible true", "visible false"])
        }

        @Test func checkmarksFollowSettings() throws {
            let controller = makeController(log: ActionLog())
            let menu = controller.menu
            controller.setInterval(.five)
            let submenu = try #require(menu.items[22].submenu)
            #expect(submenu.items.map(\.state) == [.off, .off, .on])

            controller.setLaunchAtLogin(enabled: true, available: true)
            #expect(menu.items[23].state == .on)
            #expect(menu.items[23].isEnabled)
            controller.setLaunchAtLogin(enabled: false, available: false)
            #expect(menu.items[23].state == .off)
            #expect(!menu.items[23].isEnabled)
        }

        @Test func layoutAdaptsToTheClusterCount() {
            let menu = makeController(log: ActionLog(), clusters: ["CPU"]).menu
            #expect(menu.items[5].attributedTitle?.string == "CPU cores\t—")
            #expect(menu.items[6].attributedTitle?.string == "GPU load\t—")
            #expect(menu.items[7].isSeparatorItem)
        }
    }
}
