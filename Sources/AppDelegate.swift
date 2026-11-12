import AppKit
import Carbon.HIToolbox
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appStore = AppStore()

    private var controllers: [UUID: PanelWindowController] = [:]
    private var statusBar: StatusBarController?
    private var globalHotKey: GlobalHotKey?
    private var desktopIntakeCoordinator: DesktopIntakeCoordinator?
    private var fileActivityWindowController: FileActivityWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var isWaitingForFileOperationsBeforeTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()
        statusBar = StatusBarController(delegate: self)
        appStore.onShowFileActivity = { [weak self] in self?.showFileActivity() }
        desktopIntakeCoordinator = DesktopIntakeCoordinator(appStore: appStore)
        desktopIntakeCoordinator?.start()
        appStore.$panels
            .sink { [weak self] panels in self?.syncWindows(panels) }
            .store(in: &cancellables)

        globalHotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.toggleAll()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isWaitingForFileOperationsBeforeTermination else { return .terminateLater }
        isWaitingForFileOperationsBeforeTermination = true
        desktopIntakeCoordinator?.stop()

        appStore.drainFileOperations { [weak self] in
            self?.appStore.saveNow()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        desktopIntakeCoordinator?.stop()
        appStore.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func openFullPanel() {
        guard let panel = appStore.panels.first else { return }
        // Open the interactive desktop panel from the menu bar.
        panel.config.levelMode = .floating
        panel.config.isHidden = false
        if controllers[panel.id] == nil {
            syncWindows(appStore.panels)
        }
        NSApp.activate(ignoringOtherApps: true)
        controllers[panel.id]?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func newPanel() {
        appStore.newPanel()
    }

    @objc func toggleAll() {
        appStore.toggleAll()
    }

    @objc func openStorageDirectory() {
        let storage = appStore.storageDirectory
        do {
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        } catch {
            NSLog("DesktopFolderWidget: failed to create storage: \(error)")
        }
        NSWorkspace.shared.open(storage)
    }

    @objc func showFileActivity() {
        if fileActivityWindowController == nil {
            fileActivityWindowController = FileActivityWindowController(appStore: appStore)
        }
        NSApp.activate(ignoringOtherApps: true)
        fileActivityWindowController?.showWindow(nil)
        fileActivityWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func syncWindows(_ panels: [PanelStore]) {
        let ids = Set(panels.map(\.id))
        let staleIDs = controllers.keys.filter { !ids.contains($0) }

        for id in staleIDs {
            controllers[id]?.close()
            controllers.removeValue(forKey: id)
        }

        for store in panels where controllers[store.id] == nil {
            controllers[store.id] = PanelWindowController(store: store, appStore: appStore)
        }
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "关于文档整理",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "退出文档整理",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu

        let panelMenuItem = NSMenuItem()
        mainMenu.addItem(panelMenuItem)
        let panelMenu = NSMenu(title: "面板")
        let newItem = NSMenuItem(title: "新建面板", action: #selector(newPanel), keyEquivalent: "n")
        newItem.target = self
        panelMenu.addItem(newItem)
        let toggleItem = NSMenuItem(title: "显示/隐藏全部面板 (⇧⌘T)", action: #selector(toggleAll), keyEquivalent: "")
        toggleItem.target = self
        panelMenu.addItem(toggleItem)
        panelMenuItem.submenu = panelMenu

        NSApp.mainMenu = mainMenu
    }
}
