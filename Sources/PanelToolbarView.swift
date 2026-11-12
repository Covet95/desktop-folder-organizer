import AppKit

final class PanelToolbarView: NSView, NSSearchFieldDelegate {
    var onSearchChanged: ((String) -> Void)?
    var onSearchRequested: (() -> Void)?
    var onAddRequested: (() -> Void)?
    var onSettingsRequested: (() -> Void)?
    var onBackgroundMouseDown: ((NSEvent) -> Void)?

    let searchField = NSSearchField()
    private let searchButton = NSButton()
    private let addButton = NSButton()
    private let settingsButton = NSButton()
    private var isHovering = false
    private var forceVisible = false
    private var searchVisible = false
    private var itemCount = 0
    private var primaryColor = PanelAppearance.primaryText
    private var secondaryColor = PanelAppearance.secondaryText

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        configureButton(searchButton, symbol: "magnifyingglass", tooltip: "搜索文件", action: #selector(didTapSearch))
        configureButton(addButton, symbol: "plus", tooltip: "添加文件（移动原文件）", action: #selector(didTapAdd))
        configureButton(settingsButton, symbol: "gearshape", tooltip: "面板设置", action: #selector(didTapSettings))

        searchField.delegate = self
        searchField.placeholderString = "搜索文件"
        searchField.font = PanelAppearance.Typography.settingsLabel
        searchField.isBordered = false
        searchField.bezelStyle = .roundedBezel
        searchField.drawsBackground = true
        searchField.focusRingType = .none
        searchField.controlSize = .regular
        searchField.sendsSearchStringImmediately = true
        searchField.isHidden = true
        addSubview(searchField)
        updateTools()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyAppearance(primaryColor: NSColor, secondaryColor: NSColor) {
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        searchField.textColor = primaryColor
        searchField.backgroundColor = PanelAppearance.controlFill
        updateTools()
    }

    func setItemCount(_ count: Int) {
        guard itemCount != count else { return }
        itemCount = count
        needsDisplay = true
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
        updateTools()
    }

    func setForcedVisible(_ visible: Bool) {
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
        searchField.isHidden = !visible
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
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !searchVisible else { return }

        let title = "文档整理" as NSString
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: PanelAppearance.Typography.toolbarTitle,
            .foregroundColor: primaryColor
        ]
        let titleSize = title.size(withAttributes: titleAttrs)
        title.draw(at: NSPoint(x: 0, y: 5), withAttributes: titleAttrs)

        let count = "· \(itemCount) 项" as NSString
        let countAttrs: [NSAttributedString.Key: Any] = [
            .font: PanelAppearance.Typography.toolbarDetail,
            .foregroundColor: secondaryColor
        ]
        // The controls are on the opposite edge, so this remains readable in a small panel.
        count.draw(at: NSPoint(x: titleSize.width + 8, y: 7), withAttributes: countAttrs)
    }

    override func layout() {
        super.layout()
        let buttonSize: CGFloat = 28
        var x = bounds.width - buttonSize
        for button in [settingsButton, addButton, searchButton] {
            button.frame = CGRect(x: x, y: 0, width: buttonSize, height: buttonSize)
            x -= buttonSize + 3
        }
        searchField.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 28)
    }

    override func mouseDown(with event: NSEvent) {
        onBackgroundMouseDown?(event)
    }

    private func configureButton(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.image = image?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.bezelStyle = .inline
        button.controlSize = .regular
        button.toolTip = tooltip
        button.target = self
        button.action = action
        addSubview(button)
    }

    private func updateTools() {
        // Subdued but discoverable at rest; native semantic tint on hover.
        let emphasis = isHovering || forceVisible
        for button in [searchButton, addButton, settingsButton] {
            button.isHidden = searchVisible
            button.contentTintColor = emphasis ? primaryColor : secondaryColor
        }
        needsDisplay = true
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
