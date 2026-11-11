import AppKit

final class ItemView: NSView, NSDraggingSource {
    let item: WidgetItem
    weak var panelView: PanelView?

    private let store: PanelStore
    private var labelColor: NSColor
    private let iconView = NSImageView()
    private let label: NSTextField
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isDropTarget = false
    private var mouseDownPoint: NSPoint?
    private var didStartDrag = false

    override var isFlipped: Bool { true }

    init(item: WidgetItem, store: PanelStore, labelColor: NSColor) {
        self.item = item
        self.store = store
        self.labelColor = labelColor
        self.label = NSTextField(wrappingLabelWithString: item.name)

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous

        iconView.image = IconProvider.shared.icon(for: item)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = item.exists ? nil : PanelAppearance.tertiaryText
        iconView.toolTip = item.name
        addSubview(iconView)

        label.font = .systemFont(ofSize: 11)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        label.textColor = item.exists ? labelColor : PanelAppearance.tertiaryText
        label.toolTip = item.name
        addSubview(label)

        toolTip = item.name
        updateBackground()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        iconView.frame = CGRect(x: (bounds.width - 40) / 2, y: 3, width: 40, height: 40)
        label.frame = CGRect(x: 2, y: 47, width: max(0, bounds.width - 4), height: 27)
    }

    func setLabelColor(_ color: NSColor) {
        labelColor = color
        label.textColor = item.exists ? color : PanelAppearance.tertiaryText
        iconView.contentTintColor = item.exists ? nil : PanelAppearance.tertiaryText
        updateBackground()
    }

    func setDropTarget(_ active: Bool) {
        isDropTarget = active
        updateBackground()
    }

    private func updateBackground() {
        if isDropTarget {
            layer?.backgroundColor = PanelAppearance.itemDrop.cgColor
        } else if isHovering {
            layer?.backgroundColor = PanelAppearance.itemHover.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        panelView?.setHoveredItem(item)
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        panelView?.setHoveredItem(nil)
        updateBackground()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, let start = mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) >= 4 else { return }

        didStartDrag = true
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.id.uuidString, forType: PanelView.itemPasteboardType)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(iconView.frame, contents: IconProvider.shared.icon(for: item))
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard !didStartDrag else { return }
        open(item)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let open = NSMenuItem(title: "打开", action: #selector(openItem), keyEquivalent: "")
        open.target = self
        open.isEnabled = item.exists
        menu.addItem(open)

        let reveal = NSMenuItem(title: "在 Finder 中显示", action: #selector(revealItem), keyEquivalent: "")
        reveal.target = self
        reveal.isEnabled = item.exists
        menu.addItem(reveal)

        let preview = NSMenuItem(title: "快速查看", action: #selector(previewItem), keyEquivalent: "")
        preview.target = self
        preview.isEnabled = item.exists
        menu.addItem(preview)

        let rename = NSMenuItem(title: "重命名…", action: #selector(renameFile), keyEquivalent: "")
        rename.target = self
        rename.isEnabled = item.exists
        menu.addItem(rename)

        let relocate = NSMenuItem(title: "重新定位…", action: #selector(relocateItem), keyEquivalent: "")
        relocate.target = self
        menu.addItem(relocate)

        if panelView?.canRestore(item) == true {
            let restore = NSMenuItem(title: "恢复原位置…", action: #selector(restoreFile), keyEquivalent: "")
            restore.target = self
            menu.addItem(restore)
        }

        menu.addItem(.separator())

        let remove = NSMenuItem(title: "从面板移除", action: #selector(removeItem), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)

        return menu
    }

    @objc private func openItem() {
        open(item)
    }

    @objc private func revealItem() {
        reveal(item)
    }

    private func open(_ item: WidgetItem) {
        guard item.exists else {
            NSSound.beep()
            return
        }
        if !NSWorkspace.shared.open(item.url) {
            NSSound.beep()
        }
    }

    private func reveal(_ item: WidgetItem) {
        guard item.exists else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    @objc private func previewItem() {
        panelView?.preview(item)
    }

    @objc private func removeItem() {
        store.remove(id: item.id)
    }

    @objc private func renameFile() {
        panelView?.rename(item)
    }

    @objc private func restoreFile() {
        panelView?.restore(item)
    }

    @objc private func relocateItem() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择「\(item.name)」的新位置"
        NSApp.activate(ignoringOtherApps: true)

        let itemID = item.id
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.store.relocate(id: itemID, to: url)
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
}
