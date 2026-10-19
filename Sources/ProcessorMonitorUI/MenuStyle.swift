import AppKit
import ProcessorMonitorCore

/// Menu rows are "title<TAB>value" with the value right-aligned in monospaced digits, so the
/// numbers do not jitter as they change.
@MainActor
enum MenuStyle {
    static let valueColumn: CGFloat = 270
    static let iconSize = NSSize(width: 16, height: 16)

    static let paragraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: valueColumn)]
        return style
    }()

    static func row(_ row: MenuText.Row) -> NSAttributedString {
        NSAttributedString(string: "\(row.title)\t\(row.value)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
    }

    static func header(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    static func menuIcon(_ image: NSImage) -> NSImage {
        let icon = image.copy() as! NSImage
        icon.size = iconSize
        return icon
    }
}
