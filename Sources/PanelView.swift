import AppKit
import Combine

final class PanelView: NSGlassEffectView, NSPopoverDelegate {
    static let itemPasteboardType = NSPasteboard.PasteboardType("com.covet.dfw.item")

    let store: PanelStore
    let appStore: AppStore
    var onWindowDragEnded: (() -> Void)?

    private let contentRoot = PanelContentView()
    private let scrollView = NSScrollView()
    private let gridView: GridView
    private let toolbarView = PanelToolbarView()
    private let toolbarDivider = NSView()
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

    override var acceptsFirstResponder: Bool { true }

    init(store: PanelStore, appStore: AppStore) {
        self.store = store
        self.appStore = appStore
        self.gridView = GridView(store: store)
        super.init(frame: .zero)

        // Desktop panels keep native Clear Liquid Glass; floating panels use Regular for contrast over apps.
        style = store.config.levelMode == .floating ? .regular : .clear
        tintColor = nil
        cornerRadius = CGFloat(store.config.cornerRadius)
        effectIsInteractive = false

        contentRoot.autoresizingMask = [.width, .height]
        contentRoot.wantsLayer = true
        contentRoot.layer?.backgroundColor = NSColor.clear.cgColor
        contentRoot.layer?.cornerRadius = CGFloat(store.config.cornerRadius)
        contentRoot.layer?.cornerCurve = .continuous
        contentRoot.layer?.masksToBounds = true
        contentView = contentRoot

        contentRoot.canResizeFromCorner = { [weak self] in
            self?.store.config.positionLocked == false
        }
        contentRoot.onCornerResize = { [weak self] in
            self?.beginCornerResize()
        }
        contentRoot.onBackgroundMouseDown = { [weak self] in
            self?.beginWindowDrag(with: $0)
        }
        contentRoot.onMenuRequested = { [weak self] event in
            self?.menu(for: event)
        }
        contentRoot.onDraggingEntered = { [weak self] in
            self?.dropController.draggingEntered($0) ?? []
        }
        contentRoot.onDraggingUpdated = { [weak self] in
            self?.dropController.draggingUpdated($0) ?? []
        }
        contentRoot.onDraggingExited = { [weak self] _ in
            self?.dropController.draggingExited()
        }
        contentRoot.onPerformDragOperation = { [weak self] in
            guard let self else { return false }
            return self.dropController.performDrop(
                pasteboard: $0.draggingPasteboard,
                location: $0.draggingLocation
            )
        }
        contentRoot.registerForDraggedTypes([.fileURL, Self.itemPasteboardType])

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.documentView = gridView
        contentRoot.addSubview(scrollView)

        toolbarView.onBackgroundMouseDown = { [weak self] in
            self?.beginWindowDrag(with: $0)
        }
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
        toolbarView.onStatusRequested = { [weak appStore] in
            appStore?.onShowFileActivity?()
        }
        contentRoot.addSubview(toolbarView)

        toolbarDivider.wantsLayer = true
        toolbarDivider.layer?.backgroundColor = resolvedCGColor(PanelAppearance.toolbarHairline)
        contentRoot.addSubview(toolbarDivider)

        emptyStateView.onAction = { [weak self] in self?.didTapEmptyButton() }
        contentRoot.addSubview(emptyStateView)

        gridView.panelView = self
        gridView.onAddRequested = { [weak self] in
            guard let self else { return }
            self.fileActions.chooseFiles(from: self.window)
        }

        store.$config
            .sink { [weak self] config in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let previous = self.lastConfig
                    self.applyConfigIfNeeded(config, previous: previous)
                    if previous == nil
                        || previous?.items != config.items
                        || previous?.columns != config.columns
                        || previous?.groupByType != config.groupByType {
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

        Publishers.CombineLatest(appStore.$autoAbsorbStatus, appStore.$persistenceWarning)
            .sink { [weak self] status, warning in
                DispatchQueue.main.async {
                    self?.toolbarView.setAutoAbsorbStatus(status, persistenceWarning: warning)
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
        contentRoot.setPanelHovering(hovering)
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

    private func applyConfigIfNeeded(_ config: PanelConfig, previous: PanelConfig?) {
        lastConfig = config

        let visualChanged = previous == nil
            || previous?.cornerRadius != config.cornerRadius
            || previous?.levelMode != config.levelMode
            || previous?.isLocked != config.isLocked
            || previous?.appearanceMode != config.appearanceMode

        if visualChanged {
            style = config.levelMode == .floating ? .regular : .clear
            appearance = config.effectiveAppearanceMode.nsAppearance
            cornerRadius = CGFloat(config.cornerRadius)
            contentRoot.layer?.cornerRadius = CGFloat(config.cornerRadius)
            toolbarView.setLocked(config.positionLocked)
            contentRoot.needsDisplay = true
            refreshSemanticColors()
        }

        if previous?.columns != config.columns {
            gridView.needsLayout = true
            needsLayout = true
        }
    }

    private func refreshSemanticColors() {
        primaryColor = PanelAppearance.primaryText
        secondaryColor = PanelAppearance.secondaryText
        toolbarView.applyAppearance(primaryColor: primaryColor, secondaryColor: secondaryColor)
        toolbarDivider.layer?.backgroundColor = resolvedCGColor(PanelAppearance.toolbarHairline)
        emptyStateView.update(
            searching: isSearchActive,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor
        )
        gridView.setLabelColor(primaryColor)
        contentRoot.needsDisplay = true
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

        gridView.reload(items: items, isSearching: searching, groupByType: store.config.isTypeGroupingEnabled)
        toolbarView.setItemCount(items.count)
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
        refreshSemanticColors()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        installHoverTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    func beginWindowDrag(with event: NSEvent) {
        window?.makeKey()
        guard !store.config.positionLocked else { return }

        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return }

        window?.performDrag(with: event)
        onWindowDragEnded?()
    }

    private func beginCornerResize() {
        guard let window, !store.config.positionLocked else { return }
        window.makeKey()

        let startMouse = NSEvent.mouseLocation
        let startFrame = window.frame
        let minSize = PanelAppearance.Window.minPanelSize
        let maxSize = PanelAppearance.Window.maxPanelSize
        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
        let topY = startFrame.maxY

        var finalFrame = startFrame
        while let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let currentMouse = NSEvent.mouseLocation
            let deltaX = currentMouse.x - startMouse.x
            let deltaY = currentMouse.y - startMouse.y

            var newWidth = min(maxSize.width, max(minSize.width, startFrame.width + deltaX))
            var newHeight = min(maxSize.height, max(minSize.height, startFrame.height - deltaY))

            if let visibleFrame {
                newWidth = min(newWidth, visibleFrame.maxX - startFrame.minX)
                newHeight = min(newHeight, topY - visibleFrame.minY)
                newWidth = max(minSize.width, newWidth)
                newHeight = max(minSize.height, newHeight)
            }

            finalFrame = CGRect(
                x: startFrame.minX,
                y: topY - newHeight,
                width: newWidth,
                height: newHeight
            )
            window.setFrame(finalFrame, display: true)

            if nextEvent.type == .leftMouseUp {
                break
            }
        }

        store.updateFrame(PanelFrame(rect: finalFrame))
        onWindowDragEnded?()
    }

    override func cancelOperation(_ sender: Any?) {
        if store.isSearchVisible {
            endSearch(clear: true)
        }
    }

    override func layout() {
        super.layout()

        let padding: CGFloat = 14
        let topY: CGFloat = 10
        let topHeight: CGFloat = 28
        let dividerY = topY + topHeight + 5
        let scale = max(1, window?.backingScaleFactor ?? 2)
        let hairline = 1.0 / scale
        let contentY = dividerY + 6
        let contentWidth = max(0, bounds.width - padding * 2)
        let contentHeight = max(0, bounds.height - contentY - 12)
        let contentRect = CGRect(x: padding, y: contentY, width: contentWidth, height: contentHeight)

        contentRoot.frame = bounds
        scrollView.frame = contentRect
        if abs(gridView.frame.size.width - scrollView.contentSize.width) > 0.5 {
            gridView.frame.size.width = scrollView.contentSize.width
        }
        gridView.needsLayout = true

        toolbarView.frame = CGRect(x: padding, y: topY, width: contentWidth, height: topHeight)
        toolbarDivider.frame = CGRect(x: padding, y: dividerY, width: contentWidth, height: hairline)
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

        let anchorButton = toolbarView.settingsButton
        popover.show(relativeTo: anchorButton.bounds, of: anchorButton, preferredEdge: .minY)
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

    @discardableResult
    func performDrop(
        pasteboard: NSPasteboard,
        location: NSPoint,
        completion: ((AppStore.AbsorbResult) -> Void)? = nil
    ) -> Bool {
        dropController.performDrop(pasteboard: pasteboard, location: location, completion: completion)
    }

    private func setDropHighlight(_ active: Bool) {
        contentRoot.layer?.borderWidth = active ? 2 : 0
        contentRoot.layer?.borderColor = resolvedCGColor(PanelAppearance.itemDropBorder)
    }
}

private final class PanelContentView: NSView {
    var canResizeFromCorner: (() -> Bool)?
    var onCornerResize: (() -> Void)?
    var onBackgroundMouseDown: ((NSEvent) -> Void)?
    var onMenuRequested: ((NSEvent) -> NSMenu?)?
    var onDraggingEntered: ((NSDraggingInfo) -> NSDragOperation)?
    var onDraggingUpdated: ((NSDraggingInfo) -> NSDragOperation)?
    var onDraggingExited: ((NSDraggingInfo?) -> Void)?
    var onPerformDragOperation: ((NSDraggingInfo) -> Bool)?

    private var isPanelHovering = false

    override var isFlipped: Bool { true }

    func setPanelHovering(_ hovering: Bool) {
        guard isPanelHovering != hovering else { return }
        isPanelHovering = hovering
        needsDisplay = true
    }

    private var cornerResizeRect: CGRect {
        CGRect(x: max(0, bounds.width - 18), y: max(0, bounds.height - 18), width: 18, height: 18)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if canResizeFromCorner?() == true, cornerResizeRect.contains(point) {
            onCornerResize?()
            return
        }
        onBackgroundMouseDown?(event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onMenuRequested?(event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDraggingEntered?(sender) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDraggingUpdated?(sender) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDraggingExited?(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onPerformDragOperation?(sender) ?? false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isPanelHovering, canResizeFromCorner?() == true else { return }

        PanelAppearance.tertiaryText.withAlphaComponent(0.42).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.1
        path.lineCapStyle = .round

        let maxX = bounds.width - 6.5
        let maxY = bounds.height - 6.5
        path.move(to: CGPoint(x: maxX - 5.5, y: maxY))
        path.line(to: CGPoint(x: maxX, y: maxY - 5.5))
        path.move(to: CGPoint(x: maxX - 2.6, y: maxY))
        path.line(to: CGPoint(x: maxX, y: maxY - 2.6))
        path.stroke()
    }
}
