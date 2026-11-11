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

    /// Keep managed folder items in sync while preserving manually added external references
    /// and the order/identities of items that are still present.
    func synchronizeManagedItems(_ urls: [URL], directory: URL) {
        let root = directory.standardizedFileURL.path
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        var items = config.items.filter { item in
            let url = URL(fileURLWithPath: item.path).standardizedFileURL
            return url.deletingLastPathComponent().path != root || paths.contains(url.path)
        }
        var seen = Set(items.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path })
        for url in urls.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                items.append(WidgetItem(path: path))
            }
        }
        if items != config.items {
            config.items = items
        }
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

    func setBackground(hex: String) {
        config.backgroundHex = hex
    }
}
