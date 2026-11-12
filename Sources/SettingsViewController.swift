import AppKit
import Combine

final class SettingsViewController: NSViewController {
    private let store: PanelStore
    private let appStore: AppStore
    var onDelete: (() -> Void)?

    private let sizes: [(Double, Double)] = [(330, 300), (390, 360), (480, 440)]
    private let sizeControl = NSSegmentedControl(labels: ["小", "中", "大"], trackingMode: .selectOne, target: nil, action: nil)
    private let columnsValue = NSTextField(labelWithString: "")
    private let columnsStepper = NSStepper(frame: .zero)
    private let levelControl = NSSegmentedControl(labels: ["桌面层", "悬浮置顶"], trackingMode: .selectOne, target: nil, action: nil)
    private let lockCheckbox = NSButton(checkboxWithTitle: "锁定位置（禁止拖动面板）", target: nil, action: nil)
    private let groupCheckbox = NSButton(checkboxWithTitle: "按文件类型分区显示", target: nil, action: nil)
    private let deleteButton = NSButton(title: "删除面板", target: nil, action: nil)
    private var cancellables = Set<AnyCancellable>()

    init(store: PanelStore, appStore: AppStore) {
        self.store = store
        self.appStore = appStore
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 320, height: 308)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 320, height: 308))
        root.onAppearanceChanged = { [weak self] in
            guard let self else { return }
            self.update(self.store.config)
        }
        view = root

        addLabel("面板设置", frame: CGRect(x: 18, y: 16, width: 284, height: 20), font: .systemFont(ofSize: 14, weight: .semibold))
        addLabel("每行图标", frame: CGRect(x: 18, y: 50, width: 100, height: 18), font: .systemFont(ofSize: 12))
        columnsStepper.frame = CGRect(x: 250, y: 47, width: 20, height: 24)
        columnsStepper.controlSize = .small
        columnsStepper.minValue = 3
        columnsStepper.maxValue = 7
        columnsStepper.increment = 1
        columnsStepper.target = self
        columnsStepper.action = #selector(columnsChanged(_:))
        root.addSubview(columnsStepper)
        columnsValue.frame = CGRect(x: 274, y: 50, width: 28, height: 18)
        columnsValue.alignment = .right
        columnsValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        root.addSubview(columnsValue)

        addLabel("面板尺寸", frame: CGRect(x: 18, y: 88, width: 284, height: 16), font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        sizeControl.frame = CGRect(x: 18, y: 110, width: 284, height: 26)
        sizeControl.controlSize = .small
        sizeControl.target = self
        sizeControl.action = #selector(sizeChanged(_:))
        root.addSubview(sizeControl)

        addLabel("窗口层级", frame: CGRect(x: 18, y: 150, width: 284, height: 16), font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        levelControl.frame = CGRect(x: 18, y: 172, width: 284, height: 26)
        levelControl.controlSize = .small
        levelControl.target = self
        levelControl.action = #selector(levelChanged(_:))
        root.addSubview(levelControl)

        lockCheckbox.frame = CGRect(x: 18, y: 208, width: 284, height: 20)
        lockCheckbox.controlSize = .small
        lockCheckbox.font = .systemFont(ofSize: 12)
        lockCheckbox.target = self
        lockCheckbox.action = #selector(lockChanged(_:))
        root.addSubview(lockCheckbox)

        groupCheckbox.frame = CGRect(x: 18, y: 236, width: 284, height: 20)
        groupCheckbox.controlSize = .small
        groupCheckbox.font = .systemFont(ofSize: 12)
        groupCheckbox.target = self
        groupCheckbox.action = #selector(groupingChanged(_:))
        root.addSubview(groupCheckbox)

        let separator = NSBox(frame: CGRect(x: 18, y: 269, width: 284, height: 1))
        separator.boxType = .separator
        root.addSubview(separator)

        let clearButton = NSButton(title: "清空失效条目", target: self, action: #selector(clearMissing))
        clearButton.frame = CGRect(x: 18, y: 276, width: 128, height: 24)
        clearButton.controlSize = .small
        clearButton.bezelStyle = .rounded
        clearButton.font = .systemFont(ofSize: 11)
        root.addSubview(clearButton)

        deleteButton.target = self
        deleteButton.action = #selector(deletePanel)
        deleteButton.frame = CGRect(x: 208, y: 276, width: 94, height: 24)
        deleteButton.controlSize = .small
        deleteButton.bezelStyle = .rounded
        deleteButton.font = .systemFont(ofSize: 11)
        root.addSubview(deleteButton)

        store.$config
            .sink { [weak self] config in self?.update(config) }
            .store(in: &cancellables)

        appStore.$panels
            .sink { [weak self] _ in
                guard let self else { return }
                self.deleteButton.isEnabled = self.appStore.canDeletePanel
            }
            .store(in: &cancellables)

        update(store.config)
    }

    private func addLabel(
        _ text: String,
        frame: CGRect,
        font: NSFont,
        color: NSColor = .labelColor
    ) {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = font
        label.textColor = color
        view.addSubview(label)
    }

    private func update(_ config: PanelConfig) {
        columnsStepper.integerValue = config.columns
        columnsValue.stringValue = "\(config.columns)"
        sizeControl.selectedSegment = closestSizeIndex(to: config.frame)
        levelControl.selectedSegment = config.levelMode == .desktop ? 0 : 1
        lockCheckbox.state = config.positionLocked ? .on : .off
        groupCheckbox.state = config.isTypeGroupingEnabled ? .on : .off
        deleteButton.isEnabled = appStore.canDeletePanel

    }

    @objc private func columnsChanged(_ sender: NSStepper) {
        store.config.columns = sender.integerValue
    }

    @objc private func sizeChanged(_ sender: NSSegmentedControl) {
        let index = max(0, min(sizes.count - 1, sender.selectedSegment))
        let resizedFrame = store.config.frame.resized(
            width: sizes[index].0,
            height: sizes[index].1
        )
        let visibleFrame = (view.window?.screen ?? NSScreen.main)?.visibleFrame
        let frame = visibleFrame.map { resizedFrame.clamped(to: $0) } ?? resizedFrame
        store.updateFrame(frame)
    }

    private func closestSizeIndex(to frame: PanelFrame) -> Int {
        var bestIndex = 1
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, size) in sizes.enumerated() {
            let distance = abs(size.0 - frame.width) + abs(size.1 - frame.height)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    @objc private func levelChanged(_ sender: NSSegmentedControl) {
        store.config.levelMode = sender.selectedSegment == 0 ? .desktop : .floating
    }

    @objc private func lockChanged(_ sender: NSButton) {
        store.config.isLocked = sender.state == .on
    }

    @objc private func groupingChanged(_ sender: NSButton) {
        store.config.groupByType = sender.state == .on
    }

    @objc private func clearMissing() {
        store.removeMissing()
    }

    @objc private func deletePanel() {
        onDelete?()
    }
}

final class FlippedView: NSView {
    var onAppearanceChanged: (() -> Void)?

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChanged?()
    }
}
