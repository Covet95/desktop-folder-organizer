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
        preferredContentSize = NSSize(width: 336, height: 410)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 336, height: 410))
        root.onAppearanceChanged = { [weak self] in
            guard let self else { return }
            self.update(self.store.config)
        }
        view = root

        addLabel("面板设置", frame: CGRect(x: 20, y: 14, width: 296, height: 24),
                 font: PanelAppearance.Typography.settingsTitle)
        addLabel("调整文件排列及窗口行为", frame: CGRect(x: 20, y: 41, width: 296, height: 17),
                 font: PanelAppearance.Typography.settingsDetail, color: .secondaryLabelColor)
        addSeparator(y: 64)

        addLabel("内容布局", frame: CGRect(x: 20, y: 76, width: 296, height: 17),
                 font: PanelAppearance.Typography.settingsSection, color: .secondaryLabelColor)

        addLabel("每行最多图标", frame: CGRect(x: 20, y: 102, width: 174, height: 23),
                 font: PanelAppearance.Typography.settingsLabel)
        columnsStepper.frame = CGRect(x: 260, y: 100, width: 25, height: 26)
        columnsStepper.controlSize = .regular
        columnsStepper.minValue = 3
        columnsStepper.maxValue = 7
        columnsStepper.increment = 1
        columnsStepper.target = self
        columnsStepper.action = #selector(columnsChanged(_:))
        root.addSubview(columnsStepper)

        columnsValue.frame = CGRect(x: 290, y: 102, width: 26, height: 22)
        columnsValue.alignment = .right
        columnsValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        root.addSubview(columnsValue)

        addLabel("窄面板自动减少列数，确保文件名可读", frame: CGRect(x: 20, y: 128, width: 296, height: 16),
                 font: PanelAppearance.Typography.settingsDetail, color: .secondaryLabelColor)

        groupCheckbox.frame = CGRect(x: 20, y: 152, width: 296, height: 24)
        groupCheckbox.controlSize = .regular
        groupCheckbox.font = PanelAppearance.Typography.settingsLabel
        groupCheckbox.target = self
        groupCheckbox.action = #selector(groupingChanged(_:))
        root.addSubview(groupCheckbox)

        addSeparator(y: 184)
        addLabel("窗口", frame: CGRect(x: 20, y: 195, width: 296, height: 17),
                 font: PanelAppearance.Typography.settingsSection, color: .secondaryLabelColor)

        addLabel("面板尺寸", frame: CGRect(x: 20, y: 220, width: 296, height: 18),
                 font: PanelAppearance.Typography.settingsLabel)
        sizeControl.frame = CGRect(x: 20, y: 241, width: 296, height: 27)
        sizeControl.controlSize = .regular
        sizeControl.font = PanelAppearance.Typography.settingsLabel
        sizeControl.target = self
        sizeControl.action = #selector(sizeChanged(_:))
        root.addSubview(sizeControl)

        addLabel("窗口层级", frame: CGRect(x: 20, y: 278, width: 296, height: 18),
                 font: PanelAppearance.Typography.settingsLabel)
        levelControl.frame = CGRect(x: 20, y: 299, width: 296, height: 27)
        levelControl.controlSize = .regular
        levelControl.font = PanelAppearance.Typography.settingsLabel
        levelControl.target = self
        levelControl.action = #selector(levelChanged(_:))
        root.addSubview(levelControl)

        lockCheckbox.frame = CGRect(x: 20, y: 335, width: 296, height: 23)
        lockCheckbox.controlSize = .regular
        lockCheckbox.font = PanelAppearance.Typography.settingsLabel
        lockCheckbox.target = self
        lockCheckbox.action = #selector(lockChanged(_:))
        root.addSubview(lockCheckbox)

        addSeparator(y: 366)
        let clearButton = NSButton(title: "清理失效项", target: self, action: #selector(clearMissing))
        clearButton.frame = CGRect(x: 20, y: 374, width: 130, height: 28)
        clearButton.controlSize = .regular
        clearButton.bezelStyle = .rounded
        clearButton.font = PanelAppearance.Typography.button
        root.addSubview(clearButton)

        deleteButton.target = self
        deleteButton.action = #selector(deletePanel)
        deleteButton.frame = CGRect(x: 219, y: 374, width: 97, height: 28)
        deleteButton.controlSize = .regular
        deleteButton.bezelStyle = .rounded
        deleteButton.font = PanelAppearance.Typography.button
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

    private func addSeparator(y: CGFloat) {
        let separator = NSBox(frame: CGRect(x: 20, y: y, width: 296, height: 1))
        separator.boxType = .separator
        view.addSubview(separator)
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
