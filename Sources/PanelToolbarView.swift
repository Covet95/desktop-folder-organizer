import AppKit

final class ToolbarIconButton: NSButton {
    private var isHovering = false
    private var isButtonPressed = false
    private var trackingArea: NSTrackingArea?

    init(symbol: String, tooltip: String, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        self.image = image?.withSymbolConfiguration(.init(pointSize: 12.5, weight: .medium))
        self.imagePosition = .imageOnly
        self.imageScaling = .scaleProportionallyDown
        self.isBordered = false
        self.bezelStyle = .inline
        self.toolTip = tooltip
        self.target = target
        self.action = action
        self.wantsLayer = true
        self.layer?.cornerRadius = 12
        self.layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        installHoverTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateFill()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isButtonPressed = false
        updateFill()
    }

    override func mouseDown(with event: NSEvent) {
        isButtonPressed = true
        updateFill()
        super.mouseDown(with: event)
        isButtonPressed = false
        updateFill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFill()
    }

    private func updateFill() {
        if isButtonPressed {
            layer?.backgroundColor = resolvedCGColor(PanelAppearance.controlPressed)
        } else if isHovering {
            layer?.backgroundColor = resolvedCGColor(PanelAppearance.controlHover)
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

final class PanelToolbarView: NSView, NSTextFieldDelegate {
    var onSearchChanged: ((String) -> Void)?
    var onSearchRequested: (() -> Void)?
    var onAddRequested: (() -> Void)?
    var onSettingsRequested: (() -> Void)?
    var onStatusRequested: (() -> Void)?
    var onBackgroundMouseDown: ((NSEvent) -> Void)?

    let searchField = NSTextField()
    private(set) lazy var settingsButton = ToolbarIconButton(
        symbol: "gearshape",
        tooltip: "面板设置",
        target: self,
        action: #selector(didTapSettings)
    )
    private lazy var searchButton = ToolbarIconButton(
        symbol: "magnifyingglass",
        tooltip: "搜索文件 (⌘F)",
        target: self,
        action: #selector(didTapSearch)
    )
    private lazy var addButton = ToolbarIconButton(
        symbol: "plus",
        tooltip: "添加文件（移动原文件）",
        target: self,
        action: #selector(didTapAdd)
    )

    private let leadingBadge = NSView()
    private let leadingIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "文档整理")
    private let countLabel = NSTextField(labelWithString: "·  0 项")
    private let lockIcon = NSImageView()
    private let statusPill = NSButton()
    private let actionCluster = NSView()
    private let searchContainer = NSView()
    private let searchLeadingIcon = NSImageView()
    private lazy var searchCloseButton = ToolbarIconButton(
        symbol: "xmark",
        tooltip: "关闭搜索 (Esc)",
        target: self,
        action: #selector(didTapSearch)
    )

    private var isHovering = false
    private var forceVisible = false
    private var searchVisible = false
    private var itemCount = 0
    private var isLocked = false
    private var hasAttentionStatus = false
    private var primaryColor = PanelAppearance.primaryText
    private var secondaryColor = PanelAppearance.secondaryText

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        leadingBadge.wantsLayer = true
        leadingBadge.layer?.cornerRadius = 6.5
        leadingBadge.layer?.cornerCurve = .continuous
        leadingBadge.layer?.backgroundColor = resolvedCGColor(PanelAppearance.accentSoftFill)
        leadingBadge.layer?.borderWidth = 0.5
        leadingBadge.layer?.borderColor = resolvedCGColor(PanelAppearance.accentBorder)
        addSubview(leadingBadge)

        leadingIcon.image = NSImage(
            systemSymbolName: "folder.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        leadingIcon.imageScaling = .scaleProportionallyDown
        leadingIcon.contentTintColor = PanelAppearance.accent
        leadingBadge.addSubview(leadingIcon)

        titleLabel.font = PanelAppearance.Typography.toolbarTitle
        titleLabel.textColor = primaryColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        countLabel.font = PanelAppearance.Typography.toolbarDetail
        countLabel.textColor = secondaryColor
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(countLabel)

        lockIcon.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "位置已锁定")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        lockIcon.imageScaling = .scaleProportionallyDown
        lockIcon.contentTintColor = secondaryColor
        lockIcon.toolTip = "面板位置已锁定"
        lockIcon.isHidden = true
        addSubview(lockIcon)

        statusPill.isBordered = false
        statusPill.bezelStyle = .inline
        statusPill.imagePosition = .imageOnly
        statusPill.imageScaling = .scaleProportionallyDown
        statusPill.target = self
        statusPill.action = #selector(didTapStatus)
        statusPill.isHidden = true
        addSubview(statusPill)

        actionCluster.wantsLayer = true
        actionCluster.layer?.cornerRadius = 14
        actionCluster.layer?.cornerCurve = .continuous
        actionCluster.layer?.backgroundColor = resolvedCGColor(PanelAppearance.controlFill)
        actionCluster.layer?.borderWidth = 0.5
        actionCluster.layer?.borderColor = resolvedCGColor(PanelAppearance.controlBorder)
        addSubview(actionCluster)
        actionCluster.addSubview(searchButton)
        actionCluster.addSubview(addButton)
        actionCluster.addSubview(settingsButton)

        searchContainer.wantsLayer = true
        searchContainer.layer?.cornerRadius = 15
        searchContainer.layer?.cornerCurve = .continuous
        searchContainer.layer?.backgroundColor = resolvedCGColor(PanelAppearance.cardFill)
        searchContainer.layer?.borderWidth = 0.75
        searchContainer.layer?.borderColor = resolvedCGColor(PanelAppearance.accentBorder)
        searchContainer.isHidden = true
        addSubview(searchContainer)

        searchLeadingIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "搜索")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        searchLeadingIcon.imageScaling = .scaleProportionallyDown
        searchLeadingIcon.contentTintColor = PanelAppearance.accent
        searchContainer.addSubview(searchLeadingIcon)

        searchField.delegate = self
        searchField.placeholderString = "搜索文件名…"
        searchField.font = PanelAppearance.Typography.settingsLabel
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.maximumNumberOfLines = 1
        searchField.lineBreakMode = .byTruncatingHead
        if let cell = searchField.cell as? NSTextFieldCell {
            cell.usesSingleLineMode = true
            cell.wraps = false
            cell.isScrollable = true
        }
        searchContainer.addSubview(searchField)
        searchContainer.addSubview(searchCloseButton)

        updateTools()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyLayerColors()
    }

