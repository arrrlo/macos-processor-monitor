import AppKit
import ProcessorMonitorCore

/// The status item's menu. Items are created once; `update` only rewrites titles and visibility.
@MainActor
public final class StatusMenuController: NSObject, NSMenuDelegate {
    public struct Actions {
        let openDashboard: () -> Void
        let selectInterval: (RefreshInterval) -> Void
        let toggleLaunchAtLogin: () -> Void
        let showAbout: () -> Void
        let quit: () -> Void
        let menuVisibilityChanged: (Bool) -> Void

        public init(
            openDashboard: @escaping () -> Void,
            selectInterval: @escaping (RefreshInterval) -> Void,
            toggleLaunchAtLogin: @escaping () -> Void,
            showAbout: @escaping () -> Void,
            quit: @escaping () -> Void,
            menuVisibilityChanged: @escaping (Bool) -> Void
        ) {
            self.openDashboard = openDashboard
            self.selectInterval = selectInterval
            self.toggleLaunchAtLogin = toggleLaunchAtLogin
            self.showAbout = showAbout
            self.quit = quit
            self.menuVisibilityChanged = menuVisibilityChanged
        }
    }

    static let processSlots = 10

    public let menu = NSMenu()
    private let actions: Actions
    private let loadItem = StatusMenuController.infoItem()
    private let userItem = StatusMenuController.infoItem(indented: true)
    private let systemItem = StatusMenuController.infoItem(indented: true)
    private let idleItem = StatusMenuController.infoItem(indented: true)
    private let temperatureItem = StatusMenuController.infoItem()
    private let clusterItems: [NSMenuItem]
    private let gpuLoadItem = StatusMenuController.infoItem()
    private let gpuTemperatureItem = StatusMenuController.infoItem()
    private let processHeaderItem = StatusMenuController.infoItem()
    private let processItems: [NSMenuItem]
    private let intervalItems: [NSMenuItem]
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")

    public init(clusterNames: [String], actions: Actions) {
        self.actions = actions
        clusterItems = clusterNames.map { _ in Self.infoItem() }
        processItems = (0..<Self.processSlots).map { _ in Self.infoItem(indented: true) }
        intervalItems = RefreshInterval.allCases.map { interval in
            let item = NSMenuItem(title: interval.title, action: #selector(selectInterval(_:)), keyEquivalent: "")
            item.tag = Int(interval.seconds)
            return item
        }
        super.init()
        build()
        update(MenuText(.empty, clusterNames: clusterNames), apps: [:])
    }

    private static func infoItem(indented: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.indentationLevel = indented ? 1 : 0
        return item
    }

    private func build() {
        menu.autoenablesItems = false
        menu.delegate = self
        [loadItem, userItem, systemItem, idleItem, temperatureItem].forEach(menu.addItem)
        clusterItems.forEach(menu.addItem)
        menu.addItem(gpuLoadItem)
        menu.addItem(gpuTemperatureItem)
        menu.addItem(.separator())
        menu.addItem(processHeaderItem)
        processItems.forEach(menu.addItem)
        menu.addItem(.separator())
        menu.addItem(actionItem("Open Dashboard…", #selector(openDashboard(_:)), key: "d"))
        let intervals = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        intervals.submenu = NSMenu(title: "Refresh Interval")
        intervalItems.forEach { item in
            item.target = self
            intervals.submenu?.addItem(item)
        }
        menu.addItem(intervals)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(actionItem("About macOS Processor Monitor", #selector(showAbout(_:)), key: ""))
        menu.addItem(actionItem("Quit macOS Processor Monitor", #selector(quit(_:)), key: "q"))
    }

    private func actionItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    public func update(_ text: MenuText, apps: [Int32: AppInfo]) {
        loadItem.attributedTitle = MenuStyle.row(text.load)
        userItem.attributedTitle = MenuStyle.row(text.user)
        systemItem.attributedTitle = MenuStyle.row(text.system)
        idleItem.attributedTitle = MenuStyle.row(text.idle)
        temperatureItem.attributedTitle = MenuStyle.row(text.temperature)
        for (item, row) in zip(clusterItems, text.clusters) {
            item.attributedTitle = MenuStyle.row(row)
        }
        gpuLoadItem.attributedTitle = MenuStyle.row(text.gpuLoad)
        gpuTemperatureItem.attributedTitle = MenuStyle.row(text.gpuTemperature)
        processHeaderItem.attributedTitle = MenuStyle.header(text.processHeader)
        updateProcesses(text.processes, apps: apps)
    }

    /// GUI apps get their display name and icon; everything else keeps the process name.
    private func updateProcesses(_ rows: [MenuText.ProcessRow], apps: [Int32: AppInfo]) {
        for (index, item) in processItems.enumerated() {
            item.isHidden = index >= rows.count
            guard index < rows.count else { continue }
            let app = apps[rows[index].pid]
            item.attributedTitle = MenuStyle.row(MenuText.Row(title: app?.name ?? rows[index].row.title, value: rows[index].row.value))
            item.image = app.map { MenuStyle.menuIcon($0.icon) }
        }
    }

    public func setInterval(_ interval: RefreshInterval) {
        for item in intervalItems {
            item.state = item.tag == Int(interval.seconds) ? .on : .off
        }
    }

    public func setLaunchAtLogin(enabled: Bool, available: Bool) {
        loginItem.state = enabled && available ? .on : .off
        loginItem.isEnabled = available
    }

    // MARK: - Actions

    @objc private func openDashboard(_ sender: NSMenuItem) {
        actions.openDashboard()
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        if let interval = RefreshInterval(seconds: Double(sender.tag)) {
            actions.selectInterval(interval)
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        actions.toggleLaunchAtLogin()
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        actions.showAbout()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        actions.quit()
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        actions.menuVisibilityChanged(true)
    }

    public func menuDidClose(_ menu: NSMenu) {
        actions.menuVisibilityChanged(false)
    }
}
