import AppKit

final class PanelContextMenuController: NSObject {
    private weak var panelView: PanelView?
    private let store: PanelStore
    private let appStore: AppStore

    init(panelView: PanelView, store: PanelStore, appStore: AppStore) {
        self.panelView = panelView
        self.store = store
        self.appStore = appStore
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(item("添加文件…", action: #selector(addFiles)))
        menu.addItem(item("打开存储目录", action: #selector(openStorage)))
        menu.addItem(item("收纳记录与恢复…", action: #selector(showActivity)))
        menu.addItem(item("搜索文件", action: #selector(search)))
        menu.addItem(item("面板设置…", action: #selector(settings)))

        menu.addItem(item(
            store.config.positionLocked ? "解锁位置" : "锁定位置",
            action: #selector(toggleLock)
        ))

        menu.addItem(.separator())
        menu.addItem(item("新建面板", action: #selector(newPanel)))
        menu.addItem(item("显示/隐藏全部面板", action: #selector(toggleAll)))

        let delete = item("删除此面板", action: #selector(deletePanel))
        delete.isEnabled = appStore.canDeletePanel
        menu.addItem(delete)

        menu.addItem(.separator())
        menu.addItem(item("检查更新…", action: #selector(checkForUpdates)))
        menu.addItem(item("退出", action: #selector(quit)))
        return menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func addFiles() {
        panelView?.requestAddFiles()
    }

    @objc private func openStorage() {
        do {
            let storage = try appStore.prepareStorageDirectory()
            NSWorkspace.shared.open(storage)
        } catch {
            NSAlert.showMessage(title: "无法打开存储目录", message: error.localizedDescription)
        }
    }

    @objc private func showActivity() {
        appStore.onShowFileActivity?()
    }

    @objc private func search() {
        panelView?.beginSearch()
    }

    @objc private func settings() {
        panelView?.requestSettings()
    }

    @objc private func toggleLock() {
        store.config.isLocked = !store.config.positionLocked
    }

    @objc private func newPanel() {
        appStore.newPanel()
    }

    @objc private func toggleAll() {
        appStore.toggleAll()
    }

    @objc private func deletePanel() {
        appStore.removePanel(store)
    }

    @objc private func checkForUpdates() {
        appStore.onCheckForUpdates?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
