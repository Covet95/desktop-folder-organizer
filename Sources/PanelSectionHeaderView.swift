import AppKit

/// A semantic section heading, without a secondary glass or colored panel.
final class PanelSectionHeaderView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let separator = NSView()
    private var currentGroup: FileDisplayGroup?

    override var isFlipped: Bool { true }

    init(group: FileDisplayGroup, count: Int) {
        super.init(frame: .zero)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = PanelAppearance.secondaryText
        addSubview(iconView)

        titleLabel.font = PanelAppearance.Typography.sectionTitle
        titleLabel.textColor = PanelAppearance.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        countLabel.font = PanelAppearance.Typography.sectionCount
        countLabel.textColor = PanelAppearance.secondaryText
        countLabel.alignment = .right
        addSubview(countLabel)

        separator.wantsLayer = true
        separator.layer?.backgroundColor = resolvedCGColor(PanelAppearance.sectionRule)
        addSubview(separator)

        configure(group: group, count: count)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(group: FileDisplayGroup, count: Int) {
        if currentGroup != group {
            currentGroup = group
            iconView.image = NSImage(
                systemSymbolName: Self.symbol(for: group),
                accessibilityDescription: group.title
            )?.withSymbolConfiguration(.init(pointSize: 11.5, weight: .semibold))
            titleLabel.stringValue = group.title
        }
        let countText = String(count)
        if countLabel.stringValue != countText {
            countLabel.stringValue = countText
        }
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let scale = max(1, window?.backingScaleFactor ?? 2)
        let hairline = 1.0 / scale
        iconView.frame = CGRect(x: 2, y: 5, width: 15, height: 15)
        titleLabel.frame = CGRect(x: 22, y: 3, width: max(0, width - 78), height: 19)
        countLabel.frame = CGRect(x: max(0, width - 48), y: 4, width: 46, height: 18)
        separator.frame = CGRect(x: 2, y: 25, width: max(0, width - 4), height: hairline)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        iconView.contentTintColor = PanelAppearance.secondaryText
        titleLabel.textColor = PanelAppearance.primaryText
        countLabel.textColor = PanelAppearance.secondaryText
        separator.layer?.backgroundColor = resolvedCGColor(PanelAppearance.sectionRule)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    private static func symbol(for group: FileDisplayGroup) -> String {
        switch group {
        case .folders: return "folder"
        case .images: return "photo"
        case .documents: return "doc.text"
        case .spreadsheets: return "tablecells"
        case .presentations: return "rectangle.on.rectangle"
        case .videos: return "film"
        case .audio: return "waveform"
        case .archives: return "archivebox"
        case .code: return "curlybraces"
        case .other: return "square.grid.2x2"
        }
    }
}
