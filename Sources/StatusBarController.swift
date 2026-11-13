import AppKit
import Combine
import ServiceManagement

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private weak var delegate: AppDelegate?
    private var launchItem: NSMenuItem?
    private var activityItem: NSMenuItem?
    private var statusMenuItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()
    private var latestAutoAbsorbStatus = AutoAbsorbStatus()
    private var persistenceWarning: String?

    private enum MenuBarIconState {
        case idle
        case processing
        case warning
    }

    init(delegate: AppDelegate) {
        self.delegate = delegate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.makeMenuBarIcon(state: .idle)
            button.imagePosition = .imageOnly
            button.toolTip = "文档整理 · 自动收纳已开启"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(menuItem("打开完整管理面板…", symbol: "macwindow", action: #selector(openFullPanel), key: ""))
        menu.addItem(menuItem("新建文档面板", symbol: "plus.square", action: #selector(newPanel), key: "n"))
        menu.addItem(menuItem("打开存储目录", symbol: "folder", action: #selector(openStorageDirectory), key: ""))

        let status = menuItem("自动收纳已开启", symbol: "checkmark.circle", action: #selector(showFileActivity), key: "")
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status

        let activity = menuItem("收纳记录与恢复…", symbol: "clock.arrow.circlepath", action: #selector(showFileActivity), key: "")
        menu.addItem(activity)
        activityItem = activity

        menu.addItem(menuItem("显示/隐藏全部面板 (⇧⌘T)", symbol: "eye", action: #selector(toggleAll), key: ""))

        let launch = menuItem("开机自启", symbol: "power", action: #selector(toggleLaunchAtLogin), key: "")
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launch)
        launchItem = launch

        menu.addItem(.separator())
        menu.addItem(menuItem("退出", symbol: nil, action: #selector(quit), key: "q"))
        statusItem.menu = menu

        delegate.appStore.$autoAbsorbStatus
            .sink { [weak self] status in
                self?.latestAutoAbsorbStatus = status
                self?.updateStatusDisplay()
            }
            .store(in: &cancellables)
        delegate.appStore.$persistenceWarning
            .sink { [weak self] warning in
                self?.persistenceWarning = warning
                self?.updateStatusDisplay()
            }
            .store(in: &cancellables)
        let appStore = delegate.appStore
        appStore.$fileOperations
            .sink { [weak self, weak appStore] _ in
                self?.updateHistoryCount(appStore?.recoverableOperationCount ?? 0)
            }
            .store(in: &cancellables)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        launchItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func menuItem(_ title: String, symbol: String?, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol {
            item.image = Self.menuSymbol(symbol)
        }
        return item
    }

    private func updateStatusDisplay() {
        if let warning = persistenceWarning {
            if let button = statusItem.button {
                button.image = Self.makeMenuBarIcon(state: .warning)
                button.toolTip = "文档整理 · 面板配置需要恢复\n\(warning)"
            }
            statusMenuItem?.title = "面板配置需要恢复 · \(warning)"
            statusMenuItem?.image = Self.menuSymbol("exclamationmark.triangle")
            return
        }

        let status = latestAutoAbsorbStatus
        let isWarning = status.phase == .retrying || status.phase == .attention
        let iconState: MenuBarIconState = isWarning
            ? .warning
            : (status.phase == .processing ? .processing : .idle)
        if let button = statusItem.button {
            button.image = Self.makeMenuBarIcon(state: iconState)
            button.toolTip = "文档整理 · \(status.phase.title)\n\(status.detail)"
        }
        statusMenuItem?.title = "\(status.phase.title) · \(status.detail)"
        let statusSymbol = isWarning
            ? "exclamationmark.triangle"
            : (status.phase == .processing ? "arrow.down.circle" : "checkmark.circle")
        statusMenuItem?.image = Self.menuSymbol(statusSymbol)
    }

    private static func menuSymbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    }

    /// Bespoke 18x18 template icon echoing the rounded folder + peeking document card motif.
    private static func makeMenuBarIcon(state: MenuBarIconState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // Clean peeking document card tucked behind the upper-right shoulder (no collision with left tab)
            let peekingCard = NSBezierPath(
                roundedRect: NSRect(x: 8.6, y: 10.6, width: 6.2, height: 4.1),
                xRadius: 1.35,
                yRadius: 1.35
            )
            peekingCard.lineWidth = 1.3
            NSColor.black.withAlphaComponent(0.78).setStroke()
            peekingCard.stroke()

            // Secondary subtle card edge offset slightly behind
            let backSheet = NSBezierPath()
            backSheet.lineWidth = 1.15
            backSheet.lineCapStyle = .round
            backSheet.move(to: NSPoint(x: 9.7, y: 15.8))
            backSheet.line(to: NSPoint(x: 13.6, y: 15.8))
            NSColor.black.withAlphaComponent(0.42).setStroke()
            backSheet.stroke()

            // Rounded folder pocket (clears overlap beneath for crisp layered separation)
            let folderPath = NSBezierPath()
            folderPath.move(to: NSPoint(x: 2.0, y: 4.8))
            folderPath.line(to: NSPoint(x: 2.0, y: 12.1))
            folderPath.curve(
                to: NSPoint(x: 3.6, y: 13.7),
                controlPoint1: NSPoint(x: 2.0, y: 13.0),
                controlPoint2: NSPoint(x: 2.7, y: 13.7)
            )
            folderPath.line(to: NSPoint(x: 6.1, y: 13.7))
            folderPath.curve(
                to: NSPoint(x: 7.4, y: 12.7),
                controlPoint1: NSPoint(x: 6.7, y: 13.7),
                controlPoint2: NSPoint(x: 7.0, y: 13.1)
            )
            folderPath.line(to: NSPoint(x: 8.0, y: 11.9))
            folderPath.line(to: NSPoint(x: 14.3, y: 11.9))
            folderPath.curve(
                to: NSPoint(x: 16.0, y: 10.2),
                controlPoint1: NSPoint(x: 15.3, y: 11.9),
                controlPoint2: NSPoint(x: 16.0, y: 11.2)
            )
            folderPath.line(to: NSPoint(x: 16.0, y: 4.8))
            folderPath.curve(
                to: NSPoint(x: 13.9, y: 2.7),
                controlPoint1: NSPoint(x: 16.0, y: 3.6),
                controlPoint2: NSPoint(x: 15.1, y: 2.7)
            )
            folderPath.line(to: NSPoint(x: 4.1, y: 2.7))
            folderPath.curve(
                to: NSPoint(x: 2.0, y: 4.8),
                controlPoint1: NSPoint(x: 2.9, y: 2.7),
                controlPoint2: NSPoint(x: 2.0, y: 3.6)
            )
            folderPath.close()

            ctx.saveGState()
            ctx.setBlendMode(.clear)
            folderPath.fill()
            ctx.restoreGState()

            folderPath.lineWidth = 1.4
            folderPath.lineJoinStyle = .round
            folderPath.lineCapStyle = .round
            NSColor.black.setStroke()
            folderPath.stroke()

            // Crisp front pocket lip line
            let lip = NSBezierPath()
            lip.lineWidth = 1.15
            lip.lineCapStyle = .round
            lip.move(to: NSPoint(x: 2.4, y: 9.7))
            lip.line(to: NSPoint(x: 15.6, y: 9.7))
            NSColor.black.withAlphaComponent(0.84).setStroke()
            lip.stroke()

            // State-specific indicator centered in the lower folder pocket
            switch state {
            case .idle:
                let grip = NSBezierPath(
                    roundedRect: NSRect(x: 6.7, y: 5.7, width: 4.6, height: 1.3),
                    xRadius: 0.65,
                    yRadius: 0.65
                )
                NSColor.black.withAlphaComponent(0.76).setFill()
                grip.fill()

            case .processing:
                let arrow = NSBezierPath()
                arrow.lineWidth = 1.35
                arrow.lineCapStyle = .round
                arrow.lineJoinStyle = .round
                arrow.move(to: NSPoint(x: 9.0, y: 8.0))
                arrow.line(to: NSPoint(x: 9.0, y: 4.7))
                arrow.move(to: NSPoint(x: 7.2, y: 6.3))
                arrow.line(to: NSPoint(x: 9.0, y: 4.5))
                arrow.line(to: NSPoint(x: 10.8, y: 6.3))
                NSColor.black.setStroke()
                arrow.stroke()

            case .warning:
                let stem = NSBezierPath(
                    roundedRect: NSRect(x: 8.35, y: 5.9, width: 1.3, height: 2.2),
                    xRadius: 0.65,
                    yRadius: 0.65
                )
                NSColor.black.setFill()
                stem.fill()
                let dot = NSBezierPath(ovalIn: NSRect(x: 8.3, y: 4.1, width: 1.4, height: 1.4))
                dot.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func updateHistoryCount(_ count: Int) {
        activityItem?.title = count > 0 ? "收纳记录与恢复（\(count) 项可恢复）…" : "收纳记录与恢复…"
    }

    @objc private func openFullPanel() {
        delegate?.openFullPanel()
    }

    @objc private func newPanel() {
        delegate?.newPanel()
    }

    @objc private func toggleAll() {
        delegate?.toggleAll()
    }

    @objc private func openStorageDirectory() {
        delegate?.openStorageDirectory()
    }

    @objc private func showFileActivity() {
        delegate?.showFileActivity()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSAlert.showMessage(
                title: "无法修改开机自启",
                message: "\(error.localizedDescription)\n\n请先把「文档整理」移动到「应用程序」文件夹后再试。"
            )
        }
        launchItem?.state = service.status == .enabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
