import AppKit
import Combine

final class FileActivityWindowController: NSWindowController {
    init(appStore: AppStore) {
        let controller = FileActivityViewController(appStore: appStore)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "收纳记录与恢复"
        window.minSize = NSSize(width: 680, height: 420)
        window.contentViewController = controller
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class FileActivityViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let appStore: AppStore
    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let restoreButton = NSButton(title: "恢复选中操作", target: nil, action: nil)
    private let revealButton = NSButton(title: "在 Finder 中显示", target: nil, action: nil)
    private let refreshButton = NSButton(title: "刷新", target: nil, action: nil)
    private var cancellables = Set<AnyCancellable>()
    private var records: [FileOperationRecord] = []
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
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 520))
        view = root

        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.frame = NSRect(x: 20, y: 480, width: 780, height: 20)
        root.addSubview(statusLabel)

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.frame = NSRect(x: 20, y: 455, width: 780, height: 18)
        root.addSubview(detailLabel)

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = "时间"
        dateColumn.width = 145
        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionColumn.title = "操作"
        actionColumn.width = 95
        let fileColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        fileColumn.title = "文件 / 路径"
        fileColumn.width = 390
        let stateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("state"))
        stateColumn.title = "状态"
        stateColumn.width = 135
        tableView.addTableColumn(dateColumn)
        tableView.addTableColumn(actionColumn)
        tableView.addTableColumn(fileColumn)
        tableView.addTableColumn(stateColumn)
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 30
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(revealSelected)

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 64, width: 780, height: 380))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        tableView.frame = NSRect(x: 0, y: 0, width: 760, height: 380)
        tableView.autoresizingMask = [.width]
        scrollView.documentView = tableView
        root.addSubview(scrollView)

        restoreButton.frame = NSRect(x: 20, y: 20, width: 120, height: 28)
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreSelected)
        root.addSubview(restoreButton)

        revealButton.frame = NSRect(x: 150, y: 20, width: 130, height: 28)
        revealButton.bezelStyle = .rounded
        revealButton.target = self
        revealButton.action = #selector(revealSelected)
        root.addSubview(revealButton)

        refreshButton.frame = NSRect(x: 710, y: 20, width: 90, height: 28)
        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        root.addSubview(refreshButton)

        appStore.$fileOperations
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        appStore.$autoAbsorbStatus
            .sink { [weak self] status in self?.updateStatus(status) }
            .store(in: &cancellables)

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
        switch identifier.rawValue {
        case "date": text = dateFormatter.string(from: record.createdAt)
        case "action": text = record.kind.title
        case "file": text = record.fileName
        case "state": text = record.state.title
        default: return nil
        }

        let cellID = NSUserInterfaceItemIdentifier("cell-\(identifier.rawValue)")
        let cell = (tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView)
            ?? NSTableCellView()
        cell.identifier = cellID
        let label = cell.textField ?? NSTextField(labelWithString: "")
        label.stringValue = text
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingMiddle
        label.frame = NSRect(x: 5, y: 5, width: max(40, (tableColumn?.width ?? 100) - 10), height: 20)
        if cell.textField == nil {
            cell.addSubview(label)
            cell.textField = label
        }
        label.toolTip = identifier.rawValue == "file"
            ? (record.state == .restored ? (record.restoredPath ?? record.sourcePath) : record.destinationPath)
            : record.errorMessage
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
        updateSelectionDetails()
    }

    @objc private func refresh() {
        let selectedID = selectedRecord?.id
        records = appStore.fileOperations.sorted { $0.createdAt > $1.createdAt }
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
                ? "尚无文件操作记录。自动收纳、手动收纳和重命名都会记录在这里。"
                : "共 \(records.count) 条记录；\(appStore.recoverableOperationCount) 条操作可以恢复。"
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
        statusLabel.textColor = status.phase == .retrying || status.phase == .attention
            ? .systemOrange
            : .labelColor
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
}
