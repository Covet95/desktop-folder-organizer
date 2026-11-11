import AppKit
import Combine

final class PanelView: NSView, NSPopoverDelegate {
    static let itemPasteboardType = NSPasteboard.PasteboardType("com.covet.dfw.item")

    let store: PanelStore
    let appStore: AppStore
    var onWindowDragEnded: (() -> Void)?

    private let scrollView = NSScrollView()
    private let gridView: GridView
    private let effectView = PassthroughVisualEffectView()
    private let toolbarView = PanelToolbarView()
    private let quickLook = QuickLookController()
    private lazy var fileActions = PanelFileActionCoordinator(appStore: appStore, panelStore: store)
    private lazy var contextMenuController = PanelContextMenuController(
        panelView: self,
        store: store,
        appStore: appStore
    )
    private lazy var dropController = PanelDropController(
        store: store,
        gridView: gridView,
        fileActions: fileActions,
        isSearching: { [weak self] in self?.isSearchActive ?? false },
        setHighlight: { [weak self] in self?.setDropHighlight($0) }
    )
    private var hoveredItem: WidgetItem?
    private let emptyStateView = PanelEmptyStateView()

    private var settingsPopover: NSPopover?
    private var cancellables = Set<AnyCancellable>()
    private var refreshScheduled = false
    private var trackingArea: NSTrackingArea?
    private var lastConfig: PanelConfig?
    private var primaryColor: NSColor = PanelAppearance.primaryText
    private var secondaryColor: NSColor = PanelAppearance.secondaryText

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(store: PanelStore, appStore: AppStore) {
        self.store = store
        self.appStore = appStore
        self.gridView = GridView(store: store)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous

        effectView.blendingMode = .behindWindow
        effectView.material = PanelAppearance.material(for: .desktop)
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        effectView.wantsLayer = true
        addSubview(effectView)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.documentView = gridView
        addSubview(scrollView)

        toolbarView.onSearchChanged = { [weak store] in store?.searchText = $0 }
        toolbarView.onSearchRequested = { [weak self] in
            if self?.store.isSearchVisible == true {
                self?.endSearch(clear: true)
            } else {
                self?.beginSearch()
            }
        }
        toolbarView.onAddRequested = { [weak self] in
            guard let self else { return }
            self.fileActions.chooseFiles(from: self.window)
        }
        toolbarView.onSettingsRequested = { [weak self] in self?.requestSettings() }
        addSubview(toolbarView)

        emptyStateView.onAction = { [weak self] in self?.didTapEmptyButton() }
        addSubview(emptyStateView)

        gridView.panelView = self
        gridView.onAddRequested = { [weak self] in
            guard let self else { return }
            self.fileActions.chooseFiles(from: self.window)
        }

        registerForDraggedTypes([.fileURL, Self.itemPasteboardType])

        store.$config
            .sink { [weak self] config in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let previous = self.lastConfig
                    self.configChanged(config)
                    if previous == nil
                        || previous?.items != config.items
                        || previous?.columns != config.columns {
                        self.scheduleRefresh()
                    }
                }
            }
            .store(in: &cancellables)

