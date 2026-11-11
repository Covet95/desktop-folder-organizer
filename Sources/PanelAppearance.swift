import AppKit

enum PanelAppearance {
    static let material: NSVisualEffectView.Material = .popover

    static var primaryText: NSColor { .labelColor }
    static var secondaryText: NSColor { .secondaryLabelColor }
    static var tertiaryText: NSColor { .tertiaryLabelColor }
    static var border: NSColor { NSColor.separatorColor.withAlphaComponent(0.42) }
    static var itemHover: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.24) }
    static var itemDrop: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.16) }

    static func materialOpacity(_ value: Double) -> CGFloat {
        CGFloat(min(max(value, 0.4), 1))
    }

    static func tintOpacity(_ value: Double) -> CGFloat {
        CGFloat(0.035 + min(max(value, 0.4), 1) * 0.055)
    }

    static func customTint(for hex: String) -> NSColor? {
        // The original default color now means "follow the macOS material".
        guard hex.caseInsensitiveCompare("#1C1C1E") != .orderedSame else { return nil }
        return NSColor(hex: hex)
    }
}
