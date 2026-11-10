import AppKit
import Foundation
import QuartzCore

final class SnapshotRunner {
    private let root: URL
    private let appStore: AppStore
    private let store: PanelStore
    private let panelView: PanelView
    private let panelWindow: NSWindow
    private let settingsWindow: NSWindow
    private let urls: [URL]
    private var step = 0
    private var failures = 0

    init() {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appendingPathComponent("dfw-snapshot-\(UUID().uuidString)", isDirectory: true)
        try! fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let fixtures = root.appendingPathComponent("fixtures", isDirectory: true)
        try! fileManager.createDirectory(at: fixtures, withIntermediateDirectories: true)

        let names = [
            "季度报告.pdf", "预算表.xlsx", "项目计划.docx", "会议纪要.txt",
            "设计稿.png", "演示文稿.key", "数据.csv", "合同.pdf",
            "发票.pdf", "截图.png", "README.md", "备份.zip", "客户资料"
        ]
        var fixtureURLs: [URL] = []
        for name in names {
            let url = fixtures.appendingPathComponent(name)
            if name == "客户资料" {
                try! fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                fileManager.createFile(atPath: url.path, contents: Data("x".utf8))
            }
            fixtureURLs.append(url)
        }
        urls = fixtureURLs

        let persistence = Persistence(directory: root.appendingPathComponent("support", isDirectory: true))
        let storageDir = root.appendingPathComponent("storage", isDirectory: true)
        try! FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        appStore = AppStore(persistence: persistence, storageDirectory: storageDir)
        store = appStore.panels[0]
        store.config.backgroundHex = "#1C1C1E"
        store.config.opacity = 1.0
        store.config.columns = 5

        panelView = PanelView(store: store, appStore: appStore)
        panelWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 360),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panelWindow.isOpaque = false
        panelWindow.backgroundColor = .clear
        panelWindow.level = .floating
        panelWindow.contentView = panelView
        panelWindow.setFrameOrigin(NSPoint(x: 120, y: 160))

        let settings = SettingsViewController(store: store, appStore: appStore)
        settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 360),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        settingsWindow.level = .floating
        settingsWindow.contentView = settings.view
        settingsWindow.setFrameOrigin(NSPoint(x: 560, y: 200))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func start() {
        panelWindow.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.runNext() }
    }

    private func runNext() {
        switch step {
        case 0:
            capture(panelView, "/tmp/dfw_empty_dark.png")
        case 1:
            dropFiles()
            return
        case 2:
            capture(panelView, "/tmp/dfw_items_dark.png")
            testReorder()
        case 3:
            store.config.backgroundHex = "#F2F2F7"
        case 4:
            capture(panelView, "/tmp/dfw_items_light.png")
            panelView.setHovering(true)
        case 5:
            capture(panelView, "/tmp/dfw_toolbar_light.png")
            panelView.setHovering(false)
        case 6:
            store.searchText = "报告"
            store.isSearchVisible = true
        case 7:
            print("search state: filtered=\(store.filteredItems.count)")
            capture(panelView, "/tmp/dfw_search_light.png")
        case 8:
            store.searchText = ""
            store.isSearchVisible = false
            store.config.backgroundHex = "#0F3D3A"
            settingsWindow.orderFrontRegardless()
        case 9:
            if let content = settingsWindow.contentView {
                capture(content, "/tmp/dfw_settings.png")
            }
        default:
            print(failures == 0 ? "snapshots written, all checks passed" : "snapshots written, \(failures) checks failed")
            try? FileManager.default.removeItem(at: root)
            exit(failures == 0 ? 0 : 1)
        }

        step += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.runNext() }
    }

    private func dropFiles() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.covet.dfw.snapshot.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })

        let performed = panelView.performDrop(
            pasteboard: pasteboard,
            location: .zero
        ) { [weak self] result in
            guard let self else { return }
            self.expect(result.added.count == self.urls.count, "file drop absorbs every fixture")
            self.expect(
                self.store.config.items.count == self.urls.count,
                "file drop adds every item (got \(self.store.config.items.count))"
            )
            self.step += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.runNext() }
        }
        expect(performed, "file drop reports handled")

        guard performed else {
            step += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.runNext() }
            return
        }
    }

    private func testReorder() {
        guard let first = store.config.items.first else {
            expect(false, "reorder test has items")
            return
        }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.covet.dfw.reorder.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(first.id.uuidString, forType: PanelView.itemPasteboardType)
        pasteboard.writeObjects([pasteboardItem])

        let handled = panelView.performDrop(
            pasteboard: pasteboard,
            location: NSPoint(x: 202, y: 284)
        )
        expect(handled, "internal reorder reports handled")

        let newIndex = store.config.items.firstIndex(where: { $0.id == first.id })
        expect(newIndex == 2, "internal reorder moves item to slot 2 (got \(String(describing: newIndex)))")
    }

    private func expect(_ condition: Bool, _ message: String) {
        if condition {
            print("PASS  \(message)")
        } else {
            print("FAIL  \(message)")
            failures += 1
        }
    }

    private func capture(_ view: NSView, _ path: String) {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        CATransaction.flush()

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("no bitmap rep for \(path)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("no png for \(path)")
            return
        }
        try! data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) \(Int(view.bounds.width))x\(Int(view.bounds.height))")
    }
}

@main
struct SnapshotTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let runner = SnapshotRunner()
        runner.start()
        app.run()
    }
}
