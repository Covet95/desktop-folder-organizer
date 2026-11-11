import Foundation

struct PersistedState: Codable {
    var version: Int
    var panels: [PanelConfig]
}

enum PanelStateLoadResult {
    case missing
    case loaded([PanelConfig])
    case recoveryRequired(String)
}

protocol PanelStateRepository {
    var supportDirectory: URL { get }
    func load() -> PanelStateLoadResult
    func save(_ panels: [PanelConfig]) throws
}

/// JSON-backed implementation of the panel-state repository.
final class JSONPanelStateRepository: PanelStateRepository {
    static let currentVersion = 1

    private let directory: URL
    private let fileURL: URL
    private let fileManager = FileManager.default
    private var writeBlockReason: String?
    private var hasLoaded = false

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

    func load() -> PanelStateLoadResult {
        hasLoaded = true
        writeBlockReason = nil
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .missing
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            let reason = "无法读取面板配置文件，已停止覆盖原文件：\(error.localizedDescription)"
            writeBlockReason = reason
            return .recoveryRequired(reason)
        }

        let state: PersistedState
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            state = try decoder.decode(PersistedState.self, from: data)
        } catch {
            return preserveCorruptData(data, cause: error)
        }

        guard state.version == Self.currentVersion else {
            let reason = "面板配置版本 \(state.version) 与当前支持版本 \(Self.currentVersion) 不一致，已停止写入以保护原配置"
            writeBlockReason = reason
            return .recoveryRequired(reason)
        }

        let normalizedPanels = state.panels.map { panel -> PanelConfig in
            var normalized = panel
            normalized.opacity = PanelDefaults.normalizedMaterialOpacity(panel.opacity)
            return normalized
        }
        return .loaded(normalizedPanels)
    }

    func save(_ panels: [PanelConfig]) throws {
        if !hasLoaded {
            _ = load()
        }
        if let writeBlockReason {
            throw PanelStatePersistenceError.recoveryRequired(writeBlockReason)
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(
            PersistedState(version: Self.currentVersion, panels: panels)
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private func preserveCorruptData(
        _ data: Data,
        cause: Error
    ) -> PanelStateLoadResult {
        let backupURL = directory.appendingPathComponent(
            "panels.corrupt-\(UUID().uuidString).json"
        )

        let backupMessage: String
        do {
            try data.write(to: backupURL, options: .atomic)
            backupMessage = "原始内容已备份至 \(backupURL.lastPathComponent)"
        } catch {
            backupMessage = "自动备份失败：\(error.localizedDescription)。原文件仍保留在原位置"
        }

        let reason = "面板配置无法解析：\(cause.localizedDescription)。\(backupMessage)。已停止覆盖原配置"
        writeBlockReason = reason
        NSLog("DesktopFolderWidget: \(reason)")
        return .recoveryRequired(reason)
    }
}

enum PanelStatePersistenceError: LocalizedError {
    case recoveryRequired(String)

    var errorDescription: String? {
        switch self {
        case .recoveryRequired(let reason):
            return "为保护现有配置，暂时停止保存：\(reason)"
        }
    }
}
