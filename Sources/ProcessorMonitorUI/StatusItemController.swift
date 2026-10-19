import AppKit

/// The menu bar item: a CPU glyph and "23%  49°C". The title is only touched when the text
/// changes, which avoids redrawing the menu bar every tick.
@MainActor
public final class StatusItemController {
    private let statusBar: NSStatusBar
    let item: NSStatusItem
    private var title = ""
    private(set) var titleChanges = 0

    public init(statusBar: NSStatusBar, menu: NSMenu) {
        self.statusBar = statusBar
        item = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = menu
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        item.button?.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Processor")
        item.button?.imagePosition = .imageLeading
        item.button?.toolTip = "macOS Processor Monitor"
        update(title: "—  —")
    }

    public func update(title: String) {
        guard title != self.title else { return }
        self.title = title
        titleChanges += 1
        item.button?.title = title
    }

    public func remove() {
        statusBar.removeStatusItem(item)
    }
}
