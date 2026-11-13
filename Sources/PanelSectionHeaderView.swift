import AppKit

/// A semantic section heading, without a secondary glass or colored panel.
/// A category-tinted chip heading with quiet inline count and no heavy divider rules.
final class PanelSectionHeaderView: NSView {
    private let iconBadge = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private var currentGroup: FileDisplayGroup?
    private var currentTint: NSColor = PanelAppearance.secondaryText

    override var isFlipped: Bool { true }

    init(group: FileDisplayGroup, count: Int) {
        super.init(frame: .zero)

        iconBadge.wantsLayer = true
        iconBadge.layer?.cornerRadius = 5.5
        iconBadge.layer?.cornerCurve = .continuous
        addSubview(iconBadge)

        iconView.imageScaling = .scaleProportionallyDown
        iconBadge.addSubview(iconView)

        titleLabel.font = PanelAppearance.Typography.sectionTitle
        titleLabel.textColor = PanelAppearance.primaryTextSoft
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        countLabel.font = PanelAppearance.Typography.sectionCount
        countLabel.textColor = PanelAppearance.tertiaryText
        addSubview(countLabel)

        configure(group: group, count: count)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(group: FileDisplayGroup, count: Int) {
        if currentGroup != group {
            currentGroup = group
            currentTint = PanelAppearance.tint(for: group)
            iconView.image = NSImage(
                systemSymbolName: Self.symbol(for: group),
                accessibilityDescription: group.title
            )?.withSymbolConfiguration(.init(pointSize: 10.5, weight: .semibold))
            iconView.contentTintColor = currentTint
            iconBadge.layer?.backgroundColor = resolvedCGColor(currentTint.withAlphaComponent(0.16))
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
        iconBadge.frame = CGRect(x: 1, y: 2, width: 18, height: 18)
        iconView.frame = CGRect(x: 3, y: 3, width: 12, height: 12)

        let titleWidth = ceil(titleLabel.sizeThatFits(NSSize(width: max(0, width - 56), height: 16)).width)
        let countWidth = ceil(countLabel.sizeThatFits(NSSize(width: 40, height: 15)).width)
        let maxTitleWidth = max(0, width - iconBadge.frame.maxX - 16 - countWidth)
        let finalTitleWidth = min(titleWidth, maxTitleWidth)

        titleLabel.frame = CGRect(x: iconBadge.frame.maxX + 7, y: 3, width: finalTitleWidth, height: 16)
        countLabel.frame = CGRect(x: titleLabel.frame.maxX + 6, y: 3.5, width: countWidth, height: 15)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        iconBadge.layer?.backgroundColor = resolvedCGColor(currentTint.withAlphaComponent(0.16))
        titleLabel.textColor = PanelAppearance.primaryTextSoft
        countLabel.textColor = PanelAppearance.tertiaryText
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
