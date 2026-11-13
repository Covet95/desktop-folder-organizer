import AppKit
import Foundation
import QuartzCore

final class SnapshotRunner {
    private let root: URL
    private let appStore: AppStore
    private let store: PanelStore
    private let panelView: PanelView
    private let panelWindow: NSWindow
    private let settingsController: SettingsViewController
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

        let persistence = JSONPanelStateRepository(directory: root.appendingPathComponent("support", isDirectory: true))
        let storageDir = root.appendingPathComponent("storage", isDirectory: true)
        try! FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        appStore = AppStore(persistence: persistence, storageDirectory: storageDir)
        store = appStore.panels[0]
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
        panelWindow.appearance = NSAppearance(named: .darkAqua)
        panelWindow.contentView = panelView
        panelWindow.setFrameOrigin(NSPoint(x: 120, y: 160))

        settingsController = SettingsViewController(store: store, appStore: appStore)
        let settingsSize = settingsController.preferredContentSize
        settingsWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: settingsSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        settingsWindow.backgroundColor = .windowBackgroundColor
        settingsWindow.level = .floating
        settingsWindow.contentViewController = settingsController
        settingsWindow.setContentSize(settingsSize)
        settingsWindow.setFrameOrigin(NSPoint(x: 560, y: 200))
        expect(panelView.style == .clear, "panel uses native Clear Liquid Glass")
        expect(panelView.tintColor == nil, "panel does not apply a custom glass tint")
        expect(!panelView.effectIsInteractive, "panel glass does not add button-like interaction effects")
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
            panelWindow.appearance = NSAppearance(named: .aqua)
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
            panelWindow.appearance = NSAppearance(named: .darkAqua)
            settingsWindow.appearance = NSAppearance(named: .darkAqua)
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
        guard let first = store.config.items.first,
              let target = store.config.items.first(where: { $0.name == "会议纪要.txt" }),
              let expectedSavedIndex = store.config.items.firstIndex(where: { $0.id == target.id })
        else {
            expect(false, "reorder test has items")
            return
        }

        // Find the target tile center inside the window coordinates so intra-group reorder works with grouping on.
        panelView.layoutSubtreeIfNeeded()
        guard let targetTile = findSubview(in: panelView, matching: { ($0 as? ItemView)?.item.id == target.id }) else {
            expect(false, "reorder test locates target item view")
            return
        }
        let targetCenterInWindow = targetTile.convert(
            NSPoint(x: targetTile.bounds.midX, y: targetTile.bounds.midY),
            to: nil
        )

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.covet.dfw.reorder.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(first.id.uuidString, forType: PanelView.itemPasteboardType)
        pasteboard.writeObjects([pasteboardItem])

        let handled = panelView.performDrop(
            pasteboard: pasteboard,
            location: targetCenterInWindow
        )
        expect(handled, "internal reorder reports handled")

        let newIndex = store.config.items.firstIndex(where: { $0.id == first.id })
        expect(
            newIndex == expectedSavedIndex,
            "internal reorder moves item to target slot \(expectedSavedIndex) (got \(String(describing: newIndex)))"
        )
    }

    private func findSubview(in root: NSView, matching predicate: (NSView) -> Bool) -> NSView? {
        if predicate(root) { return root }
        for subview in root.subviews {
            if let match = findSubview(in: subview, matching: predicate) {
                return match
            }
        }
        return nil
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
