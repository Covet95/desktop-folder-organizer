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

    init(delegate: AppDelegate) {
        self.delegate = delegate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "文档整理")
            button.image?.size = NSSize(width: 17, height: 17)
            button.toolTip = "文档整理 · 自动监控中"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(menuItem("新建文档面板", action: #selector(newPanel), key: "n"))
        menu.addItem(menuItem("打开存储目录", action: #selector(openStorageDirectory), key: ""))

        let status = menuItem("自动监控中", action: #selector(showFileActivity), key: "")
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status

        let activity = menuItem("收纳记录与恢复…", action: #selector(showFileActivity), key: "")
        menu.addItem(activity)
        activityItem = activity

        menu.addItem(menuItem("显示/隐藏全部面板 (⇧⌘T)", action: #selector(toggleAll), key: ""))

        let launch = menuItem("开机自启", action: #selector(toggleLaunchAtLogin), key: "")
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launch)
        launchItem = launch

        menu.addItem(.separator())
        menu.addItem(menuItem("退出", action: #selector(quit), key: "q"))
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
        delegate.appStore.$fileOperations
            .sink { [weak self] operations in
                self?.updateHistoryCount(operations.filter(\.canRestore).count)
            }
            .store(in: &cancellables)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        launchItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func updateStatusDisplay() {
        if let warning = persistenceWarning {
            if let button = statusItem.button {
                button.image = NSImage(
                    systemSymbolName: "exclamationmark.triangle.fill",
                    accessibilityDescription: "面板配置需要恢复"
                )
                button.image?.size = NSSize(width: 17, height: 17)
                button.toolTip = "文档整理 · 面板配置需要恢复\n\(warning)"
            }
            statusMenuItem?.title = "面板配置需要恢复 · \(warning)"
            return
        }

        let status = latestAutoAbsorbStatus
        let warning = status.phase == .retrying || status.phase == .attention
        let symbol = warning
            ? "exclamationmark.triangle.fill"
            : (status.phase == .processing ? "arrow.down.doc" : "folder.fill")
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "文档整理")
            button.image?.size = NSSize(width: 17, height: 17)
            button.toolTip = "文档整理 · \(status.phase.title)\n\(status.detail)"
        }
        statusMenuItem?.title = "\(status.phase.title) · \(status.detail)"
    }

    private func updateHistoryCount(_ count: Int) {
        activityItem?.title = count > 0 ? "收纳记录与恢复（\(count) 项可恢复）…" : "收纳记录与恢复…"
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
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "无法修改开机自启"
            alert.informativeText = "\(error.localizedDescription)\n\n请先把「文档整理」移动到「应用程序」文件夹后再试。"
            alert.alertStyle = .warning
            alert.runModal()
        }
        launchItem?.state = service.status == .enabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
