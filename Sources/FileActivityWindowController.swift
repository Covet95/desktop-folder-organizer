import AppKit
import Combine

final class FileActivityWindowController: NSWindowController, NSWindowDelegate {
    private let activityController: FileActivityViewController

    init(appStore: AppStore) {
        let controller = FileActivityViewController(appStore: appStore)
        self.activityController = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "收纳记录与恢复"
        window.minSize = NSSize(width: 660, height: 420)
        window.contentViewController = controller
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowDidBecomeKey(_ notification: Notification) {
        activityController.refreshIfVisible()
    }
}

private final class AppearanceCardView: NSView {
    var onAppearanceChanged: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChanged?()
    }
}

private final class FileActivityViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum FilterMode: Int {
        case all = 0
        case recoverable = 1
        case attention = 2
    }

    private let appStore: AppStore
    private let statusIcon = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let filterControl = NSSegmentedControl(
        labels: ["全部", "可恢复", "需检查"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let tableView = NSTableView()
    private let restoreButton = NSButton(title: "恢复选中操作", target: nil, action: nil)
    private let revealButton = NSButton(title: "在 Finder 中显示", target: nil, action: nil)
    private let openStorageButton = NSButton(title: "打开收纳目录", target: nil, action: nil)
    private let refreshButton = NSButton(title: "刷新", target: nil, action: nil)
    private var cancellables = Set<AnyCancellable>()
    private var records: [FileOperationRecord] = []
    private var filterMode: FilterMode = .all

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    init(appStore: AppStore) {
        self.appStore = appStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 540))
        view = root

        // Top status card
        let headerCard = AppearanceCardView()
        headerCard.wantsLayer = true
        headerCard.layer?.cornerRadius = 10
        headerCard.layer?.cornerCurve = .continuous
        let applyCardBackground: () -> Void = { [weak headerCard] in
            guard let headerCard else { return }
            headerCard.layer?.backgroundColor = headerCard.resolvedCGColor(
                NSColor.controlBackgroundColor.withAlphaComponent(0.65)
            )
        }
        applyCardBackground()
        headerCard.onAppearanceChanged = applyCardBackground
        headerCard.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(headerCard)

        statusIcon.imageScaling = .scaleProportionallyDown
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        headerCard.addSubview(statusIcon)

        statusLabel.font = PanelAppearance.Typography.activityTitle
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        headerCard.addSubview(statusLabel)

        detailLabel.font = PanelAppearance.Typography.secondary
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        headerCard.addSubview(detailLabel)

        filterControl.selectedSegment = 0
        filterControl.controlSize = .regular
        filterControl.target = self
        filterControl.action = #selector(filterChanged)
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        headerCard.addSubview(filterControl)

        // Table
        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = "时间"
        dateColumn.width = 148
        dateColumn.minWidth = 120
        dateColumn.maxWidth = 180

        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionColumn.title = "操作"
        actionColumn.width = 92
        actionColumn.minWidth = 80
        actionColumn.maxWidth = 120

        let fileColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        fileColumn.title = "文件 / 路径"
        fileColumn.width = 390
        fileColumn.minWidth = 220

        let stateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("state"))
        stateColumn.title = "状态"
        stateColumn.width = 138
        stateColumn.minWidth = 110
        stateColumn.maxWidth = 170

        tableView.addTableColumn(dateColumn)
        tableView.addTableColumn(actionColumn)
        tableView.addTableColumn(fileColumn)
        tableView.addTableColumn(stateColumn)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.headerView = NSTableHeaderView()
        for column in tableView.tableColumns {
            column.headerCell.font = .systemFont(ofSize: 12, weight: .medium)
        }
        tableView.rowHeight = 32
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(revealSelected)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        // Footer bar
        let footerStack = NSStackView()
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.spacing = 10
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(footerStack)

        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreSelected)

        revealButton.bezelStyle = .rounded
        revealButton.target = self
        revealButton.action = #selector(revealSelected)

        openStorageButton.bezelStyle = .rounded
        openStorageButton.target = self
        openStorageButton.action = #selector(openStorage)

        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refresh)

        for button in [restoreButton, revealButton, openStorageButton, refreshButton] {
            button.font = PanelAppearance.Typography.button
            button.controlSize = .regular
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        footerStack.addArrangedSubview(restoreButton)
        footerStack.addArrangedSubview(revealButton)
        footerStack.addArrangedSubview(spacer)
        footerStack.addArrangedSubview(openStorageButton)
        footerStack.addArrangedSubview(refreshButton)

        NSLayoutConstraint.activate([
            headerCard.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            headerCard.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            headerCard.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            statusIcon.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 14),
            statusIcon.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 18),
            statusIcon.heightAnchor.constraint(equalToConstant: 18),

            statusLabel.topAnchor.constraint(equalTo: headerCard.topAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: filterControl.leadingAnchor, constant: -12),

            filterControl.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            filterControl.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -14),

            detailLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 5),
            detailLabel.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 14),
            detailLabel.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -14),
            detailLabel.bottomAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -14),

            footerStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            footerStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footerStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])

        appStore.$fileOperations
            .sink { [weak self] _ in self?.refreshIfVisible() }
            .store(in: &cancellables)
        appStore.$autoAbsorbStatus
            .sink { [weak self] status in
                guard let self, self.view.window?.isVisible == true else { return }
                self.updateStatus(status)
            }
            .store(in: &cancellables)

        refresh()
        updateStatus(appStore.autoAbsorbStatus)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
        updateStatus(appStore.autoAbsorbStatus)
    }

    func refreshIfVisible() {
        guard view.window?.isVisible == true else { return }
        refresh()
        updateStatus(appStore.autoAbsorbStatus)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        records.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard records.indices.contains(row), let identifier = tableColumn?.identifier else { return nil }
        let record = records[row]
        let text: String
        var textColor: NSColor = .labelColor
        var font: NSFont = PanelAppearance.Typography.activityRow

        switch identifier.rawValue {
        case "date":
            text = dateFormatter.string(from: record.createdAt)
            font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
            textColor = .secondaryLabelColor
        case "action":
            text = record.kind.title
        case "file":
            text = record.fileName
        case "state":
            text = record.state.title
            switch record.state {
            case .completed: textColor = .systemGreen
            case .restored: textColor = .secondaryLabelColor
            case .needsAttention, .prepared, .restoring: textColor = .systemOrange
            case .failed: textColor = .systemRed
            }
        default:
            return nil
        }

        let cellID = NSUserInterfaceItemIdentifier("cell-\(identifier.rawValue)")
        let cell: NSTableCellView
        let label: NSTextField
        if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView,
           let existingLabel = reused.textField {
            cell = reused
            label = existingLabel
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID
            label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        label.stringValue = text
        label.font = font
        label.textColor = textColor
        label.lineBreakMode = .byTruncatingMiddle
        label.toolTip = identifier.rawValue == "file"
            ? (record.state == .restored ? (record.restoredPath ?? record.sourcePath) : record.destinationPath)
            : record.errorMessage
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
        updateSelectionDetails()
    }

    @objc private func filterChanged() {
        filterMode = FilterMode(rawValue: filterControl.selectedSegment) ?? .all
        refresh()
    }

    @objc private func refresh() {
        let selectedID = selectedRecord?.id
        let all = appStore.fileOperations.sorted { $0.createdAt > $1.createdAt }
        switch filterMode {
        case .all:
            records = all
        case .recoverable:
            records = all.filter(\.canRestore)
        case .attention:
            records = all.filter { $0.state == .needsAttention || $0.state == .failed || $0.state == .prepared }
        }
        tableView.reloadData()
        if let selectedID, let index = records.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        updateButtons()
        updateSelectionDetails()
    }

    private func updateSelectionDetails() {
        guard let record = selectedRecord else {
            detailLabel.stringValue = records.isEmpty
                ? "当前筛选条件下没有记录。自动收纳、手动收纳和重命名都会记录在这里。"
                : "显示 \(records.count) 条记录；共 \(appStore.recoverableOperationCount) 条操作可以恢复。"
            return
        }
        if let error = record.errorMessage, !error.isEmpty {
            detailLabel.stringValue = error
        } else if record.state == .restored {
            detailLabel.stringValue = "已恢复到：\(record.restoredPath ?? record.sourcePath)"
        } else {
            detailLabel.stringValue = "原位置：\(record.sourcePath)  →  当前：\(record.destinationPath)"
        }
    }

    private var selectedRecord: FileOperationRecord? {
        let row = tableView.selectedRow
        guard records.indices.contains(row) else { return nil }
        return records[row]
    }

    private func updateButtons() {
        let record = selectedRecord
        restoreButton.isEnabled = record?.canRestore == true
        revealButton.isEnabled = record != nil
    }

    private func updateStatus(_ status: AutoAbsorbStatus) {
        statusLabel.stringValue = "\(status.phase.title) · \(status.detail)"
        switch status.phase {
        case .monitoring:
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemGreen
            statusLabel.textColor = .labelColor
        case .processing:
            statusIcon.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .controlAccentColor
            statusLabel.textColor = .labelColor
        case .retrying, .attention:
            statusIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemOrange
            statusLabel.textColor = .systemOrange
        }
    }

    @objc private func restoreSelected() {
        guard let record = selectedRecord, record.canRestore else { return }
        restoreButton.isEnabled = false
        appStore.restoreOperation(record.id) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url):
                self.statusLabel.stringValue = "恢复成功：\(url.path)"
                self.statusLabel.textColor = .systemGreen
            case .failure(let error):
                self.statusLabel.stringValue = "恢复失败：\(error.localizedDescription)"
                self.statusLabel.textColor = .systemOrange
            }
            self.refresh()
        }
    }

    @objc private func revealSelected() {
        guard let record = selectedRecord else { return }
        let path: String
        if record.state == .restored {
            path = record.restoredPath ?? record.sourcePath
        } else {
            path = record.destinationPath
        }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    @objc private func openStorage() {
        do {
            let storage = try appStore.prepareStorageDirectory()
            NSWorkspace.shared.open(storage)
        } catch {
            NSAlert.showMessage(
                title: "无法打开存储目录",
                message: error.localizedDescription,
                from: view.window
            )
        }
    }
}
