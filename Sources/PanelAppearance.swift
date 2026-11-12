import AppKit

/// Native macOS semantic colors and a shared SF typography scale.
/// Keep the glass material system-controlled; these tokens style only content.
enum PanelAppearance {
    static var primaryText: NSColor { .labelColor }
    static var secondaryText: NSColor { .secondaryLabelColor }
    static var tertiaryText: NSColor { .tertiaryLabelColor }

    static var controlFill: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.12) }
    static var itemHover: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.18) }
    static var itemDrop: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.18) }
    static var sectionRule: NSColor { NSColor.separatorColor.withAlphaComponent(0.55) }

    enum Typography {
        static var toolbarTitle: NSFont { .systemFont(ofSize: 13, weight: .semibold) }
        static var toolbarDetail: NSFont { .systemFont(ofSize: 11, weight: .regular) }
        static var sectionTitle: NSFont { .systemFont(ofSize: 13, weight: .semibold) }
        static var sectionCount: NSFont { .monospacedDigitSystemFont(ofSize: 11, weight: .medium) }
        static var fileName: NSFont { .systemFont(ofSize: 12, weight: .regular) }
        static var secondary: NSFont { .systemFont(ofSize: 12, weight: .regular) }
        static var settingsTitle: NSFont { .systemFont(ofSize: 16, weight: .semibold) }
        static var settingsSection: NSFont { .systemFont(ofSize: 11, weight: .semibold) }
        static var settingsLabel: NSFont { .systemFont(ofSize: 13, weight: .regular) }
        static var settingsDetail: NSFont { .systemFont(ofSize: 11, weight: .regular) }
        static var button: NSFont { .systemFont(ofSize: 12, weight: .medium) }
        static var activityTitle: NSFont { .systemFont(ofSize: 15, weight: .semibold) }
        static var activityRow: NSFont { .systemFont(ofSize: 12, weight: .regular) }
    }

    enum Grid {
        static let iconSize: CGFloat = 46
        static let tileHeight: CGFloat = 92
        static let columnSpacing: CGFloat = 9
        static let rowSpacing: CGFloat = 10
        static let minTileWidth: CGFloat = 94
        static let sectionHeaderHeight: CGFloat = 29
        static let sectionGap: CGFloat = 14
    }
}
