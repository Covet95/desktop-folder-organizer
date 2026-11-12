import AppKit

final class GridView: NSView {
    let store: PanelStore
    weak var panelView: PanelView?
    private(set) var itemViews: [ItemView] = []
    private var addTile: AddTileView?
    private var labelColor: NSColor = PanelAppearance.primaryText
    private var groupedSections: [(header: PanelSectionHeaderView, range: Range<Int>)] = []
    private var typeGrouping = false

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

    func reload(items: [WidgetItem], isSearching: Bool, groupByType: Bool) {
        subviews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        groupedSections.removeAll()
        addTile = nil
        typeGrouping = groupByType

        if groupByType {
            // Classify once per refresh, then preserve each group's saved order.
            var buckets: [FileDisplayGroup: [WidgetItem]] = [:]
            for item in items {
                buckets[item.displayGroup, default: []].append(item)
            }
            for group in FileDisplayGroup.allCases {
                guard let matching = buckets[group], !matching.isEmpty else { continue }

                let header = PanelSectionHeaderView(group: group, count: matching.count)
                addSubview(header)

                let start = itemViews.count
                for item in matching { addItem(item) }
                groupedSections.append((header, start..<itemViews.count))
            }
        } else {
            for item in items { addItem(item) }
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

    private func addItem(_ item: WidgetItem) {
        let view = ItemView(item: item, store: store, labelColor: labelColor)
        view.panelView = panelView
        addSubview(view)
        itemViews.append(view)
    }

    override func layout() {
        super.layout()

        let width = bounds.width
        guard width > 0 else { return }

        let columns = effectiveColumns(for: width)
        let spacingX = PanelAppearance.Grid.columnSpacing
        let spacingY = PanelAppearance.Grid.rowSpacing
        let cellWidth = max(1, (width - spacingX * CGFloat(columns - 1)) / CGFloat(columns))
        let cellHeight = PanelAppearance.Grid.tileHeight

        var contentHeight: CGFloat

        if typeGrouping {
            var y: CGFloat = 0
            for section in groupedSections {
                section.header.frame = CGRect(
                    x: 0, y: y, width: width, height: PanelAppearance.Grid.sectionHeaderHeight
                )
                y += PanelAppearance.Grid.sectionHeaderHeight + 6
                for (localIndex, index) in section.range.enumerated() {
                    let row = localIndex / columns
                    let column = localIndex % columns
                    itemViews[index].frame = CGRect(
                        x: CGFloat(column) * (cellWidth + spacingX),
                        y: y + CGFloat(row) * (cellHeight + spacingY),
                        width: cellWidth,
                        height: cellHeight
                    )
                }
                let count = section.range.count
                let rows = (count + columns - 1) / columns
                y += CGFloat(rows) * cellHeight + CGFloat(max(0, rows - 1)) * spacingY
                y += PanelAppearance.Grid.sectionGap
            }
            if let addTile {
                addTile.frame = CGRect(x: 0, y: y, width: cellWidth, height: cellHeight)
                y += cellHeight + 4
            }
            contentHeight = max(y, 4)
        } else {
            var views: [NSView] = itemViews
            if let addTile { views.append(addTile) }

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
            contentHeight = CGFloat(rows) * cellHeight + CGFloat(max(0, rows - 1)) * spacingY + 4
        }

        let height = max(contentHeight, superview?.bounds.height ?? 0)
        if abs(frame.height - height) > 0.5 {
            frame.size.height = height
        }
    }

    override func mouseDown(with event: NSEvent) {
        panelView?.beginWindowDrag(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        panelView?.menu(for: event)
    }

    /// The user-configured value is an upper bound. Narrow panels retain readable labels.
    private func effectiveColumns(for width: CGFloat) -> Int {
        let gap = PanelAppearance.Grid.columnSpacing
        let minimum = PanelAppearance.Grid.minTileWidth
        let fitting = Int(max(1, floor((width + gap) / (minimum + gap))))
        return max(1, min(store.config.columns, fitting))
    }

    func index(at point: NSPoint, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }

        if typeGrouping {
            // A category header or gap selects the nearest visible icon.
            // The resulting index is in displayed (section-sorted) order.
            return itemViews.enumerated().min {
                let a = $0.element.frame
                let b = $1.element.frame
                let ax = max(a.minX, min(point.x, a.maxX))
                let ay = max(a.minY, min(point.y, a.maxY))
                let bx = max(b.minX, min(point.x, b.maxX))
                let by = max(b.minY, min(point.y, b.maxY))
                return hypot(ax - point.x, ay - point.y) < hypot(bx - point.x, by - point.y)
            }?.offset ?? 0
        }

        let columns = effectiveColumns(for: bounds.width)
        let spacingX = PanelAppearance.Grid.columnSpacing
        let spacingY = PanelAppearance.Grid.rowSpacing
        let cellWidth = max(1, (bounds.width - spacingX * CGFloat(columns - 1)) / CGFloat(columns))
        let cellHeight = PanelAppearance.Grid.tileHeight

        let column = max(0, min(columns - 1, Int((point.x + spacingX / 2) / (cellWidth + spacingX))))
        let row = max(0, Int((point.y + spacingY / 2) / (cellHeight + spacingY)))
        return min(itemCount - 1, row * columns + column)
    }

    func displayedItem(at index: Int) -> WidgetItem? {
        guard itemViews.indices.contains(index) else { return nil }
        return itemViews[index].item
    }

    func setDropTarget(_ index: Int?) {
        for (viewIndex, view) in itemViews.enumerated() {
            view.setDropTarget(viewIndex == index)
        }
    }
}
