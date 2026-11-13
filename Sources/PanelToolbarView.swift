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
        self.layer?.cornerRadius = 7
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

    private let leadingIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "文档整理")
    private let countBadge = NSView()
    private let countLabel = NSTextField(labelWithString: "0 项")
    private let lockIcon = NSImageView()
    private let statusPill = NSButton()
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

        leadingIcon.image = NSImage(
            systemSymbolName: "folder.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 12.5, weight: .semibold))
        leadingIcon.imageScaling = .scaleProportionallyDown
        leadingIcon.contentTintColor = secondaryColor
        addSubview(leadingIcon)

        titleLabel.font = PanelAppearance.Typography.toolbarTitle
        titleLabel.textColor = primaryColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        countBadge.wantsLayer = true
        countBadge.layer?.cornerRadius = 8.5
        countBadge.layer?.cornerCurve = .continuous
        countBadge.layer?.backgroundColor = resolvedCGColor(PanelAppearance.sectionBadgeFill)
        addSubview(countBadge)

        countLabel.font = PanelAppearance.Typography.toolbarDetail
        countLabel.textColor = secondaryColor
        countLabel.alignment = .center
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countBadge.addSubview(countLabel)

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

        addSubview(searchButton)
        addSubview(addButton)
        addSubview(settingsButton)

        searchContainer.wantsLayer = true
        searchContainer.layer?.cornerRadius = 9.5
        searchContainer.layer?.cornerCurve = .continuous
        searchContainer.layer?.backgroundColor = resolvedCGColor(PanelAppearance.controlFill)
        searchContainer.layer?.borderWidth = 0.5
        searchContainer.layer?.borderColor = resolvedCGColor(PanelAppearance.controlBorder)
        searchContainer.isHidden = true
        addSubview(searchContainer)

        searchLeadingIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "搜索")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        searchLeadingIcon.imageScaling = .scaleProportionallyDown
        searchLeadingIcon.contentTintColor = secondaryColor
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
        countBadge.layer?.backgroundColor = resolvedCGColor(PanelAppearance.sectionBadgeFill)
        searchContainer.layer?.backgroundColor = resolvedCGColor(PanelAppearance.controlFill)
        searchContainer.layer?.borderColor = resolvedCGColor(PanelAppearance.controlBorder)
    }

    func applyAppearance(primaryColor: NSColor, secondaryColor: NSColor) {
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        leadingIcon.contentTintColor = secondaryColor
        titleLabel.textColor = primaryColor
        countLabel.textColor = secondaryColor
        countBadge.layer?.backgroundColor = resolvedCGColor(PanelAppearance.sectionBadgeFill)
        lockIcon.contentTintColor = secondaryColor
        searchLeadingIcon.contentTintColor = secondaryColor
        searchField.textColor = primaryColor
        searchContainer.layer?.backgroundColor = resolvedCGColor(PanelAppearance.controlFill)
        searchContainer.layer?.borderColor = resolvedCGColor(PanelAppearance.controlBorder)
        updateTools()
    }

    func setItemCount(_ count: Int) {
        guard itemCount != count else { return }
        itemCount = count
        countLabel.stringValue = "\(count) 项"
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
        leadingIcon.isHidden = visible
        titleLabel.isHidden = visible
        countBadge.isHidden = visible
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
        let buttonSize: CGFloat = 26

        var rightX = width
        for button in [settingsButton, addButton, searchButton] {
            rightX -= buttonSize
            button.frame = CGRect(x: rightX, y: (height - buttonSize) / 2, width: buttonSize, height: buttonSize)
            rightX -= 3
        }

        if !statusPill.isHidden {
            rightX -= 22
            statusPill.frame = CGRect(x: rightX, y: (height - 22) / 2, width: 22, height: 22)
            rightX -= 4
        }

        let leadingWidthLimit = max(0, rightX - 6)
        let iconSpace: CGFloat = 20
        leadingIcon.frame = CGRect(x: 1, y: (height - 15) / 2, width: 15, height: 15)
        let titleSize = titleLabel.sizeThatFits(NSSize(width: leadingWidthLimit, height: 20))
        let countTextWidth = ceil(countLabel.sizeThatFits(NSSize(width: 80, height: 14)).width)
        let badgeWidth = countTextWidth + 12
        let lockWidth: CGFloat = (!lockIcon.isHidden) ? 14 : 0
        let lockGap: CGFloat = (!lockIcon.isHidden) ? 5 : 0
        let reservedForCount = iconSpace + badgeWidth + 8 + lockWidth + lockGap
        let titleWidth = min(titleSize.width, max(0, leadingWidthLimit - reservedForCount))

        titleLabel.frame = CGRect(x: iconSpace, y: (height - 18) / 2, width: titleWidth, height: 18)
        let badgeX = titleLabel.frame.maxX + 7
        let clampedBadgeWidth = min(badgeWidth, max(0, leadingWidthLimit - badgeX))
        countBadge.frame = CGRect(
            x: badgeX,
            y: (height - 17) / 2,
            width: clampedBadgeWidth,
            height: 17
        )
        countLabel.frame = CGRect(x: 0, y: 1.5, width: clampedBadgeWidth, height: 14)
        if !lockIcon.isHidden {
            lockIcon.frame = CGRect(x: countBadge.frame.maxX + 5, y: (height - 12) / 2, width: 12, height: 12)
        }

        searchContainer.frame = bounds
        let iconSize: CGFloat = 14
        searchLeadingIcon.frame = CGRect(
            x: 9,
            y: (height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        let closeSize: CGFloat = 24
        searchCloseButton.frame = CGRect(
            x: max(0, width - closeSize - 3),
            y: (height - closeSize) / 2,
            width: closeSize,
            height: closeSize
        )
        let fieldHeight = max(17, ceil(searchField.sizeThatFits(NSSize(width: 200, height: 30)).height))
        let fieldX = searchLeadingIcon.frame.maxX + 6
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
        for button in [searchButton, addButton, settingsButton] {
            button.isHidden = searchVisible
            button.contentTintColor = emphasis ? primaryColor : secondaryColor
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
