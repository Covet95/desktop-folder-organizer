import AppKit

enum PanelAppearance {
    static let defaultTintHex = "#034373"
    private static let lightAppearance = NSAppearance(named: .aqua)!
    private static let darkAppearance = NSAppearance(named: .darkAqua)!

    static func material(for level: PanelLevelMode) -> NSVisualEffectView.Material {
        switch level {
        case .desktop:
            // A dark, wallpaper-sampling glass surface better matches the desktop widget treatment.
            return .hudWindow
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
    static var border: NSColor { NSColor.separatorColor.withAlphaComponent(0.42) }
    static var itemHover: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.24) }
    static var itemDrop: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.16) }

    static func tintOpacity(_ value: Double) -> CGFloat {
        // Preserve a rich tinted-glass surface while leaving the underlying blur visible.
        CGFloat(0.55 + min(max(value, 0.4), 1) * 0.25)
    }

    static func customTint(for hex: String) -> NSColor {
        NSColor(hex: hex)
    }
}
