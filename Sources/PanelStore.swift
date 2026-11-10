import AppKit
import Combine
import Foundation

final class PanelStore: ObservableObject, Identifiable {
    let id: UUID
    @Published var config: PanelConfig
    @Published var searchText: String = ""
    @Published var isSearchVisible: Bool = false

    init(config: PanelConfig) {
        self.id = config.id
        self.config = config
    }

    var filteredItems: [WidgetItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return config.items }
        return config.items.filter { $0.name.localizedStandardContains(query) }
    }

    func add(urls: [URL]) {
        var seen = Set(config.items.map { $0.path })
        var added: [WidgetItem] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !path.isEmpty, !seen.contains(path) else { continue }
            seen.insert(path)
            added.append(WidgetItem(path: path))
        }
        guard !added.isEmpty else { return }
        config.items.append(contentsOf: added)
    }

    func remove(id: UUID) {
        config.items.removeAll { $0.id == id }
    }

    func removeMissing() {
        config.items.removeAll { !$0.exists }
    }

    func move(id: UUID, toIndex index: Int) {
        guard let from = config.items.firstIndex(where: { $0.id == id }), !config.items.isEmpty else { return }
        moveItem(from: from, to: max(0, min(index, config.items.count - 1)))
    }

    private func moveItem(from: Int, to: Int) {
        guard from != to else { return }
        var items = config.items
        let item = items.remove(at: from)
        items.insert(item, at: max(0, min(to, items.count)))
        config.items = items
    }

    func relocate(id: UUID, to url: URL) {
        guard let index = config.items.firstIndex(where: { $0.id == id }) else { return }
        config.items[index].path = url.standardizedFileURL.path
    }

    func replacePath(from sourcePath: String, to destinationPath: String) {
        let source = URL(fileURLWithPath: sourcePath).standardizedFileURL.path
        let destination = URL(fileURLWithPath: destinationPath).standardizedFileURL.path
        var items = config.items
        var changed = false
        for index in items.indices where URL(fileURLWithPath: items[index].path).standardizedFileURL.path == source {
            items[index].path = destination
            changed = true
        }
        if changed {
            config.items = items
        }
    }

    func updateFrame(_ frame: PanelFrame) {
        guard config.frame != frame else { return }
        config.frame = frame
    }

    func resize(width: Double, height: Double) {
        var rect = config.frame.rect
        rect.origin.y += rect.height - height
        rect.size.width = width
        rect.size.height = height

        // 夹紧到屏幕可视区域
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
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

        config.frame = PanelFrame(rect: rect)
    }

    func setBackground(hex: String) {
        config.backgroundHex = hex
    }

    func open(_ item: WidgetItem) {
        guard item.exists else {
            NSSound.beep()
            return
        }
        if !NSWorkspace.shared.open(item.url) {
            NSSound.beep()
        }
    }

    func reveal(_ item: WidgetItem) {
        guard item.exists else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}
