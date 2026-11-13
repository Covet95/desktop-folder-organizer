import AppKit

/// A semantic section heading, without a secondary glass or colored panel.
final class PanelSectionHeaderView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countBadge = NSView()
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
        titleLabel.textColor = PanelAppearance.secondaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        countBadge.wantsLayer = true
        countBadge.layer?.cornerRadius = 8
        countBadge.layer?.cornerCurve = .continuous
        countBadge.layer?.backgroundColor = resolvedCGColor(PanelAppearance.sectionBadgeFill)
        addSubview(countBadge)

        countLabel.font = PanelAppearance.Typography.sectionCount
        countLabel.textColor = PanelAppearance.secondaryText
        countLabel.alignment = .center
        countBadge.addSubview(countLabel)

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
            )?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
            titleLabel.stringValue = group.title
        }
        let countText = String(count)
        if countLabel.stringValue != countText {
            countLabel.stringValue = countText
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let scale = max(1, window?.backingScaleFactor ?? 2)
        let hairline = 1.0 / scale
        iconView.frame = CGRect(x: 2, y: 4, width: 14, height: 14)
        let countTextWidth = ceil(countLabel.sizeThatFits(NSSize(width: 48, height: 14)).width)
        let badgeWidth = max(20, countTextWidth + 10)
        countBadge.frame = CGRect(x: max(0, width - badgeWidth - 2), y: 2.5, width: badgeWidth, height: 16)
        countLabel.frame = CGRect(x: 0, y: 1, width: badgeWidth, height: 14)
        titleLabel.frame = CGRect(x: 21, y: 3, width: max(0, countBadge.frame.minX - 27), height: 16)
        separator.frame = CGRect(x: 2, y: 23, width: max(0, width - 4), height: hairline)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        iconView.contentTintColor = PanelAppearance.secondaryText
        titleLabel.textColor = PanelAppearance.secondaryText
        countLabel.textColor = PanelAppearance.secondaryText
        countBadge.layer?.backgroundColor = resolvedCGColor(PanelAppearance.sectionBadgeFill)
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
