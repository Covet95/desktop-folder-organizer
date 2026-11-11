import AppKit
import Combine

final class SettingsViewController: NSViewController {
    private let store: PanelStore
    private let appStore: AppStore
    var onDelete: (() -> Void)?

    private let presets = [PanelAppearance.defaultTintHex, "#147F7A", "#6359A6", "#9A6B48", "#416B91", "#59616C"]
    private let sizes: [(Double, Double)] = [(330, 300), (390, 360), (480, 440)]
    private var swatches: [NSButton] = []
    private let colorWell = NSColorWell(frame: .zero)
    private let sizeControl = NSSegmentedControl(labels: ["小", "中", "大"], trackingMode: .selectOne, target: nil, action: nil)
    private let opacitySlider = NSSlider(value: PanelAppearance.defaultMaterialOpacity, minValue: PanelAppearance.minimumMaterialOpacity, maxValue: PanelAppearance.maximumMaterialOpacity, target: nil, action: nil)
    private let opacityValue = NSTextField(labelWithString: "")
    private let columnsValue = NSTextField(labelWithString: "")
    private let columnsStepper = NSStepper(frame: .zero)
    private let levelControl = NSSegmentedControl(labels: ["桌面层", "悬浮置顶"], trackingMode: .selectOne, target: nil, action: nil)
    private let lockCheckbox = NSButton(checkboxWithTitle: "锁定位置（禁止拖动面板）", target: nil, action: nil)
    private let deleteButton = NSButton(title: "删除面板", target: nil, action: nil)
    private var cancellables = Set<AnyCancellable>()

    init(store: PanelStore, appStore: AppStore) {
        self.store = store
        self.appStore = appStore
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 320, height: 372)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 320, height: 372))
        root.onAppearanceChanged = { [weak self] in
            guard let self else { return }
            self.update(self.store.config)
        }
        view = root

        addLabel("面板设置", frame: CGRect(x: 18, y: 16, width: 284, height: 20), font: .systemFont(ofSize: 14, weight: .semibold))
        addLabel("材质色调", frame: CGRect(x: 18, y: 48, width: 284, height: 16), font: .systemFont(ofSize: 12), color: .secondaryLabelColor)

        for (index, hex) in presets.enumerated() {
            let button = NSButton(frame: CGRect(x: 18 + CGFloat(index) * 30, y: 72, width: 24, height: 24))
            button.title = ""
            button.isBordered = false
            button.tag = index
            button.toolTip = index == 0 ? "蓝色玻璃（默认）" : "自定义玻璃色调"
            button.target = self
            button.action = #selector(swatchTapped(_:))
            button.wantsLayer = true
            button.layer?.cornerRadius = 12
            button.layer?.backgroundColor = NSColor(hex: hex).cgColor
            root.addSubview(button)
            swatches.append(button)
        }

        colorWell.frame = CGRect(x: 218, y: 72, width: 24, height: 24)
        colorWell.colorWellStyle = .minimal
        colorWell.target = self
        colorWell.action = #selector(colorWellChanged(_:))
        root.addSubview(colorWell)

        addLabel("材质不透明度", frame: CGRect(x: 18, y: 116, width: 82, height: 18), font: .systemFont(ofSize: 12))
        opacitySlider.frame = CGRect(x: 102, y: 114, width: 156, height: 20)
        opacitySlider.controlSize = .small
        opacitySlider.toolTip = "数值越低，面板越透明；文件图标和文字保持清晰"
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        root.addSubview(opacitySlider)
        opacityValue.frame = CGRect(x: 264, y: 116, width: 38, height: 18)
        opacityValue.alignment = .right
        opacityValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        root.addSubview(opacityValue)

        addLabel("每行图标", frame: CGRect(x: 18, y: 152, width: 100, height: 18), font: .systemFont(ofSize: 12))
        columnsStepper.frame = CGRect(x: 250, y: 149, width: 20, height: 24)
        columnsStepper.controlSize = .small
        columnsStepper.minValue = 3
        columnsStepper.maxValue = 7
        columnsStepper.increment = 1
        columnsStepper.target = self
        columnsStepper.action = #selector(columnsChanged(_:))
        root.addSubview(columnsStepper)
        columnsValue.frame = CGRect(x: 274, y: 152, width: 28, height: 18)
        columnsValue.alignment = .right
        columnsValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        root.addSubview(columnsValue)

        addLabel("面板尺寸", frame: CGRect(x: 18, y: 190, width: 284, height: 16), font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        sizeControl.frame = CGRect(x: 18, y: 212, width: 284, height: 26)
        sizeControl.controlSize = .small
        sizeControl.target = self
        sizeControl.action = #selector(sizeChanged(_:))
        root.addSubview(sizeControl)

        addLabel("窗口层级", frame: CGRect(x: 18, y: 252, width: 284, height: 16), font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        levelControl.frame = CGRect(x: 18, y: 274, width: 284, height: 26)
        levelControl.controlSize = .small
        levelControl.target = self
        levelControl.action = #selector(levelChanged(_:))
        root.addSubview(levelControl)

        lockCheckbox.frame = CGRect(x: 18, y: 310, width: 284, height: 20)
        lockCheckbox.controlSize = .small
        lockCheckbox.font = .systemFont(ofSize: 12)
        lockCheckbox.target = self
        lockCheckbox.action = #selector(lockChanged(_:))
        root.addSubview(lockCheckbox)

        let separator = NSBox(frame: CGRect(x: 18, y: 340, width: 284, height: 1))
        separator.boxType = .separator
        root.addSubview(separator)

        let clearButton = NSButton(title: "清空失效条目", target: self, action: #selector(clearMissing))
        clearButton.frame = CGRect(x: 18, y: 346, width: 128, height: 24)
        clearButton.controlSize = .small
        clearButton.bezelStyle = .rounded
        clearButton.font = .systemFont(ofSize: 11)
        root.addSubview(clearButton)

        deleteButton.target = self
        deleteButton.action = #selector(deletePanel)
        deleteButton.frame = CGRect(x: 208, y: 346, width: 94, height: 24)
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
        colorWell.color = PanelAppearance.customTint(for: config.backgroundHex)
        opacitySlider.doubleValue = config.opacity
        opacityValue.stringValue = "\(Int(config.opacity * 100))%"
        columnsStepper.integerValue = config.columns
        columnsValue.stringValue = "\(config.columns)"
        sizeControl.selectedSegment = closestSizeIndex(to: config.frame)
        levelControl.selectedSegment = config.levelMode == .desktop ? 0 : 1
        lockCheckbox.state = config.positionLocked ? .on : .off
        deleteButton.isEnabled = appStore.canDeletePanel

        for (index, button) in swatches.enumerated() {
            let swatchColor = NSColor(hex: presets[index])
            button.layer?.backgroundColor = swatchColor.cgColor
            let selected = presets[index].caseInsensitiveCompare(config.backgroundHex) == .orderedSame
            button.layer?.borderWidth = selected ? 2 : 1
            button.layer?.borderColor = selected
                ? NSColor.controlAccentColor.cgColor
                : NSColor.separatorColor.withAlphaComponent(0.7).cgColor
        }
    }

    @objc private func swatchTapped(_ sender: NSButton) {
        guard presets.indices.contains(sender.tag) else { return }
        store.setBackground(hex: presets[sender.tag])
    }

    @objc private func colorWellChanged(_ sender: NSColorWell) {
        store.setBackground(hex: sender.color.hexString)
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        store.config.opacity = sender.doubleValue
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
