import AppKit

/// Native macOS semantic colors and a shared SF typography scale.
/// Keep the glass material system-controlled; these tokens style only content.
enum PanelAppearance {
    static var primaryText: NSColor { .labelColor }
    static var secondaryText: NSColor { .secondaryLabelColor }
    static var tertiaryText: NSColor { .tertiaryLabelColor }

    static var controlFill: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.16) }
    static var controlHover: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.26) }
    static var controlPressed: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.38) }
    static var controlBorder: NSColor { NSColor.separatorColor.withAlphaComponent(0.22) }

    static var cardFill: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.11) }
    static var cardBorder: NSColor { NSColor.separatorColor.withAlphaComponent(0.20) }

    static var itemHover: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.19) }
    static var itemPressed: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.31) }
    static var itemHoverBorder: NSColor { NSColor.separatorColor.withAlphaComponent(0.22) }
    static var itemDrop: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.20) }
    static var itemDropBorder: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.75) }
    static var sectionRule: NSColor { NSColor.separatorColor.withAlphaComponent(0.16) }
    static var sectionBadgeFill: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.18) }
    static var toolbarHairline: NSColor { NSColor.separatorColor.withAlphaComponent(0.15) }

    enum Typography {
        static var toolbarTitle: NSFont { .systemFont(ofSize: 13.5, weight: .semibold) }
        static var toolbarDetail: NSFont { .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold) }
        static var sectionTitle: NSFont { .systemFont(ofSize: 11.5, weight: .semibold) }
        static var sectionCount: NSFont { .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold) }
        static var fileName: NSFont { .systemFont(ofSize: 11.5, weight: .medium) }
        static var secondary: NSFont { .systemFont(ofSize: 11.5, weight: .regular) }
        static var settingsTitle: NSFont { .systemFont(ofSize: 15, weight: .semibold) }
        static var settingsSection: NSFont { .systemFont(ofSize: 11, weight: .semibold) }
        static var settingsLabel: NSFont { .systemFont(ofSize: 12.5, weight: .regular) }
        static var settingsDetail: NSFont { .systemFont(ofSize: 11, weight: .regular) }
        static var button: NSFont { .systemFont(ofSize: 12, weight: .medium) }
        static var activityTitle: NSFont { .systemFont(ofSize: 15, weight: .semibold) }
        static var activityRow: NSFont { .systemFont(ofSize: 12, weight: .regular) }
    }

    enum Grid {
        static let iconSize: CGFloat = 44
        static let tileHeight: CGFloat = 94
        static let columnSpacing: CGFloat = 8
        static let rowSpacing: CGFloat = 8
        static let minTileWidth: CGFloat = 80
        static let sectionHeaderHeight: CGFloat = 26
        static let sectionGap: CGFloat = 12
    }

    enum Window {
        static let minPanelSize = CGSize(width: 280, height: 220)
        static let maxPanelSize = CGSize(width: 960, height: 820)
    }
}

extension PanelAppearanceMode {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

extension NSView {
    /// Resolve dynamic semantic `NSColor`s inside this view's effective appearance for Core Animation layers.
    func resolvedCGColor(_ color: NSColor) -> CGColor {
        var resolved = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved
    }

    func installHoverTrackingArea(_ existing: inout NSTrackingArea?) {
        if let existing {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        existing = area
    }
}

extension NSAlert {
    func present(from window: NSWindow?, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(runModal())
        }
    }

    static func showMessage(
        title: String,
        message: String,
        style: NSAlert.Style = .warning,
        from window: NSWindow? = nil
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.present(from: window) { _ in }
    }
}