    func applyAppearance(primaryColor: NSColor, secondaryColor: NSColor) {
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        titleLabel.textColor = primaryColor
        countLabel.textColor = secondaryColor
        lockIcon.contentTintColor = secondaryColor
        searchField.textColor = primaryColor
        applyLayerColors()
        updateTools()
    }

    private func applyLayerColors() {
        leadingBadge.layer?.backgroundColor = resolvedCGColor(PanelAppearance.accentSoftFill)
        leadingBadge.layer?.borderColor = resolvedCGColor(PanelAppearance.accentBorder)
        actionCluster.layer?.backgroundColor = resolvedCGColor(PanelAppearance.controlFill)
        actionCluster.layer?.borderColor = resolvedCGColor(PanelAppearance.controlBorder)
        searchContainer.layer?.backgroundColor = resolvedCGColor(PanelAppearance.cardFill)
        searchContainer.layer?.borderColor = resolvedCGColor(PanelAppearance.accentBorder)
    }

    func setItemCount(_ count: Int) {
        guard itemCount != count else { return }
        itemCount = count
        countLabel.stringValue = "·  \(count) 项"
        needsLayout = true
    }

    func setLocked(_ locked: Bool) {
        guard isLocked != locked else { return }
        isLocked = locked
        lockIcon.isHidden = searchVisible || !locked
        needsLayout = true
    }

