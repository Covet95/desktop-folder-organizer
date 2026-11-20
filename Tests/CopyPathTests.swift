import AppKit
import Foundation

private final class StubPanelStateRepository: PanelStateRepository {
    let supportDirectory: URL

    init(directory: URL) {
        self.supportDirectory = directory
    }

    func load() -> PanelStateLoadResult { .missing }
    func save(_ panels: [PanelConfig]) throws {}
}

@main
struct CopyPathTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        var failures = 0
        func expect(_ condition: Bool, _ message: String) {
            if condition {
                print("PASS  \(message)")
            } else {
                print("FAIL  \(message)")
                failures += 1
            }
        }

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("dfw-copypath-\(UUID().uuidString)", isDirectory: true)
        try! fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let specialFile = root.appendingPathComponent("季度 报告 (终版).pdf")
        fileManager.createFile(atPath: specialFile.path, contents: Data("pdf".utf8))

        let folderURL = root.appendingPathComponent("客户资料", isDirectory: true)
        try! fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let missingURL = root.appendingPathComponent("已移动文件.txt")

        let fileItem = WidgetItem(path: specialFile.path)
        let folderItemWithSlash = WidgetItem(path: folderURL.path + "/")
        let missingItem = WidgetItem(path: missingURL.path)
        let emptyItem = WidgetItem(path: "   ")

        expect(
            PanelFileActionCoordinator.standardizedPath(for: fileItem) == specialFile.path,
            "standardizedPath preserves spaces, parentheses, and Chinese characters without percent-encoding"
        )
        expect(
            PanelFileActionCoordinator.standardizedPath(for: folderItemWithSlash) == folderURL.path,
            "standardizedPath trims trailing slash on directory paths"
        )
        expect(
            PanelFileActionCoordinator.standardizedPath(for: missingItem) == missingURL.path,
            "standardizedPath returns recorded path for missing items"
        )
        expect(
            PanelFileActionCoordinator.standardizedPath(for: emptyItem) == nil,
            "standardizedPath rejects blank paths"
        )

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.covet.dfw.copypath.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("stale-value", forType: .string)

        let copiedFile = PanelFileActionCoordinator.copyPath(of: fileItem, to: pasteboard)
        expect(copiedFile == specialFile.path, "copyPath returns copied POSIX file path")
        expect(pasteboard.string(forType: .string) == specialFile.path, "pasteboard contains plain unquoted POSIX path")
        expect(
            pasteboard.types?.contains(.fileURL) != true,
            "pasteboard does not include fileURL so pasting inserts the path string instead of the file object"
        )

        let copiedFolder = PanelFileActionCoordinator.copyPath(of: folderItemWithSlash, to: pasteboard)
        expect(copiedFolder == folderURL.path, "copyPath replaces previous pasteboard contents with folder path")
        expect(pasteboard.string(forType: .string) == folderURL.path, "pasteboard string matches normalized folder path")

        expect(
            PanelFileActionCoordinator.copyPath(of: emptyItem, to: pasteboard) == nil,
            "copyPath returns nil for empty path"
        )
        expect(
            pasteboard.string(forType: .string) == folderURL.path,
            "failed copyPath leaves previous pasteboard contents intact"
        )

        let persistence = StubPanelStateRepository(directory: root.appendingPathComponent("support", isDirectory: true))
        let storageDir = root.appendingPathComponent("storage", isDirectory: true)
        try! fileManager.createDirectory(at: storageDir, withIntermediateDirectories: true)
        let appStore = AppStore(persistence: persistence, storageDirectory: storageDir)
        let panelStore = appStore.panels[0]
        let panelView = PanelView(store: panelStore, appStore: appStore)
        panelView.frame = NSRect(x: 0, y: 0, width: 390, height: 360)
        panelView.layoutSubtreeIfNeeded()

        expect(!panelView.isToastVisible, "copy feedback toast starts hidden")

        let rightClick = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!

        let fileMetadata = IconProvider.shared.metadata(for: fileItem, forceRefresh: true)
        let fileTile = ItemView(item: fileItem, metadata: fileMetadata, store: panelStore, labelColor: .labelColor)
        fileTile.panelView = panelView

        if let fileMenu = fileTile.menu(for: rightClick) {
            expect(!fileMenu.autoenablesItems, "item context menu disables autoenablesItems to preserve explicit enabled states")
            let copyMenuItem = fileMenu.items.first { $0.title == "复制文件地址" }
            expect(copyMenuItem != nil, "item context menu includes 复制文件地址")
            expect(copyMenuItem?.isEnabled == true, "复制文件地址 is enabled for existing files")
            expect(copyMenuItem?.target === fileTile && copyMenuItem?.action != nil, "复制文件地址 targets ItemView")

            let trashMenuItem = fileMenu.items.first { $0.title == "移到废纸篓…" }
            expect(trashMenuItem != nil, "item context menu includes 移到废纸篓…")
            expect(trashMenuItem?.isEnabled == true, "移到废纸篓… is enabled for existing files")
            expect(trashMenuItem?.target === fileTile && trashMenuItem?.action != nil, "移到废纸篓… targets ItemView")
        } else {
            expect(false, "file ItemView returns context menu")
        }

        let folderMetadata = IconProvider.shared.metadata(for: folderItemWithSlash, forceRefresh: true)
        let folderTile = ItemView(item: folderItemWithSlash, metadata: folderMetadata, store: panelStore, labelColor: .labelColor)
        folderTile.panelView = panelView
        if let folderMenu = folderTile.menu(for: rightClick) {
            let copyMenuItem = folderMenu.items.first { $0.title == "复制文件地址" }
            let trashMenuItem = folderMenu.items.first { $0.title == "移到废纸篓…" }
            expect(copyMenuItem?.isEnabled == true, "复制文件地址 is enabled for folders")
            expect(trashMenuItem?.isEnabled == true, "移到废纸篓… is enabled for folders")
        } else {
            expect(false, "folder ItemView returns context menu")
        }

        let missingMetadata = IconProvider.shared.metadata(for: missingItem, forceRefresh: true)
        let missingTile = ItemView(item: missingItem, metadata: missingMetadata, store: panelStore, labelColor: .labelColor)
        missingTile.panelView = panelView
        if let missingMenu = missingTile.menu(for: rightClick) {
            let openMenuItem = missingMenu.items.first { $0.title == "打开" }
            let copyMenuItem = missingMenu.items.first { $0.title == "复制文件地址" }
            let trashMenuItem = missingMenu.items.first { $0.title == "移到废纸篓…" }
            expect(openMenuItem?.isEnabled == false, "打开 is disabled for missing files")
            expect(copyMenuItem?.isEnabled == true, "复制文件地址 remains enabled for missing items with a recorded path")
            expect(trashMenuItem?.isEnabled == false, "移到废纸篓… is disabled for missing files")
        } else {
            expect(false, "missing ItemView returns context menu")
        }

        let storageItem = WidgetItem(path: storageDir.path)
        let storageMeta = IconProvider.shared.metadata(for: storageItem, forceRefresh: true)
        let storageTile = ItemView(item: storageItem, metadata: storageMeta, store: panelStore, labelColor: .labelColor)
        storageTile.panelView = panelView
        if let storageMenu = storageTile.menu(for: rightClick) {
            let trashMenuItem = storageMenu.items.first { $0.title == "移到废纸篓…" }
            expect(trashMenuItem?.isEnabled == false, "移到废纸篓… is disabled for managed storage directory")
        } else {
            expect(false, "storage ItemView returns context menu")
        }

        let emptyTile = ItemView(item: emptyItem, metadata: .missing, store: panelStore, labelColor: .labelColor)
        if let emptyMenu = emptyTile.menu(for: rightClick) {
            let copyMenuItem = emptyMenu.items.first { $0.title == "复制文件地址" }
            expect(copyMenuItem?.isEnabled == false, "复制文件地址 is disabled when path is blank")
        } else {
            expect(false, "empty ItemView returns context menu")
        }

        let copiedFromTile = fileTile.copyPath(to: pasteboard)
        expect(copiedFromTile, "ItemView.copyPath succeeds")
        expect(pasteboard.string(forType: .string) == specialFile.path, "ItemView.copyPath writes file path to pasteboard")
        expect(panelView.isToastVisible, "ItemView.copyPath triggers transient confirmation toast on PanelView")

        print(failures == 0 ? "ALL COPY PATH TESTS PASSED" : "\(failures) COPY PATH TESTS FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
