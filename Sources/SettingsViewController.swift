import AppKit
import Combine

final class SettingsViewController: NSViewController {
    private let store: PanelStore
    private let appStore: AppStore
    var onDelete: (() -> Void)?

    private let sizes: [(Double, Double)] = [(330, 300), (390, 360), (480, 440)]
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let sizeControl = NSSegmentedControl(labels: ["小", "中", "大"], trackingMode: .selectOne, target: nil, action: nil)
    private let columnsValue = NSTextField(labelWithString: "")
    private let columnsStepper = NSStepper(frame: .zero)
    private let levelControl = NSSegmentedControl(labels: ["桌面层", "悬浮置顶"], trackingMode: .selectOne, target: nil, action: nil)
    private let appearanceControl = NSSegmentedControl(labels: ["自动", "浅色", "深色"], trackingMode: .selectOne, target: nil, action: nil)
    private let lockCheckbox = NSButton(checkboxWithTitle: "锁定位置与尺寸（禁止拖动）", target: nil, action: nil)
    private let groupCheckbox = NSButton(checkboxWithTitle: "按文件类型分区显示", target: nil, action: nil)
    private let clearButton = NSButton(title: "清理失效项", target: nil, action: nil)
    private let deleteButton = NSButton(title: "删除面板", target: nil, action: nil)
    private var cancellables = Set<AnyCancellable>()

