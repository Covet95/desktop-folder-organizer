import AppKit

/// Native macOS semantic colors, adaptive frosted card tokens, category tints, and SF typography.
/// Keep the outer glass material system-controlled; these tokens style only interior content.
enum PanelAppearance {
    static var primaryText: NSColor { .labelColor }
    static var primaryTextSoft: NSColor {
        dynamicColor(
            light: NSColor(calibratedWhite: 0.08, alpha: 0.88),
            dark: NSColor(calibratedWhite: 0.96, alpha: 0.92)
        )
    }
    static var secondaryText: NSColor { .secondaryLabelColor }
    static var tertiaryText: NSColor { .tertiaryLabelColor }
    static var toolbarIconIdle: NSColor {
        dynamicColor(
            light: NSColor(calibratedWhite: 0.14, alpha: 0.78),
            dark: NSColor(calibratedWhite: 0.92, alpha: 0.78)
        )
    }
    static var toolbarIconEmphasis: NSColor {
        dynamicColor(
            light: NSColor(calibratedWhite: 0.06, alpha: 0.96),
            dark: NSColor(calibratedWhite: 1.0, alpha: 0.96)
        )
    }

    static var accent: NSColor { .systemBlue }
    static var accentSoftFill: NSColor { NSColor.systemBlue.withAlphaComponent(0.15) }
    static var accentBorder: NSColor { NSColor.systemBlue.withAlphaComponent(0.32) }

    static var controlFill: NSColor {
        dynamicColor(
            light: NSColor.black.withAlphaComponent(0.055),
            dark: NSColor.white.withAlphaComponent(0.085)
        )
    }
    static var controlHover: NSColor {
        dynamicColor(
            light: NSColor.black.withAlphaComponent(0.10),
            dark: NSColor.white.withAlphaComponent(0.15)
        )
    }
    static var controlPressed: NSColor {
        dynamicColor(
            light: NSColor.black.withAlphaComponent(0.15),
            dark: NSColor.white.withAlphaComponent(0.22)
        )
    }
    static var controlBorder: NSColor {
        dynamicColor(
            light: NSColor.black.withAlphaComponent(0.08),
            dark: NSColor.white.withAlphaComponent(0.12)
        )
    }

    static var cardFill: NSColor {
        dynamicColor(
            light: NSColor.white.withAlphaComponent(0.62),
            dark: NSColor.white.withAlphaComponent(0.065)
        )
    }
    static var cardBorder: NSColor {
        dynamicColor(
            light: NSColor.black.withAlphaComponent(0.07),
            dark: NSColor.white.withAlphaComponent(0.10)
        )
    }

    static var itemTileFill: NSColor {
        dynamicColor(
            light: NSColor.white.withAlphaComponent(0.68),
            dark: NSColor.white.withAlphaComponent(0.075)
        )
    }
    static var itemTileBorder: NSColor {
        dynamicColor(
            light: NSColor.black.withAlphaComponent(0.075),
            dark: NSColor.white.withAlphaComponent(0.11)
        )
    }
    static var itemHover: NSColor {
        dynamicColor(
            light: NSColor.white.withAlphaComponent(0.84),
            dark: NSColor.white.withAlphaComponent(0.125)
        )
    }
    static var itemPressed: NSColor {
        dynamicColor(
            light: NSColor.white.withAlphaComponent(0.95),
            dark: NSColor.white.withAlphaComponent(0.18)
        )
    }
    static var itemHoverBorder: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.45) }
    static var itemDrop: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.20) }
    static var itemDropBorder: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.82) }

    static func tint(for group: FileDisplayGroup) -> NSColor {
        switch group {
        case .folders: return .systemBlue
        case .images: return .systemPurple
        case .documents: return .systemIndigo
        case .spreadsheets: return .systemGreen
        case .presentations: return .systemOrange
        case .videos: return .systemPink
        case .audio: return .systemTeal
        case .archives: return .systemBrown
        case .code: return .systemCyan
        case .other: return .secondaryLabelColor
        }
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }

    enum Typography {
        static var toolbarTitle: NSFont { .systemFont(ofSize: 13.5, weight: .semibold) }
        static var toolbarDetail: NSFont { .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium) }
        static var sectionTitle: NSFont { .systemFont(ofSize: 11.5, weight: .semibold) }
        static var sectionCount: NSFont { .monospacedDigitSystemFont(ofSize: 11, weight: .medium) }
        static var fileName: NSFont { .systemFont(ofSize: 11, weight: .medium) }
        static var secondary: NSFont { .systemFont(ofSize: 12, weight: .regular) }
        static var settingsTitle: NSFont { .systemFont(ofSize: 15, weight: .semibold) }
        static var settingsSection: NSFont { .systemFont(ofSize: 11, weight: .semibold) }
        static var settingsLabel: NSFont { .systemFont(ofSize: 12.5, weight: .regular) }
        static var settingsDetail: NSFont { .systemFont(ofSize: 11, weight: .regular) }
        static var button: NSFont { .systemFont(ofSize: 12, weight: .medium) }
        static var activityTitle: NSFont { .systemFont(ofSize: 15, weight: .semibold) }
        static var activityRow: NSFont { .systemFont(ofSize: 12, weight: .regular) }
    }

    enum Grid {
        static let iconSize: CGFloat = 40
        static let tileHeight: CGFloat = 90
        static let columnSpacing: CGFloat = 8
        static let rowSpacing: CGFloat = 8
        static let minTileWidth: CGFloat = 80
        static let sectionHeaderHeight: CGFloat = 22
        static let sectionGap: CGFloat = 10
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
