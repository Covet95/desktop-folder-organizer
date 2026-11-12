import AppKit

/// A semantic section heading, without a secondary glass or colored panel.
final class PanelSectionHeaderView: NSView {
    private let iconView = NSImageView()
    private let titleLabel: NSTextField
    private let countLabel: NSTextField
    private let separator = NSView()

    override var isFlipped: Bool { true }

    init(group: FileDisplayGroup, count: Int) {
        titleLabel = NSTextField(labelWithString: group.title)
        countLabel = NSTextField(labelWithString: String(count))
        super.init(frame: .zero)

        iconView.image = NSImage(
            systemSymbolName: Self.symbol(for: group),
            accessibilityDescription: group.title
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
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
        separator.layer?.backgroundColor = PanelAppearance.sectionRule.cgColor
        addSubview(separator)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        iconView.frame = CGRect(x: 2, y: 4, width: 16, height: 16)
        titleLabel.frame = CGRect(x: 24, y: 2, width: max(0, width - 85), height: 20)
        countLabel.frame = CGRect(x: max(0, width - 48), y: 4, width: 46, height: 18)
        separator.frame = CGRect(x: 2, y: 26, width: max(0, width - 4), height: 1)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        iconView.contentTintColor = PanelAppearance.secondaryText
        titleLabel.textColor = PanelAppearance.primaryText
        countLabel.textColor = PanelAppearance.secondaryText
        separator.layer?.backgroundColor = PanelAppearance.sectionRule.cgColor
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