    init(store: PanelStore, appStore: AppStore) {
        self.store = store
        self.appStore = appStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = FlippedView()
        root.onAppearanceChanged = { [weak self] in
            guard let self else { return }
            self.update(self.store.config)
        }
        view = root

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mainStack)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 344),
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])

        // Header
        let headerStack = NSStackView()
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 3

        let titleLabel = makeLabel("面板设置", font: PanelAppearance.Typography.settingsTitle)
        subtitleLabel.font = PanelAppearance.Typography.settingsDetail
        subtitleLabel.textColor = .secondaryLabelColor
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(subtitleLabel)
        mainStack.addArrangedSubview(headerStack)

        // Content Layout Section Card
        mainStack.setCustomSpacing(10, after: headerStack)
        mainStack.addArrangedSubview(
            makeLabel("内容布局", font: PanelAppearance.Typography.settingsSection, color: .secondaryLabelColor)
        )
        let layoutCard = makeSectionCard(spacing: 8)

        let columnsRow = NSStackView()
        columnsRow.orientation = .horizontal
        columnsRow.alignment = .centerY
        columnsRow.spacing = 8

        let columnsLabel = makeLabel("每行最多图标", font: PanelAppearance.Typography.settingsLabel)
        let columnsSpacer = NSView()
        columnsSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        columnsStepper.controlSize = .regular
        columnsStepper.minValue = 3
        columnsStepper.maxValue = 7
        columnsStepper.increment = 1
        columnsStepper.target = self
        columnsStepper.action = #selector(columnsChanged(_:))

        columnsValue.alignment = .right
        columnsValue.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        columnsValue.widthAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true

        columnsRow.addArrangedSubview(columnsLabel)
        columnsRow.addArrangedSubview(columnsSpacer)
        columnsRow.addArrangedSubview(columnsStepper)
        columnsRow.addArrangedSubview(columnsValue)
        layoutCard.stack.addArrangedSubview(columnsRow)
        columnsRow.widthAnchor.constraint(equalTo: layoutCard.stack.widthAnchor).isActive = true

        let columnsHint = makeLabel(
            "窄面板会自动减少显示列数，优先保证文件名完整可读",
            font: PanelAppearance.Typography.settingsDetail,
            color: .secondaryLabelColor
        )
        layoutCard.stack.setCustomSpacing(4, after: columnsRow)
        layoutCard.stack.addArrangedSubview(columnsHint)

        groupCheckbox.controlSize = .regular
        groupCheckbox.font = PanelAppearance.Typography.settingsLabel
        groupCheckbox.target = self
        groupCheckbox.action = #selector(groupingChanged(_:))
        layoutCard.stack.setCustomSpacing(10, after: columnsHint)
        layoutCard.stack.addArrangedSubview(groupCheckbox)

        mainStack.setCustomSpacing(6, after: mainStack.arrangedSubviews.last!)
        mainStack.addArrangedSubview(layoutCard.card)
        layoutCard.card.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // Window & Appearance Section Card
        mainStack.setCustomSpacing(12, after: layoutCard.card)
        let appearanceSectionLabel = makeLabel(
            "窗口与外观",
            font: PanelAppearance.Typography.settingsSection,
            color: .secondaryLabelColor
        )
        mainStack.addArrangedSubview(appearanceSectionLabel)
        let appearanceCard = makeSectionCard(spacing: 10)

        sizeControl.controlSize = .regular
        sizeControl.font = PanelAppearance.Typography.settingsLabel
        sizeControl.target = self
        sizeControl.action = #selector(sizeChanged(_:))
        addControlRow(title: "面板尺寸", control: sizeControl, to: appearanceCard.stack)

        levelControl.controlSize = .regular
        levelControl.font = PanelAppearance.Typography.settingsLabel
        levelControl.target = self
        levelControl.action = #selector(levelChanged(_:))
        addControlRow(title: "窗口层级", control: levelControl, to: appearanceCard.stack)

        appearanceControl.controlSize = .regular
        appearanceControl.font = PanelAppearance.Typography.settingsLabel
        appearanceControl.target = self
        appearanceControl.action = #selector(appearanceChanged(_:))
        addControlRow(title: "面板外观", control: appearanceControl, to: appearanceCard.stack)

        lockCheckbox.controlSize = .regular
        lockCheckbox.font = PanelAppearance.Typography.settingsLabel
        lockCheckbox.target = self
        lockCheckbox.action = #selector(lockChanged(_:))
        appearanceCard.stack.addArrangedSubview(lockCheckbox)

        mainStack.setCustomSpacing(6, after: appearanceSectionLabel)
        mainStack.addArrangedSubview(appearanceCard.card)
        appearanceCard.card.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // Footer actions
        mainStack.setCustomSpacing(14, after: appearanceCard.card)
        let actionsRow = NSStackView()
        actionsRow.orientation = .horizontal
        actionsRow.alignment = .centerY
        actionsRow.spacing = 8

        clearButton.target = self
        clearButton.action = #selector(clearMissing)
        clearButton.controlSize = .regular
        clearButton.bezelStyle = .rounded
        clearButton.font = PanelAppearance.Typography.button

        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        deleteButton.target = self
        deleteButton.action = #selector(deletePanel)
        deleteButton.controlSize = .regular
        deleteButton.bezelStyle = .rounded
        deleteButton.font = PanelAppearance.Typography.button
        deleteButton.contentTintColor = .systemRed

        actionsRow.addArrangedSubview(clearButton)
        actionsRow.addArrangedSubview(actionSpacer)
        actionsRow.addArrangedSubview(deleteButton)
        mainStack.addArrangedSubview(actionsRow)
        actionsRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

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
        root.layoutSubtreeIfNeeded()
        preferredContentSize = root.fittingSize
    }

    private func makeLabel(
        _ text: String,
        font: NSFont,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        return label
    }

    private func makeSectionCard(spacing: CGFloat) -> (card: NSView, stack: NSStackView) {
        let card = SettingsCardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        return (card, stack)
    }

    private func addControlRow(
        title: String,
        control: NSSegmentedControl,
        to stack: NSStackView
    ) {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 5
        container.addArrangedSubview(makeLabel(title, font: PanelAppearance.Typography.settingsLabel))
        container.addArrangedSubview(control)
        control.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(container)
        control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func update(_ config: PanelConfig) {
        let itemCount = config.items.count
        subtitleLabel.stringValue = config.positionLocked
            ? "共 \(itemCount) 项 · 位置与尺寸已锁定"
            : "共 \(itemCount) 项 · 可拖动面板右下角自由缩放"

        columnsStepper.integerValue = config.columns
        columnsValue.stringValue = "\(config.columns) 列"
        sizeControl.selectedSegment = closestSizeIndex(to: config.frame)
        levelControl.selectedSegment = config.levelMode == .desktop ? 0 : 1
        switch config.effectiveAppearanceMode {
        case .system: appearanceControl.selectedSegment = 0
        case .light: appearanceControl.selectedSegment = 1
        case .dark: appearanceControl.selectedSegment = 2
        }
        lockCheckbox.state = config.positionLocked ? .on : .off
        groupCheckbox.state = config.isTypeGroupingEnabled ? .on : .off

        let missingCount = config.items.reduce(0) { count, item in
            let exists = IconProvider.shared.metadata(for: item).exists
            return count + (exists ? 0 : 1)
        }
        clearButton.title = missingCount > 0 ? "清理失效项 (\(missingCount))" : "清理失效项"
        clearButton.isEnabled = missingCount > 0

        deleteButton.isEnabled = appStore.canDeletePanel
        deleteButton.contentTintColor = appStore.canDeletePanel ? .systemRed : .tertiaryLabelColor
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

    @objc private func appearanceChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 1: store.config.appearanceMode = .light
        case 2: store.config.appearanceMode = .dark
        default: store.config.appearanceMode = .system
        }
    }

    @objc private func lockChanged(_ sender: NSButton) {
        store.config.isLocked = sender.state == .on
    }

    @objc private func groupingChanged(_ sender: NSButton) {
        store.config.groupByType = sender.state == .on
    }

    @objc private func clearMissing() {
        store.removeMissing()
        update(store.config)
    }

    @objc private func deletePanel() {
        guard appStore.canDeletePanel else { return }
        if store.config.items.isEmpty {
            onDelete?()
            return
        }
        let alert = NSAlert()
        alert.messageText = "删除此面板？"
        alert.informativeText = "这只会移除面板视图，不会删除「文档整理」目录中的磁盘文件。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除面板")
        alert.addButton(withTitle: "取消")
        alert.present(from: view.window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.onDelete?()
            }
        }
    }
}

private final class SettingsCardView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        translatesAutoresizingMaskIntoConstraints = false
        applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        layer?.backgroundColor = resolvedCGColor(PanelAppearance.cardFill)
        layer?.borderColor = resolvedCGColor(PanelAppearance.cardBorder)
    }
}

private final class FlippedView: NSView {
    var onAppearanceChanged: (() -> Void)?

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChanged?()
    }
}
