import AppKit
import ProcessorMonitorCore
import ProcessorMonitorSystem

/// The few things only the real application object can do; supplied by `main.swift`.
public struct AppActions {
    let activate: @MainActor () -> Void
    let showAbout: @MainActor () -> Void
    let quit: @MainActor () -> Void

    public init(activate: @escaping @MainActor () -> Void, showAbout: @escaping @MainActor () -> Void, quit: @escaping @MainActor () -> Void) {
        self.activate = activate
        self.showAbout = showAbout
        self.quit = quit
    }
}

/// Composition root: connects the sampling engine to the status item, menu and dashboard.
@MainActor
public final class AppController {
    public typealias EngineFactory = (@escaping @Sendable (MonitorSnapshot) -> Void) -> SamplingEngine

    private let topology: CPUTopology
    private let settings: SettingsStore
    private let loginItem: LoginItemControlling
    private let identities: ProcessIdentityResolver
    private let statusBar: NSStatusBar
    private let workspaceCenter: NotificationCenter
    private let actions: AppActions
    private let makeEngine: EngineFactory
    private var engine: SamplingEngine?
    private var observers: [NSObjectProtocol] = []
    private var latest = MonitorSnapshot.empty

    private lazy var demand = ProcessDemand { [weak self] active in self?.engine?.setProcessDemand(active) }
    lazy var statusItem = StatusItemController(statusBar: statusBar, menu: menu.menu)
    lazy var dashboard = DashboardWindowController { [weak self] visible in self?.dashboardVisibilityChanged(visible) }
    lazy var menu = StatusMenuController(clusterNames: clusterNames, actions: StatusMenuController.Actions(
        openDashboard: { [weak self] in self?.openDashboard() },
        selectInterval: { [weak self] interval in self?.select(interval) },
        toggleLaunchAtLogin: { [weak self] in self?.toggleLaunchAtLogin() },
        showAbout: { [weak self] in self?.actions.showAbout() },
        quit: { [weak self] in self?.actions.quit() },
        menuVisibilityChanged: { [weak self] visible in self?.menuVisibilityChanged(visible) }
    ))

    public init(
        topology: CPUTopology,
        settings: SettingsStore,
        loginItem: LoginItemControlling,
        identities: ProcessIdentityResolver,
        statusBar: NSStatusBar,
        workspaceCenter: NotificationCenter,
        actions: AppActions,
        makeEngine: @escaping EngineFactory
    ) {
        self.topology = topology
        self.settings = settings
        self.loginItem = loginItem
        self.identities = identities
        self.statusBar = statusBar
        self.workspaceCenter = workspaceCenter
        self.actions = actions
        self.makeEngine = makeEngine
    }

    public static func live(statusBar: NSStatusBar = .system, actions: AppActions) -> AppController {
        let topology = TopologyReader().read(coreCount: ProcessInfo.processInfo.processorCount)
        let settings = UserDefaultsSettings(defaults: .standard)
        let ticks = CPUTicksReader()
        let temperature = CPUTemperatureReader.live()
        let processes = TopProcessesService.live()
        let scheduler = DispatchScheduler(queue: DispatchQueue(label: "io.github.arrrlo.macos-processor-monitor.sampling", qos: .utility))
        return AppController(
            topology: topology,
            settings: settings,
            loginItem: LaunchAgentLoginItem.live(),
            identities: .live(),
            statusBar: statusBar,
            workspaceCenter: NSWorkspace.shared.notificationCenter,
            actions: actions,
            makeEngine: { publish in
                SamplingEngine(
                    sources: SamplingEngine.Sources(
                        cpuTicks: ticks.read,
                        temperature: temperature.read,
                        topProcesses: processes,
                        topology: topology
                    ),
                    scheduler: scheduler,
                    interval: settings.refreshInterval.seconds,
                    publish: publish
                )
            }
        )
    }

    private var clusterNames: [String] { topology.clusters.map(\.name) }

    public func start() {
        let engine = makeEngine { [weak self] snapshot in
            Task { @MainActor in self?.render(snapshot) }
        }
        self.engine = engine
        menu.setInterval(settings.refreshInterval)
        syncLoginItem()
        observe(NSWorkspace.screensDidSleepNotification) { $0.engine?.stop() }
        observe(NSWorkspace.screensDidWakeNotification) { $0.engine?.start() }
        engine.start()
    }

    public func stop() {
        engine?.stop()
        observers.forEach(workspaceCenter.removeObserver)
        observers = []
        statusItem.remove()
    }

    /// While the displays sleep nobody can see the menu bar, so sampling pauses entirely.
    private func observe(_ name: Notification.Name, _ handler: @escaping @MainActor (AppController) -> Void) {
        observers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self {
                    handler(self)
                }
            }
        })
    }

    // MARK: - Rendering

    func render(_ snapshot: MonitorSnapshot) {
        latest = snapshot
        statusItem.update(title: MetricFormatter.statusTitle(snapshot))
        refreshMenu()
        refreshDashboard()
    }

    /// The closed menu is not updated; it gets the latest reading when it opens.
    private func refreshMenu() {
        guard demand.menuOpen else { return }
        menu.update(MenuText(latest, clusterNames: clusterNames), apps: resolveApps())
    }

    private func refreshDashboard() {
        guard dashboard.isVisible else { return }
        dashboard.update(DashboardModel(snapshot: latest, clusterNames: clusterNames, apps: resolveApps()))
    }

    private func resolveApps() -> [Int32: AppInfo] {
        identities.resolve(latest.topProcesses?.processes ?? [])
    }

    // MARK: - Menu actions

    private func menuVisibilityChanged(_ visible: Bool) {
        demand.menuOpen = visible
        refreshMenu()
    }

    private func dashboardVisibilityChanged(_ visible: Bool) {
        demand.dashboardVisible = visible
    }

    private func openDashboard() {
        actions.activate()
        dashboard.show()
        refreshDashboard()
    }

    private func select(_ interval: RefreshInterval) {
        settings.refreshInterval = interval
        engine?.setInterval(interval.seconds)
        menu.setInterval(interval)
    }

    private func toggleLaunchAtLogin() {
        loginItem.setEnabled(!loginItem.isEnabled)
        syncLoginItem()
    }

    private func syncLoginItem() {
        menu.setLaunchAtLogin(enabled: loginItem.isEnabled, available: loginItem.isAvailable)
    }
}
