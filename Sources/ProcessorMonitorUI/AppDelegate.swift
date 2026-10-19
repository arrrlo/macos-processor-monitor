import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let makeController: () -> AppController
    private let otherInstances: () -> [pid_t]
    private let terminate: () -> Void
    private(set) var controller: AppController?

    public init(
        makeController: @escaping () -> AppController,
        otherInstances: @escaping () -> [pid_t],
        terminate: @escaping () -> Void
    ) {
        self.makeController = makeController
        self.otherInstances = otherInstances
        self.terminate = terminate
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // launchd starts the app at login; opening it by hand as well must not add a second icon.
        guard otherInstances().isEmpty else {
            terminate()
            return
        }
        let controller = makeController()
        self.controller = controller
        controller.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}

public enum SingleInstance {
    static func others(bundleIdentifier: String?, currentPID: pid_t, running: (String) -> [pid_t]) -> [pid_t] {
        guard let bundleIdentifier else { return [] }
        return running(bundleIdentifier).filter { $0 != currentPID }
    }

    static func runningPIDs(bundleIdentifier: String) -> [pid_t] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).map(\.processIdentifier)
    }

    /// Other running copies of this app bundle.
    public static func otherInstances(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> [pid_t] {
        others(bundleIdentifier: bundleIdentifier, currentPID: getpid(), running: runningPIDs)
    }
}
