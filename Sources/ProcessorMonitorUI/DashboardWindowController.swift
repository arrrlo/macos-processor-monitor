import AppKit
import SwiftUI

/// Creates the dashboard window when first shown and releases it on close, so no SwiftUI
/// work happens while it is not on screen.
@MainActor
public final class DashboardWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    private var host: NSHostingController<DashboardView>?
    private(set) var model = DashboardModel(snapshot: .empty, clusterNames: [], apps: [:])
    private let onVisibilityChanged: (Bool) -> Void
    public private(set) var isVisible = false

    public init(onVisibilityChanged: @escaping (Bool) -> Void) {
        self.onVisibilityChanged = onVisibilityChanged
    }

    public func show() {
        let window = self.window ?? makeWindow()
        window.makeKeyAndOrderFront(nil)
        setVisible(true)
    }

    public func update(_ model: DashboardModel) {
        self.model = model
        host?.rootView = DashboardView(model: model)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: DashboardView(model: model))
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(host.view.fittingSize)
        window.title = "macOS Processor Monitor"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        self.host = host
        return window
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
        host = nil
        setVisible(false)
    }

    /// Minimised or fully covered counts as not visible: no process sampling for it.
    public func windowDidChangeOcclusionState(_ notification: Notification) {
        setVisible(window?.occlusionState.contains(.visible) == true)
    }

    private func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        onVisibilityChanged(visible)
    }
}
