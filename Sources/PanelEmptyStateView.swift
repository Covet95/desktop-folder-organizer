import AppKit

final class PanelEmptyStateView: NSView {
    var onAction: (() -> Void)?

    private let stack = NSStackView()
    private let iconBadge = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let actionButton = PillActionButton()
    private var primaryColor: NSColor = PanelAppearance.primaryText
    private var secondaryColor: NSColor = PanelAppearance.secondaryText
    private var isSearching = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconBadge.wantsLayer = true
        iconBadge.layer?.cornerRadius = 18
        iconBadge.layer?.cornerCurve = .continuous
        iconBadge.layer?.backgroundColor = resolvedCGColor(PanelAppearance.accentSoftFill)
        iconBadge.layer?.borderWidth = 0.75
        iconBadge.layer?.borderColor = resolvedCGColor(PanelAppearance.accentBorder)
        iconBadge.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBadge.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconBadge.widthAnchor.constraint(equalToConstant: 60),
            iconBadge.heightAnchor.constraint(equalToConstant: 60),
            iconView.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28)
        ])

        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 1
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.font = PanelAppearance.Typography.secondary
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.preferredMaxLayoutWidth = 280

        actionButton.onTap = { [weak self] in self?.didTapAction() }

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconBadge)
        stack.setCustomSpacing(14, after: iconBadge)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        stack.setCustomSpacing(16, after: subtitleLabel)
        stack.addArrangedSubview(actionButton)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -6),
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
        applyBadgeStyle()
    }

    private func applyBadgeStyle() {
        let accentTint = isSearching ? NSColor.systemIndigo : PanelAppearance.accent
        iconBadge.layer?.backgroundColor = resolvedCGColor(accentTint.withAlphaComponent(0.15))
        iconBadge.layer?.borderColor = resolvedCGColor(accentTint.withAlphaComponent(0.32))
        iconView.contentTintColor = accentTint
    }

    private func updateContent() {
        let symbolName = isSearching ? "doc.text.magnifyingglass" : "folder.badge.plus"
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 24, weight: .medium))
        applyBadgeStyle()

        titleLabel.stringValue = isSearching ? "没有匹配的文件" : "拖入文件开始整理"
        titleLabel.textColor = primaryColor

        subtitleLabel.stringValue = isSearching
            ? "试试其他关键词，或清除搜索条件"
            : "拖放文件至此或存入桌面，将自动安全归类"
        subtitleLabel.textColor = secondaryColor

        actionButton.configure(
            title: isSearching ? "清除搜索" : "选择并整理文件…",
            symbol: isSearching ? "xmark.circle.fill" : "plus.circle.fill",
            prominent: !isSearching
        )
    }

    @objc private func didTapAction() {
        onAction?()
    }
}

private final class PillActionButton: NSView {
    var onTap: (() -> Void)?

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isPressed = false
    private var prominent = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.cornerCurve = .continuous

        iconView.imageScaling = .scaleProportionallyDown
        label.font = .systemFont(ofSize: 12.5, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, symbol: String, prominent: Bool) {
        self.prominent = prominent
        label.stringValue = title
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12.5, weight: .semibold))
        applyAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        installHoverTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        applyAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressed = false
        applyAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        applyAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        applyAppearance()
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onTap?()
        }
    }

    private func applyAppearance() {
        if prominent {
            let base = NSColor.systemBlue
            let fill = isPressed
                ? base.withAlphaComponent(0.78)
                : (isHovering ? base.withAlphaComponent(0.92) : base)
            layer?.backgroundColor = resolvedCGColor(fill)
            layer?.borderWidth = 0
            label.textColor = .white
            iconView.contentTintColor = .white
        } else {
            let fill = isPressed
                ? PanelAppearance.controlPressed
                : (isHovering ? PanelAppearance.controlHover : PanelAppearance.controlFill)
            layer?.backgroundColor = resolvedCGColor(fill)
            layer?.borderWidth = 0.5
            layer?.borderColor = resolvedCGColor(PanelAppearance.controlBorder)
            label.textColor = PanelAppearance.primaryText
            iconView.contentTintColor = PanelAppearance.secondaryText
        }
    }
}
