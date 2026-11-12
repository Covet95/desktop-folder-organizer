import Foundation

struct WidgetSummaryItem: Codable, Equatable {
    let name: String
    let isFolder: Bool
}

struct DesktopWidgetSnapshot: Codable, Equatable {
    static let kind = "DesktopFolderSummaryWidget"
    static var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "DFWAppGroupIdentifier") as? String
            ?? "group.com.covet.DesktopFolderWidget"
    }
    static let filename = "widget-snapshot.json"

    let updatedAt: Date
    let itemCount: Int
    let items: [WidgetSummaryItem]

    static func load() -> DesktopWidgetSnapshot? {
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else { return nil }

        let url = directory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DesktopWidgetSnapshot.self, from: data)
    }

    static func make(from urls: [URL]) -> DesktopWidgetSnapshot {
        let fileManager = FileManager.default
        let sorted = urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        let items = sorted.prefix(8).map { url in
            let isFolder = (try? url.resourceValues(
                forKeys: [.isDirectoryKey]
            ).isDirectory) ?? fileManager.isDirectory(at: url)
            return WidgetSummaryItem(name: url.lastPathComponent, isFolder: isFolder)
        }
        return DesktopWidgetSnapshot(updatedAt: Date(), itemCount: urls.count, items: items)
    }
}

private extension FileManager {
    func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
