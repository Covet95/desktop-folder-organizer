import AppKit

final class GridView: NSView {
    let store: PanelStore
    weak var panelView: PanelView?
    private(set) var itemViews: [ItemView] = []
    private var addTile: AddTileView?
    private var labelColor: NSColor = .white

    var onAddRequested: (() -> Void)?

    override var isFlipped: Bool { true }

    init(store: PanelStore) {
        self.store = store
        super.init(frame: .zero)
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setLabelColor(_ color: NSColor) {
        labelColor = color
        for view in itemViews {
            view.setLabelColor(color)
        }
        addTile?.setColor(color)
    }

    func reload(items: [WidgetItem], isSearching: Bool) {
        subviews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        addTile = nil

        for item in items {
            let view = ItemView(item: item, store: store, labelColor: labelColor)
            view.panelView = panelView
            addSubview(view)
            itemViews.append(view)
        }

        if !isSearching {
            let tile = AddTileView()
            tile.onTap = { [weak self] in self?.onAddRequested?() }
            tile.setColor(labelColor)
            addSubview(tile)
            addTile = tile
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()

        let width = bounds.width
        guard width > 0 else { return }

        let columns = max(1, store.config.columns)
        let spacingX: CGFloat = 8
        let spacingY: CGFloat = 4
        let cellWidth = max(1, (width - spacingX * CGFloat(columns - 1)) / CGFloat(columns))
        let cellHeight: CGFloat = 72

        var views: [NSView] = itemViews
        if let addTile {
            views.append(addTile)
        }

        for (index, view) in views.enumerated() {
            let row = index / columns
            let column = index % columns
            view.frame = CGRect(
                x: CGFloat(column) * (cellWidth + spacingX),
                y: CGFloat(row) * (cellHeight + spacingY),
                width: cellWidth,
                height: cellHeight
            )
        }

        let rows = max(1, (views.count + columns - 1) / columns)
        let contentHeight = CGFloat(rows) * cellHeight + CGFloat(max(0, rows - 1)) * spacingY + 4
        let height = max(contentHeight, superview?.bounds.height ?? 0)
        if abs(frame.height - height) > 0.5 {
            frame.size.height = height
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        guard !store.config.positionLocked else { return }
        // 只在真正拖动时才吸位；单击不触发 snapWindow
        let locationInEvent = event.locationInWindow
        let contentRect = bounds
        if contentRect.contains(locationInEvent) {
            window?.performDrag(with: event)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.panelView?.maybeSnapWindow()
            }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        panelView?.menu(for: event)
    }

    func index(at point: NSPoint, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }

        let columns = max(1, store.config.columns)
        let spacingX: CGFloat = 8
        let spacingY: CGFloat = 4
        let cellWidth = max(1, (bounds.width - spacingX * CGFloat(columns - 1)) / CGFloat(columns))
        let cellHeight: CGFloat = 72

        let column = max(0, min(columns - 1, Int((point.x + spacingX / 2) / (cellWidth + spacingX))))
        let row = max(0, Int((point.y + spacingY / 2) / (cellHeight + spacingY)))
        return min(itemCount - 1, row * columns + column)
    }

    func setDropTarget(_ index: Int?) {
        for (viewIndex, view) in itemViews.enumerated() {
            view.setDropTarget(viewIndex == index)
        }
    }
}
