import AppKit

enum PanelAppearance {
    static let defaultTintHex = PanelDefaults.backgroundHex
    private static let lightAppearance = NSAppearance(named: .aqua)!
    private static let darkAppearance = NSAppearance(named: .darkAqua)!

    static func material(for level: PanelLevelMode) -> NSVisualEffectView.Material {
        switch level {
        case .desktop:
            // Desktop widgets should sample and blur the wallpaper rather than paint a solid HUD surface.
            return .underWindowBackground
        case .floating:
            return .popover
        }
    }

    static func appearance(for hex: String) -> NSAppearance {
        let name: NSAppearance.Name = NSColor(hex: hex).perceivedLuminance < 0.52
            ? .darkAqua
            : .aqua
        return name == .darkAqua ? darkAppearance : lightAppearance
    }

    static var primaryText: NSColor { .labelColor }
    static var secondaryText: NSColor { .secondaryLabelColor }
    static var tertiaryText: NSColor { .tertiaryLabelColor }
    static func border(for hex: String) -> NSColor {
        let isDark = NSColor(hex: hex).perceivedLuminance < 0.52
        return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.18)
    }

    static func controlFill(for hex: String) -> NSColor {
        let isDark = NSColor(hex: hex).perceivedLuminance < 0.52
        return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.085)
    }

    static var itemHover: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.18) }
    static var itemDrop: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.18) }

    static let minimumMaterialOpacity = PanelDefaults.minimumMaterialOpacity
    static let maximumMaterialOpacity = PanelDefaults.maximumMaterialOpacity
    static let defaultMaterialOpacity = PanelDefaults.materialOpacity
    static let tintOpacity: CGFloat = 0.12

    static func customTint(for hex: String) -> NSColor {
        NSColor(hex: hex)
    }
}
