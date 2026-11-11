import AppKit

final class PanelToolbarView: NSView, NSSearchFieldDelegate {
    var onSearchChanged: ((String) -> Void)?
    var onSearchRequested: (() -> Void)?
    var onAddRequested: (() -> Void)?
    var onSettingsRequested: (() -> Void)?

    let searchField = NSSearchField()
    private let searchButton = NSButton()
    private let addButton = NSButton()
    private let settingsButton = NSButton()
    private var isHovering = false
    private var forceVisible = false
    private var searchVisible = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        configureButton(searchButton, symbol: "magnifyingglass", tooltip: "搜索", action: #selector(didTapSearch))
        configureButton(addButton, symbol: "plus", tooltip: "添加文件", action: #selector(didTapAdd))
        configureButton(settingsButton, symbol: "gearshape", tooltip: "面板设置", action: #selector(didTapSettings))

        searchField.delegate = self
        searchField.placeholderString = "搜索文件"
        searchField.font = .systemFont(ofSize: 12)
        searchField.isBordered = false
        searchField.bezelStyle = .roundedBezel
        searchField.drawsBackground = true
        searchField.focusRingType = .none
        searchField.controlSize = .small
        searchField.sendsSearchStringImmediately = true
        searchField.isHidden = true
        addSubview(searchField)
        updateTools()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyAppearance(primaryColor: NSColor, secondaryColor: NSColor) {
        for button in [searchButton, addButton, settingsButton] {
            button.contentTintColor = secondaryColor
        }
        searchField.textColor = primaryColor
        searchField.backgroundColor = PanelAppearance.controlFill
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
    }

    override func layout() {
        super.layout()
        let buttonSize: CGFloat = 20
        var x = bounds.width - buttonSize
        for button in [settingsButton, addButton, searchButton] {
            button.frame = CGRect(x: x, y: 1, width: buttonSize, height: buttonSize)
            x -= buttonSize + 6
        }
        searchField.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 24)
    }

    private func configureButton(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.isBordered = true
        button.bezelStyle = .toolbar
        button.controlSize = .small
        button.toolTip = tooltip
        button.target = self
        button.action = action
        addSubview(button)
    }

    private func updateTools() {
        let visible = (isHovering || forceVisible) && !searchVisible
        searchButton.isHidden = !visible
        addButton.isHidden = !visible
        settingsButton.isHidden = !visible
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