        store.$searchText
            .sink { [weak self] text in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.toolbarView.setSearchText(text)
                    self.scheduleRefresh()
                }
            }
            .store(in: &cancellables)

        store.$isSearchVisible
            .sink { [weak self] visible in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.toolbarView.setSearchVisible(visible, text: self.store.searchText)
                    self.scheduleRefresh()
                }
            }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
    }

    var isSearchActive: Bool {
        store.isSearchVisible || !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func setHovering(_ hovering: Bool) {
        toolbarView.setHovering(hovering)
    }

    var hasHoveredItem: Bool {
        hoveredItem != nil
    }

    func setHoveredItem(_ item: WidgetItem?) {
        hoveredItem = item
    }

    func previewHoveredItem() {
        if let hoveredItem {
            quickLook.preview(hoveredItem)
        }
    }

    func preview(_ item: WidgetItem) {
        quickLook.preview(item)
    }

    func beginSearch() {
        window?.makeKey()
        store.isSearchVisible = true
        window?.makeFirstResponder(toolbarView.searchField)
    }

    func endSearch(clear: Bool = true) {
        if clear {
            store.searchText = ""
        }
        store.isSearchVisible = false
    }

    private func configChanged(_ config: PanelConfig) {
        let previous = lastConfig
        lastConfig = config

        primaryColor = PanelAppearance.primaryText
        secondaryColor = PanelAppearance.secondaryText

        effectView.material = PanelAppearance.material(for: config.levelMode)
        // Only the native wallpaper-sampling material is faded.
        // File icons, labels and controls remain fully opaque above this layer.
        effectView.alphaValue = CGFloat(
            min(max(config.opacity, PanelAppearance.minimumMaterialOpacity),
                PanelAppearance.maximumMaterialOpacity)
        )
        effectView.layer?.cornerRadius = config.cornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true

        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = config.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = PanelAppearance.border.cgColor

        toolbarView.applyAppearance(primaryColor: primaryColor, secondaryColor: secondaryColor)
        emptyStateView.update(
            searching: isSearchActive,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor
        )

        gridView.setLabelColor(primaryColor)

        if previous?.columns != config.columns {
            gridView.needsLayout = true
        }

        needsDisplay = true
        needsLayout = true
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refresh()
        }
    }

    private func refresh() {
        hoveredItem = nil
        let items = store.filteredItems
        let searching = isSearchActive

        gridView.reload(items: items, isSearching: searching)
        updateEmptyState(items: items, searching: searching)
        gridView.needsLayout = true
        needsLayout = true
    }

    private func updateEmptyState(items: [WidgetItem], searching: Bool) {
        let isEmpty = items.isEmpty
        scrollView.isHidden = isEmpty
        emptyStateView.isHidden = !isEmpty
        emptyStateView.update(
            searching: searching,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        configChanged(store.config)
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
        toolbarView.setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        toolbarView.setHovering(false)
    }

    override func mouseDown(with event: NSEvent) {
        beginWindowDrag(with: event)
    }

    func beginWindowDrag(with event: NSEvent) {
        window?.makeKey()
        guard !store.config.positionLocked else { return }

        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return }

        window?.performDrag(with: event)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.onWindowDragEnded?()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if store.isSearchVisible {
            endSearch(clear: true)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // A restrained top-edge glint gives the glass a native layered edge without a solid outline.
        let highlight = NSBezierPath()
        highlight.move(to: CGPoint(x: store.config.cornerRadius, y: 0.7))
        highlight.line(to: CGPoint(x: bounds.width - store.config.cornerRadius, y: 0.7))
        NSColor.white.withAlphaComponent(0.16).setStroke()
        highlight.lineWidth = 0.8
        highlight.stroke()

        PanelAppearance.tertiaryText.withAlphaComponent(0.62).setFill()
        let startX: CGFloat = 14
        let startY: CGFloat = 17
        for row in 0..<3 {
            for column in 0..<3 {
                let rect = CGRect(
                    x: startX + CGFloat(column) * 3.4,
                    y: startY + CGFloat(row) * 3.4,
                    width: 1.6,
                    height: 1.6
                )
                NSBezierPath(ovalIn: rect).fill()
            }
        }
    }

    override func layout() {
        super.layout()

        let padding: CGFloat = 12
        let topY: CGFloat = 10
        let topHeight: CGFloat = 22
        let contentY = topY + topHeight + 8
        let contentWidth = max(0, bounds.width - padding * 2)
        let contentHeight = max(0, bounds.height - contentY - padding)
        let contentRect = CGRect(x: padding, y: contentY, width: contentWidth, height: contentHeight)

        effectView.frame = bounds
        scrollView.frame = contentRect
        gridView.frame.size.width = scrollView.contentSize.width
        gridView.needsLayout = true

        toolbarView.frame = CGRect(x: padding, y: topY, width: contentWidth, height: 24)

        emptyStateView.frame = contentRect
    }

    @objc private func didTapEmptyButton() {
        if isSearchActive {
            endSearch(clear: true)
        } else {
            fileActions.chooseFiles(from: window)
        }
    }

    func requestAddFiles() {
        fileActions.chooseFiles(from: window)
    }

    func rename(_ item: WidgetItem) {
        fileActions.rename(item, from: window)
    }

    func restore(_ item: WidgetItem) {
        fileActions.restore(item, from: window)
    }

    func canRestore(_ item: WidgetItem) -> Bool {
        fileActions.canRestore(item)
    }

    func requestSettings() {
        toggleSettings()
    }

    private func toggleSettings() {
        if let popover = settingsPopover, popover.isShown {
            popover.performClose(nil)
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self

        let controller = SettingsViewController(store: store, appStore: appStore)
        controller.onDelete = { [weak self] in
            guard let self else { return }
            self.settingsPopover?.performClose(nil)
            self.appStore.removePanel(self.store)
        }
        popover.contentViewController = controller

        let anchor = CGRect(x: bounds.width - 40, y: 8, width: 20, height: 20)
        popover.show(relativeTo: anchor, of: self, preferredEdge: .maxY)
        settingsPopover = popover
        toolbarView.setForcedVisible(true)
    }

    func popoverDidClose(_ notification: Notification) {
        settingsPopover = nil
        toolbarView.setForcedVisible(false)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuController.makeMenu()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropController.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropController.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropController.draggingExited()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropController.performDrop(
            pasteboard: sender.draggingPasteboard,
            location: sender.draggingLocation
        )
    }

    @discardableResult
    func performDrop(
        pasteboard: NSPasteboard,
        location: NSPoint,
        completion: ((AppStore.AbsorbResult) -> Void)? = nil
    ) -> Bool {
        dropController.performDrop(pasteboard: pasteboard, location: location, completion: completion)
    }

    private func setDropHighlight(_ active: Bool) {
        layer?.borderWidth = active ? 2 : 1
        layer?.borderColor = active
            ? NSColor.controlAccentColor.withAlphaComponent(0.72).cgColor
            : PanelAppearance.border.cgColor
    }
}

final class PassthroughVisualEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
