import AppKit

final class PanelEmptyStateView: NSView {
    var onAction: (() -> Void)?

    private let stack = NSStackView()
    private let iconBadge = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private var primaryColor: NSColor = PanelAppearance.primaryText
    private var secondaryColor: NSColor = PanelAppearance.secondaryText
    private var isSearching = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconBadge.wantsLayer = true
        iconBadge.layer?.cornerRadius = 14
        iconBadge.layer?.cornerCurve = .continuous
        iconBadge.layer?.backgroundColor = resolvedCGColor(PanelAppearance.controlFill)
        iconBadge.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBadge.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconBadge.widthAnchor.constraint(equalToConstant: 48),
            iconBadge.heightAnchor.constraint(equalToConstant: 48),
            iconView.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24)
        ])

        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 1
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.font = PanelAppearance.Typography.secondary
        subtitleLabel.lineBreakMode = .byWordWrapping

        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .regular
        actionButton.target = self
        actionButton.action = #selector(didTapAction)

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconBadge)
        stack.setCustomSpacing(10, after: iconBadge)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        stack.setCustomSpacing(12, after: subtitleLabel)
        stack.addArrangedSubview(actionButton)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20)
        ])

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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        iconBadge.layer?.backgroundColor = resolvedCGColor(PanelAppearance.controlFill)
    }

    private func updateContent() {
        let symbolName = isSearching ? "doc.text.magnifyingglass" : "folder.badge.plus"
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .medium))
        iconView.contentTintColor = secondaryColor
        iconBadge.layer?.backgroundColor = resolvedCGColor(PanelAppearance.controlFill)

        titleLabel.stringValue = isSearching ? "没有匹配的文件" : "面板为空"
        titleLabel.textColor = primaryColor

        subtitleLabel.stringValue = isSearching
            ? "试试其他关键词，或清除搜索条件"
            : "拖入文件或文件夹以自动收纳，桌面新文件也会同步到这里"
        subtitleLabel.textColor = secondaryColor

        actionButton.title = isSearching ? "清除搜索" : "选择并移动文件…"
        actionButton.font = PanelAppearance.Typography.button
    }

    @objc private func didTapAction() {
        onAction?()
    }
}
