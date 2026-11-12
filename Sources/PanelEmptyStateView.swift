import AppKit

final class PanelEmptyStateView: NSView {
    var onAction: (() -> Void)?

    private let iconView = NSImageView(frame: .zero)
    private let messageLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private var primaryColor: NSColor = PanelAppearance.primaryText
    private var secondaryColor: NSColor = PanelAppearance.secondaryText
    private var isSearching = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 1
        messageLabel.isEditable = false
        messageLabel.isSelectable = false
        messageLabel.isBezeled = false
        messageLabel.drawsBackground = false
        messageLabel.font = .systemFont(ofSize: 14, weight: .medium)
        addSubview(messageLabel)

        actionButton.isBordered = false
        actionButton.bezelStyle = .inline
        actionButton.controlSize = .small
        actionButton.target = self
        actionButton.action = #selector(didTapAction)
        addSubview(actionButton)

        updateContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(searching: Bool, primaryColor: NSColor, secondaryColor: NSColor) {
        self.isSearching = searching
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        updateContent()
    }

    private func updateContent() {
        iconView.image = NSImage(
            systemSymbolName: isSearching ? "doc.text.magnifyingglass" : "folder.badge.plus",
            accessibilityDescription: nil
        )
        iconView.contentTintColor = secondaryColor
        messageLabel.stringValue = isSearching ? "没有匹配的文件" : "拖入文件或文件夹以移动收纳"
        messageLabel.textColor = secondaryColor
        actionButton.title = isSearching ? "清除搜索" : "选择并移动文件…"
        actionButton.attributedTitle = NSAttributedString(
            string: actionButton.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.controlAccentColor
            ]
        )
        needsLayout = true
    }

    override func layout() {
        super.layout()
        iconView.frame = CGRect(x: bounds.midX - 18, y: bounds.midY - 54, width: 36, height: 36)
        messageLabel.frame = CGRect(x: 0, y: bounds.midY - 10, width: bounds.width, height: 21)
        actionButton.frame = CGRect(x: 0, y: bounds.midY + 24, width: bounds.width, height: 23)
    }

    @objc private func didTapAction() {
        onAction?()
    }
}
