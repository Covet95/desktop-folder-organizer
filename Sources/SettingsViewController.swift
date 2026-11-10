import AppKit
import Combine

final class SettingsViewController: NSViewController {
    private let store: PanelStore
    private let appStore: AppStore
    var onDelete: (() -> Void)?

    private let presets = ["#1C1C1E", "#0F3D3A", "#3A2E52", "#F2F2F7", "#FFFFFF", "#1E3A5F"]
    private let sizes: [(Double, Double)] = [(330, 300), (390, 360), (480, 440)]
    private var swatches: [NSButton] = []
    private let colorWell = NSColorWell(frame: .zero)
    private let sizeControl = NSSegmentedControl(labels: ["小", "中", "大"], trackingMode: .selectOne, target: nil, action: nil)
    private let opacitySlider = NSSlider(value: 0.92, minValue: 0.4, maxValue: 1.0, target: nil, action: nil)
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
        preferredContentSize = NSSize(width: 300, height: 360)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 300, height: 360))
        view = root

        addLabel("面板设置", frame: CGRect(x: 16, y: 14, width: 268, height: 18), font: .systemFont(ofSize: 13, weight: .semibold))
        addLabel("背景颜色", frame: CGRect(x: 16, y: 44, width: 268, height: 14), font: .systemFont(ofSize: 11), color: .secondaryLabelColor)

        for (index, hex) in presets.enumerated() {
            let button = NSButton(frame: CGRect(x: 16 + CGFloat(index) * 28, y: 66, width: 22, height: 22))
            button.title = ""
            button.isBordered = false
            button.tag = index
            button.target = self
            button.action = #selector(swatchTapped(_:))
            button.wantsLayer = true
            button.layer?.cornerRadius = 11
            button.layer?.backgroundColor = NSColor(hex: hex).cgColor
            root.addSubview(button)
            swatches.append(button)
        }

        colorWell.frame = CGRect(x: 190, y: 66, width: 22, height: 22)
        colorWell.colorWellStyle = .minimal
        colorWell.target = self
        colorWell.action = #selector(colorWellChanged(_:))
        root.addSubview(colorWell)

        addLabel("不透明度", frame: CGRect(x: 16, y: 104, width: 70, height: 18), font: .systemFont(ofSize: 12))
        opacitySlider.frame = CGRect(x: 92, y: 102, width: 150, height: 20)
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        root.addSubview(opacitySlider)
        opacityValue.frame = CGRect(x: 246, y: 104, width: 40, height: 18)
        opacityValue.alignment = .right
        opacityValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        root.addSubview(opacityValue)

        addLabel("每行图标", frame: CGRect(x: 16, y: 138, width: 100, height: 18), font: .systemFont(ofSize: 12))
        columnsStepper.frame = CGRect(x: 234, y: 135, width: 20, height: 24)
        columnsStepper.minValue = 3
        columnsStepper.maxValue = 7
        columnsStepper.increment = 1
        columnsStepper.target = self
        columnsStepper.action = #selector(columnsChanged(_:))
        root.addSubview(columnsStepper)
        columnsValue.frame = CGRect(x: 258, y: 138, width: 26, height: 18)
        columnsValue.alignment = .right
        columnsValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        root.addSubview(columnsValue)

        addLabel("面板尺寸", frame: CGRect(x: 16, y: 172, width: 268, height: 14), font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        sizeControl.frame = CGRect(x: 16, y: 192, width: 268, height: 24)
        sizeControl.target = self
        sizeControl.action = #selector(sizeChanged(_:))
        root.addSubview(sizeControl)

        addLabel("窗口层级", frame: CGRect(x: 16, y: 226, width: 268, height: 14), font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        levelControl.frame = CGRect(x: 16, y: 246, width: 268, height: 24)
        levelControl.target = self
        levelControl.action = #selector(levelChanged(_:))
        root.addSubview(levelControl)

        lockCheckbox.frame = CGRect(x: 16, y: 274, width: 268, height: 18)
        lockCheckbox.font = .systemFont(ofSize: 11)
        lockCheckbox.target = self
        lockCheckbox.action = #selector(lockChanged(_:))
        root.addSubview(lockCheckbox)

        let separator = NSBox(frame: CGRect(x: 16, y: 300, width: 268, height: 1))
        separator.boxType = .separator
        root.addSubview(separator)

        let clearButton = NSButton(title: "清空失效条目", target: self, action: #selector(clearMissing))
        clearButton.frame = CGRect(x: 16, y: 320, width: 120, height: 24)
        clearButton.bezelStyle = .rounded
        clearButton.font = .systemFont(ofSize: 11)
        root.addSubview(clearButton)

        deleteButton.target = self
        deleteButton.action = #selector(deletePanel)
        deleteButton.frame = CGRect(x: 190, y: 320, width: 94, height: 24)
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
        colorWell.color = NSColor(hex: config.backgroundHex)
        opacitySlider.doubleValue = config.opacity
        opacityValue.stringValue = "\(Int(config.opacity * 100))%"
        columnsStepper.integerValue = config.columns
        columnsValue.stringValue = "\(config.columns)"
        sizeControl.selectedSegment = closestSizeIndex(to: config.frame)
        levelControl.selectedSegment = config.levelMode == .desktop ? 0 : 1
        lockCheckbox.state = config.positionLocked ? .on : .off
        deleteButton.isEnabled = appStore.canDeletePanel

        for (index, button) in swatches.enumerated() {
            let selected = presets[index].caseInsensitiveCompare(config.backgroundHex) == .orderedSame
            button.layer?.borderWidth = selected ? 2 : 1
            button.layer?.borderColor = selected
                ? NSColor.labelColor.cgColor
                : NSColor.labelColor.withAlphaComponent(0.15).cgColor
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
        var rect = store.config.frame.resized(
            width: sizes[index].0,
            height: sizes[index].1
        ).rect

        if let visible = NSScreen.main?.visibleFrame {
            if rect.origin.y < visible.minY {
                rect.origin.y = visible.minY
            }
            if rect.origin.x + rect.width > visible.maxX {
                rect.origin.x = visible.maxX - rect.width
            }
            if rect.origin.y + rect.height > visible.maxY {
                rect.origin.y = visible.maxY - rect.height
            }
        }

        store.updateFrame(PanelFrame(rect: rect))
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
    override var isFlipped: Bool { true }
}
