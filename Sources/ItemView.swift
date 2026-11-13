import AppKit

final class ItemView: NSView, NSDraggingSource {
    private(set) var item: WidgetItem
    private(set) var metadata: FileMetadata
    weak var panelView: PanelView?

    private let store: PanelStore
    private var labelColor: NSColor
    private let iconView = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isPressed = false
    private var isDropTarget = false
    private var mouseDownPoint: NSPoint?
    private var didStartDrag = false
    private var loadedIconPath: String?
    private var loadedIconTimestamp: TimeInterval = -1
    private var loadedIconExists: Bool?
    private var thumbnailGeneration: UInt64 = 0

    override var isFlipped: Bool { true }

    init(item: WidgetItem, metadata: FileMetadata, store: PanelStore, labelColor: NSColor) {
        self.item = item
        self.metadata = metadata
        self.store = store
        self.labelColor = labelColor

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.masksToBounds = false
        iconView.layer?.shadowColor = NSColor.black.cgColor
        iconView.layer?.shadowOpacity = 0.16
        iconView.layer?.shadowRadius = 3.5
        iconView.layer?.shadowOffset = CGSize(width: 0, height: -1.5)
        addSubview(iconView)

        label.font = PanelAppearance.Typography.fileName
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.allowsDefaultTighteningForTruncation = true
        label.cell?.usesSingleLineMode = false
        label.cell?.wraps = true
        label.cell?.truncatesLastVisibleLine = true
        label.isSelectable = false
        addSubview(label)

        configure(item: item, metadata: metadata, labelColor: labelColor)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: WidgetItem, metadata: FileMetadata, labelColor: NSColor) {
        let oldName = self.item.name
        self.item = item
        self.metadata = metadata
        self.labelColor = labelColor

        if label.stringValue.isEmpty || oldName != item.name {
            label.stringValue = item.name
        }

        let tip = metadata.exists
            ? item.name
            : "\(item.name)（文件已不在原位置，右键可重新定位或移除）"
        if toolTip != tip {
            toolTip = tip
            iconView.toolTip = tip
            label.toolTip = tip
        }

        if loadedIconPath != item.path
            || loadedIconTimestamp != metadata.modificationTimestamp
            || loadedIconExists != metadata.exists {
            loadedIconPath = item.path
            loadedIconTimestamp = metadata.modificationTimestamp
            loadedIconExists = metadata.exists
            thumbnailGeneration &+= 1

            iconView.image = IconProvider.shared.icon(for: item, metadata: metadata)
            refreshThumbnailIfNeeded()
        }

        applyColors()
        updateBackground()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        refreshThumbnailIfNeeded()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func refreshThumbnailIfNeeded() {
        guard metadata.exists, !metadata.isDirectory else { return }
        let generation = thumbnailGeneration
        let targetPath = item.path
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        IconProvider.shared.requestThumbnailIfNeeded(
            for: item,
            metadata: metadata,
            scale: scale
        ) { [weak self] thumbnail in
            guard let self,
                  self.thumbnailGeneration == generation,
                  self.item.path == targetPath else { return }
            self.iconView.image = thumbnail
        }
    }

    override func layout() {
        super.layout()
        let iconSize = min(PanelAppearance.Grid.iconSize, max(1, bounds.width - 8))
        iconView.frame = CGRect(
            x: (bounds.width - iconSize) / 2, y: 7, width: iconSize, height: iconSize
        )
        label.frame = CGRect(x: 2, y: 54, width: max(0, bounds.width - 4), height: 36)
    }

    func setLabelColor(_ color: NSColor) {
        labelColor = color
        applyColors()
        updateBackground()
    }

    func setDropTarget(_ active: Bool) {
        guard isDropTarget != active else { return }
        isDropTarget = active
        updateBackground()
    }

    private func applyColors() {
        label.textColor = metadata.exists ? labelColor : PanelAppearance.tertiaryText
        iconView.contentTintColor = metadata.exists ? nil : PanelAppearance.tertiaryText
        iconView.alphaValue = metadata.exists ? (isPressed ? 0.82 : 1.0) : 0.65
    }

    private func updateBackground() {
        if isDropTarget {
            layer?.backgroundColor = resolvedCGColor(PanelAppearance.itemDrop)
            layer?.borderWidth = 1.5
            layer?.borderColor = resolvedCGColor(PanelAppearance.itemDropBorder)
        } else if isPressed {
            layer?.backgroundColor = resolvedCGColor(PanelAppearance.itemPressed)
            layer?.borderWidth = 0
        } else if isHovering {
            layer?.backgroundColor = resolvedCGColor(PanelAppearance.itemHover)
            layer?.borderWidth = 0.5
            layer?.borderColor = resolvedCGColor(PanelAppearance.itemHoverBorder)
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
        }
        iconView.alphaValue = metadata.exists ? (isPressed ? 0.82 : 1.0) : 0.65
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        installHoverTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        panelView?.setHoveredItem(item)
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressed = false
        panelView?.setHoveredItem(nil)
        updateBackground()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didStartDrag = false
        isPressed = true
        updateBackground()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, let start = mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) >= 4 else { return }

        didStartDrag = true
        isPressed = false
        updateBackground()

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.id.uuidString, forType: PanelView.itemPasteboardType)
        if metadata.exists {
            pasteboardItem.setString(item.url.absoluteString, forType: .fileURL)
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(iconView.frame, contents: iconView.image ?? IconProvider.shared.icon(for: item, metadata: metadata))
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let shouldOpen = !didStartDrag && bounds.contains(point)
        mouseDownPoint = nil
        isPressed = false
        updateBackground()
        if shouldOpen {
            open(item)
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : .copy
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let freshMetadata = IconProvider.shared.metadata(for: item, forceRefresh: true)
        if freshMetadata != metadata {
            metadata = freshMetadata
            applyColors()
        }
        let exists = freshMetadata.exists

        let menu = NSMenu()

        let open = NSMenuItem(title: "打开", action: #selector(openItem), keyEquivalent: "")
        open.target = self
        open.isEnabled = exists
        menu.addItem(open)

        let reveal = NSMenuItem(title: "在 Finder 中显示", action: #selector(revealItem), keyEquivalent: "")
        reveal.target = self
        reveal.isEnabled = exists
        menu.addItem(reveal)

        let preview = NSMenuItem(title: "快速查看", action: #selector(previewItem), keyEquivalent: "")
        preview.target = self
        preview.isEnabled = exists
        menu.addItem(preview)

        let rename = NSMenuItem(title: "重命名…", action: #selector(renameFile), keyEquivalent: "")
        rename.target = self
        rename.isEnabled = exists
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
