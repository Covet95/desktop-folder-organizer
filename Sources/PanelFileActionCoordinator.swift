import AppKit

final class PanelFileActionCoordinator {
    private let appStore: AppStore
    private let panelStore: PanelStore

    init(appStore: AppStore, panelStore: PanelStore) {
        self.appStore = appStore
        self.panelStore = panelStore
    }

    func chooseFiles(from window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "移动并添加"
        panel.message = "所选原文件将移动到「文档整理」目录"
        NSApp.activate(ignoringOtherApps: true)

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK else { return }
            self?.absorb(panel.urls)
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func absorb(
        _ urls: [URL],
        completion: ((AppStore.AbsorbResult) -> Void)? = nil
    ) {
        guard !urls.isEmpty else { return }
        appStore.absorb(urls: urls, kind: .manualAbsorb) { [weak self] result in
            guard let self else {
                completion?(result)
                return
            }

            self.panelStore.add(urls: result.added)
            if !result.added.isEmpty {
                self.appStore.saveNow()
            }

            let blocked = result.rejected + result.failed
            if !blocked.isEmpty {
                self.showAlert(
                    title: "\(blocked.count) 个项目无法收纳",
                    message: blocked.map(\.lastPathComponent).joined(separator: "\n"),
                    style: .warning
                )
            }
            completion?(result)
        }
    }

    func canRestore(_ item: WidgetItem) -> Bool {
        let path = item.url.standardizedFileURL.path
        return appStore.fileOperations.contains {
            $0.canRestore && $0.destinationPath == path
        }
    }

    func rename(_ item: WidgetItem, from window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "重命名文件"
        alert.informativeText = "重命名会修改磁盘上的实际文件名，并记录可撤销操作。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "重命名")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(string: item.name)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.appStore.renameItem(at: item.url, to: field.stringValue) { result in
                if case .failure(let error) = result {
                    self?.showAlert(title: "重命名失败", message: error.localizedDescription, style: .warning)
                }
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        if let window {
            alert.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(alert.runModal())
        }
    }

    func restore(_ item: WidgetItem, from window: NSWindow?) {
        guard canRestore(item) else {
            showAlert(title: "没有可恢复的操作", message: "该项目没有尚未撤销的移动或重命名记录。", style: .informational)
            return
        }

        let alert = NSAlert()
        alert.messageText = "恢复原位置？"
        alert.informativeText = "「\(item.name)」将从当前目录移动回上一次操作前的位置。若原位置已有同名文件，将另存为恢复副本，不会覆盖现有文件。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "取消")

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.appStore.restoreLatestOperation(for: item.url.path) { result in
                switch result {
                case .success(let url):
                    self?.showAlert(
                        title: "已恢复",
                        message: "文件已恢复到：\n\(url.path)",
                        style: .informational
                    )
                case .failure(let error):
                    self?.showAlert(title: "恢复失败", message: error.localizedDescription, style: .warning)
                }
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        if let window {
            alert.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(alert.runModal())
        }
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.runModal()
    }
}
