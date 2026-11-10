import Foundation

struct PersistedState: Codable {
    var version: Int
    var panels: [PanelConfig]
}

final class Persistence {
    private let directory: URL
    private let fileURL: URL
    private let fileManager = FileManager.default

    var supportDirectory: URL { directory }

    init(directory: URL? = nil) {
        let base = directory ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            .map { $0.appendingPathComponent("DesktopFolderWidget", isDirectory: true) }
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/DesktopFolderWidget", isDirectory: true)
        self.directory = base
        self.fileURL = base.appendingPathComponent("panels.json")
    }

    func load() -> [PanelConfig]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(PersistedState.self, from: data).panels
        } catch {
            NSLog("DesktopFolderWidget: load failed: \(error)")
            let backup = directory.appendingPathComponent(
                "panels.corrupt-\(Int(Date().timeIntervalSince1970)).json"
            )
            try? data.write(to: backup)
            return nil
        }
    }

    func save(_ panels: [PanelConfig]) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(PersistedState(version: 1, panels: panels))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("DesktopFolderWidget: save failed: \(error)")
        }
    }
}
