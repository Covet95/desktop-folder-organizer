import AppKit

enum PanelAppearance {
    static func material(for level: PanelLevelMode) -> NSVisualEffectView.Material {
        switch level {
        case .desktop:
            // Sample the actual desktop wallpaper; do not add a custom color wash.
            return .underWindowBackground
        case .floating:
            return .popover
        }
    }

    static var primaryText: NSColor { .labelColor }
    static var secondaryText: NSColor { .secondaryLabelColor }
    static var tertiaryText: NSColor { .tertiaryLabelColor }

    // Neutral semantic chrome adapts to the system appearance.
    static var border: NSColor { NSColor.separatorColor.withAlphaComponent(0.26) }
    static var controlFill: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.12) }

    static var itemHover: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.18) }
    static var itemDrop: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.18) }

    static let minimumMaterialOpacity = PanelDefaults.minimumMaterialOpacity
    static let maximumMaterialOpacity = PanelDefaults.maximumMaterialOpacity
    static let defaultMaterialOpacity = PanelDefaults.materialOpacity
}
