import AppKit

/// The menu bar item: a CPU glyph and "23%  49°C". Redrawing it is the app's main running cost,
/// so the item has a fixed length (a changing reading never resizes it, which would re-lay out
/// the menu bar and send a scene update to the system) and the title is only set when it changes.
@MainActor
public final class StatusItemController {
    static let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    /// Glyph (16 pt), spacing and margins around the widest reading.
    static let length = ceil(("100%  100°C" as NSString).size(withAttributes: [.font: font]).width) + 30

    private let statusBar: NSStatusBar
    let item: NSStatusItem
    private var title = ""
    private(set) var titleChanges = 0

    public init(statusBar: NSStatusBar, menu: NSMenu) {
        self.statusBar = statusBar
        item = statusBar.statusItem(withLength: Self.length)
        item.menu = menu
        item.button?.font = Self.font
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
