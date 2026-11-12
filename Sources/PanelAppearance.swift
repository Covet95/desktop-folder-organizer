import AppKit

enum PanelAppearance {
    static var primaryText: NSColor { .labelColor }
    static var secondaryText: NSColor { .secondaryLabelColor }
    static var tertiaryText: NSColor { .tertiaryLabelColor }

    static var controlFill: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.12) }
    static var itemHover: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.18) }
    static var itemDrop: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.18) }
}