    func setAutoAbsorbStatus(_ status: AutoAbsorbStatus, persistenceWarning: String?) {
        if let persistenceWarning {
            hasAttentionStatus = true
            statusPill.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: "配置警告"
            )?.withSymbolConfiguration(.init(pointSize: 11.5, weight: .semibold))
            statusPill.contentTintColor = .systemOrange
            statusPill.toolTip = persistenceWarning
            statusPill.isHidden = searchVisible
        } else {
            switch status.phase {
            case .monitoring:
                hasAttentionStatus = false
                statusPill.isHidden = true
            case .processing:
                hasAttentionStatus = true
                statusPill.image = NSImage(
                    systemSymbolName: "arrow.down.circle.fill",
                    accessibilityDescription: status.phase.title
                )?.withSymbolConfiguration(.init(pointSize: 11.5, weight: .medium))
                statusPill.contentTintColor = .controlAccentColor
                statusPill.toolTip = "\(status.phase.title)：\(status.detail)"
                statusPill.isHidden = searchVisible
            case .retrying, .attention:
                hasAttentionStatus = true
                statusPill.image = NSImage(
                    systemSymbolName: "exclamationmark.triangle.fill",
                    accessibilityDescription: status.phase.title
                )?.withSymbolConfiguration(.init(pointSize: 11.5, weight: .semibold))
                statusPill.contentTintColor = .systemOrange
                statusPill.toolTip = "\(status.phase.title)：\(status.detail)"
                statusPill.isHidden = searchVisible
            }
        }
        needsLayout = true
    }

    func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        updateTools()
    }

    func setForcedVisible(_ visible: Bool) {
        guard forceVisible != visible else { return }
        forceVisible = visible
        updateTools()
    }

    func setSearchText(_ text: String) {
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    func setSearchVisible(_ visible: Bool, text: String) {
        searchVisible = visible
        searchContainer.isHidden = !visible
        leadingBadge.isHidden = visible
        titleLabel.isHidden = visible
        countLabel.isHidden = visible
        actionCluster.isHidden = visible
        lockIcon.isHidden = visible || !isLocked
        statusPill.isHidden = visible || !hasAttentionStatus

        if visible {
            setSearchText(text)
            needsLayout = true
            window?.makeFirstResponder(searchField)
            if let editor = searchField.currentEditor() {
                editor.selectedRange = NSRange(location: searchField.stringValue.count, length: 0)
            }
        } else {
            if let editor = searchField.currentEditor(), window?.firstResponder === editor {
                window?.makeFirstResponder(nil)
            }
            searchField.stringValue = ""
            needsLayout = true
        }
        updateTools()
    }

    override func layout() {
        super.layout()

        let height = bounds.height
        let width = bounds.width
        let clusterHeight: CGFloat = 28
        let buttonSize: CGFloat = 24
        let clusterWidth = buttonSize * 3 + 6
        let clusterX = max(0, width - clusterWidth)
        actionCluster.frame = CGRect(
            x: clusterX,
            y: (height - clusterHeight) / 2,
            width: clusterWidth,
            height: clusterHeight
        )
        for (idx, button) in [searchButton, addButton, settingsButton].enumerated() {
            button.frame = CGRect(
                x: 3 + CGFloat(idx) * buttonSize,
                y: (clusterHeight - buttonSize) / 2,
                width: buttonSize,
                height: buttonSize
            )
        }

        var rightX = clusterX - 4
        if !statusPill.isHidden {
            rightX -= 22
            statusPill.frame = CGRect(x: rightX, y: (height - 22) / 2, width: 22, height: 22)
            rightX -= 4
        }

        let leadingWidthLimit = max(0, rightX - 4)
        let badgeSize: CGFloat = 22
        leadingBadge.frame = CGRect(x: 0, y: (height - badgeSize) / 2, width: badgeSize, height: badgeSize)
        leadingIcon.frame = CGRect(x: 4, y: 4, width: 14, height: 14)

        let titleX = badgeSize + 8
        let titleSize = titleLabel.sizeThatFits(NSSize(width: leadingWidthLimit, height: 20))
        let countTextWidth = ceil(countLabel.sizeThatFits(NSSize(width: 80, height: 16)).width)
        let lockWidth: CGFloat = (!lockIcon.isHidden) ? 14 : 0
        let lockGap: CGFloat = (!lockIcon.isHidden) ? 5 : 0
        let reservedForCount = titleX + countTextWidth + 6 + lockWidth + lockGap
        let titleWidth = min(titleSize.width, max(0, leadingWidthLimit - reservedForCount))

        titleLabel.frame = CGRect(x: titleX, y: (height - 18) / 2, width: titleWidth, height: 18)
        let countX = titleLabel.frame.maxX + 6
        countLabel.frame = CGRect(
            x: countX,
            y: (height - 15) / 2 + 0.5,
            width: min(countTextWidth, max(0, leadingWidthLimit - countX)),
            height: 15
        )
        if !lockIcon.isHidden {
            lockIcon.frame = CGRect(x: countLabel.frame.maxX + 5, y: (height - 12) / 2, width: 12, height: 12)
        }

        searchContainer.frame = bounds
        let iconSize: CGFloat = 14
        searchLeadingIcon.frame = CGRect(
            x: 11,
            y: (height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        let closeSize: CGFloat = 24
        searchCloseButton.frame = CGRect(
            x: max(0, width - closeSize - 4),
            y: (height - closeSize) / 2,
            width: closeSize,
            height: closeSize
        )
        let fieldHeight = max(17, ceil(searchField.sizeThatFits(NSSize(width: 200, height: 30)).height))
        let fieldX = searchLeadingIcon.frame.maxX + 7
        searchField.frame = CGRect(
            x: fieldX,
            y: (height - fieldHeight) / 2,
            width: max(0, searchCloseButton.frame.minX - fieldX - 4),
            height: fieldHeight
        )
    }

    override func mouseDown(with event: NSEvent) {
        onBackgroundMouseDown?(event)
    }

    private func updateTools() {
        let emphasis = isHovering || forceVisible
        let tint = emphasis ? PanelAppearance.toolbarIconEmphasis : PanelAppearance.toolbarIconIdle
        for button in [searchButton, addButton, settingsButton] {
            button.isHidden = searchVisible
            button.contentTintColor = tint
        }
        searchCloseButton.contentTintColor = secondaryColor
    }

    @objc private func didTapSearch() {
        onSearchRequested?()
    }

    @objc private func didTapAdd() {
        onAddRequested?()
    }

    @objc private func didTapSettings() {
        onSettingsRequested?()
    }

    @objc private func didTapStatus() {
        onStatusRequested?()
    }

    func controlTextDidChange(_ notification: Notification) {
        onSearchChanged?(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        if !searchField.stringValue.isEmpty {
            searchField.stringValue = ""
            onSearchChanged?("")
        } else {
            onSearchRequested?()
        }
        return true
    }
}
