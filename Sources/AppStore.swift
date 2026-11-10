import Combine
import Darwin
import Foundation

final class AppStore: ObservableObject {
    @Published private(set) var panels: [PanelStore] = []
    @Published private(set) var fileOperations: [FileOperationRecord] = []
    @Published private(set) var autoAbsorbStatus = AutoAbsorbStatus()

    var onShowFileActivity: (() -> Void)?
    var onFileRestored: ((URL) -> Void)?

    private let persistence: Persistence
    private let operationJournal: FileOperationJournal
    private let configuredStorageDirectory: URL?
    private let fileOperationQueue = DispatchQueue(
        label: "com.covet.DesktopFolderWidget.file-operations",
        qos: .userInitiated
    )
    // Accessed only on fileOperationQueue. Makes overlapping watcher/UI requests idempotent.
    private var absorbedDestinations: [String: URL] = [:]
    private var saveWork: DispatchWorkItem?

    init(persistence: Persistence = Persistence(), storageDirectory: URL? = nil) {
        self.persistence = persistence
        self.configuredStorageDirectory = storageDirectory
        self.operationJournal = FileOperationJournal(directory: persistence.supportDirectory)
        self.fileOperations = operationJournal.operations
        if let warning = operationJournal.loadWarning {
            self.autoAbsorbStatus = AutoAbsorbStatus(
                phase: .attention,
                pendingCount: 1,
                message: warning
            )
        }

        if let saved = persistence.load(), !saved.isEmpty {
            panels = saved.map(PanelStore.init)
        } else {
            panels = [PanelStore(config: .makeDefault(index: 0))]
        }
        panels.forEach(attach)
        saveNow()
    }

    var storageDirectory: URL {
        configuredStorageDirectory ?? Self.defaultStorageDirectory
    }

    var canDeletePanel: Bool { panels.count > 1 }

    var allHidden: Bool {
        !panels.isEmpty && panels.allSatisfy { $0.config.isHidden }
    }

    var recoverableOperationCount: Int {
        fileOperations.filter(\.canRestore).count
    }

    func newPanel() {
        let panel = PanelStore(config: .makeDefault(index: panels.count))
        attach(panel)
        panels.append(panel)
        scheduleSave()
    }

    func removePanel(_ panel: PanelStore) {
        guard canDeletePanel, let index = panels.firstIndex(where: { $0.id == panel.id }) else { return }
        panels.remove(at: index)
        scheduleSave()
    }

    func toggleAll() {
        let hidden = !allHidden
        for panel in panels {
            panel.config.isHidden = hidden
        }
    }

    struct AbsorbResult {
        var added: [URL] = []
        var rejected: [URL] = []
        var failed: [URL] = []
        var resolved: [String: URL] = [:]
        var moved: [String: URL] = [:]
        var operationIDs: [UUID] = []
    }

    enum AbsorbSourceDisposition: Equatable {
        case reject
        case alreadyStored
        case move
    }

    static var defaultStorageDirectory: URL {
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents", isDirectory: true)
        return documents.appendingPathComponent("文档整理", isDirectory: true)
    }

    // Bundle.main caches the launch path; proc_pidpath reflects the executable's current path.
    static var currentAppBundleURL: URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 else {
            return Bundle.main.bundleURL
        }
        return URL(fileURLWithPath: String(cString: buffer))
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func isSameOrDescendant(_ candidate: String, of parent: String) -> Bool {
        if candidate == parent { return true }
        let prefix = parent.hasSuffix("/") ? parent : parent + "/"
        return candidate.hasPrefix(prefix)
    }

    static func absorbDisposition(
        for url: URL,
        storagePath: String,
        appPath: String
    ) -> AbsorbSourceDisposition {
        let sourcePath = canonicalPath(url)
        if isSameOrDescendant(appPath, of: sourcePath) || url.pathExtension.lowercased() == "app" {
            return .reject
        }
        if isSameOrDescendant(sourcePath, of: storagePath) {
            return .alreadyStored
        }
        if isSameOrDescendant(storagePath, of: sourcePath) {
            return .reject
        }
        return .move
    }

    static func uniqueDestination(in directory: URL, name: String) -> URL {
        let fileManager = FileManager.default
        let pathExtension = (name as NSString).pathExtension
        let baseName = (name as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(name)
        var index = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let newName = pathExtension.isEmpty
                ? "\(baseName) \(index)"
                : "\(baseName) \(index).\(pathExtension)"
            candidate = directory.appendingPathComponent(newName)
            index += 1
        }
        return candidate
    }

    func absorb(
        urls: [URL],
        kind: FileOperationKind = .manualAbsorb,
        completion: @escaping (AbsorbResult) -> Void
    ) {
        let storage = storageDirectory
        fileOperationQueue.async { [self] in
            let result = performJournaledAbsorb(urls: urls, storageURL: storage, kind: kind)
            let operationsSnapshot = operationJournal.operations
            DispatchQueue.main.async {
                self.fileOperations = operationsSnapshot
                completion(result)
            }
        }
    }

    private func performJournaledAbsorb(
        urls: [URL],
        storageURL: URL,
        kind: FileOperationKind
    ) -> AbsorbResult {
        let fileManager = FileManager.default
        var result = AbsorbResult()
        var pending: [URL] = []
        var seenPaths = Set<String>()

        for url in urls {
            let path = Self.canonicalPath(url)
            guard seenPaths.insert(path).inserted else { continue }

            if !fileManager.fileExists(atPath: url.path),
               let destination = absorbedDestinations[path],
               fileManager.fileExists(atPath: destination.path) {
                result.added.append(destination)
                result.resolved[path] = destination
            } else {
                pending.append(url)
            }
        }

        do {
            try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        } catch {
            result.failed.append(contentsOf: pending)
            return result
        }

        let appPath = Self.canonicalPath(Self.currentAppBundleURL)
        let storagePath = Self.canonicalPath(storageURL)

        for url in pending {
            let sourcePath = Self.canonicalPath(url)

            switch Self.absorbDisposition(
                for: url,
                storagePath: storagePath,
                appPath: appPath
            ) {
            case .reject:
                result.rejected.append(url)
                continue
            case .alreadyStored:
                result.added.append(url)
                result.resolved[sourcePath] = url
                continue
            case .move:
                break
            }

            guard fileManager.fileExists(atPath: url.path) else {
                result.failed.append(url)
                continue
            }

            let destination = Self.uniqueDestination(in: storageURL, name: url.lastPathComponent)
            let operationID: UUID
            do {
                operationID = try operationJournal.prepareMove(
                    kind: kind,
                    source: url,
                    destination: destination
                )
            } catch {
                result.failed.append(url)
                continue
            }

            do {
                try fileManager.moveItem(at: url, to: destination)
                result.added.append(destination)
                result.resolved[sourcePath] = destination
                result.moved[sourcePath] = destination
                result.operationIDs.append(operationID)
                absorbedDestinations[sourcePath] = destination

                do {
                    try operationJournal.markCompleted(operationID)
                } catch {
                    operationJournal.markRecoveryPending(
                        operationID,
                        error: "文件已移动，但操作记录尚未完成写入；下次启动会根据原位置和目标位置自动核对。\(error.localizedDescription)"
                    )
                    publishRecoveryAttention("文件已移动，操作记录正在等待恢复核对")
                }
            } catch {
                operationJournal.markFailed(operationID, error: error.localizedDescription)
                result.failed.append(url)
            }
        }

        return result
    }

    func renameItem(
        at source: URL,
        to newName: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains(":")
        else {
            completion(.failure(FileOperationError.invalidName))
            return
        }

        fileOperationQueue.async { [self] in
            let fileManager = FileManager.default
            let sourceURL = source.standardizedFileURL
            let destination = sourceURL.deletingLastPathComponent().appendingPathComponent(trimmed)

            guard fileManager.fileExists(atPath: sourceURL.path) else {
                DispatchQueue.main.async { completion(.failure(FileOperationError.sourceMissing)) }
                return
            }
            guard Self.canonicalPath(sourceURL) != Self.canonicalPath(destination) else {
                DispatchQueue.main.async { completion(.success(sourceURL)) }
                return
            }
            guard !fileManager.fileExists(atPath: destination.path) else {
                DispatchQueue.main.async { completion(.failure(FileOperationError.destinationExists)) }
                return
            }

            do {
                let operationID = try operationJournal.prepareMove(
                    kind: .rename,
                    source: sourceURL,
                    destination: destination
                )
                do {
                    try fileManager.moveItem(at: sourceURL, to: destination)
                } catch {
                    operationJournal.markFailed(operationID, error: error.localizedDescription)
                    throw error
                }

                do {
                    try operationJournal.markCompleted(operationID)
                } catch {
                    operationJournal.markRecoveryPending(
                        operationID,
                        error: "文件已重命名，但操作记录尚未完成写入；下次启动会自动核对。\(error.localizedDescription)"
                    )
                    publishRecoveryAttention("文件已重命名，操作记录正在等待恢复核对")
                }

                let operationsSnapshot = operationJournal.operations
                DispatchQueue.main.async {
                    self.replacePanelReferences(from: sourceURL, to: destination)
                    self.fileOperations = operationsSnapshot
                    self.saveNow()
                    completion(.success(destination))
                }
            } catch {
                let operationsSnapshot = operationJournal.operations
                DispatchQueue.main.async {
                    self.fileOperations = operationsSnapshot
                    completion(.failure(error))
                }
            }
        }
    }

    func restoreOperation(
        _ id: UUID,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        fileOperationQueue.async { [self] in
            let fileManager = FileManager.default
            guard let record = operationJournal.record(for: id), record.state == .completed else {
                DispatchQueue.main.async { completion(.failure(FileOperationJournalError.operationNotRestorable)) }
                return
            }

            let movedURL = record.destinationURL
            guard fileManager.fileExists(atPath: movedURL.path) else {
                operationJournal.markNeedsAttention(id, error: "收纳后的文件已不存在，无法自动恢复")
                publishRecoveryAttention("有文件已不在收纳目录，无法自动恢复")
                let operationsSnapshot = operationJournal.operations
                DispatchQueue.main.async {
                    self.fileOperations = operationsSnapshot
                    completion(.failure(FileOperationError.destinationMissing))
                }
                return
            }

            if let expected = record.fileResourceIdentifier,
               let actual = FileOperationJournal.resourceIdentifier(at: movedURL),
               expected != actual {
                operationJournal.markNeedsAttention(
                    id,
                    error: "目标路径中的文件身份已变化。为避免移动错误文件，已停止恢复。"
                )
                publishRecoveryAttention("文件身份发生变化，已阻止自动恢复")
                let operationsSnapshot = operationJournal.operations
                DispatchQueue.main.async {
                    self.fileOperations = operationsSnapshot
                    completion(.failure(FileOperationError.fileIdentityChanged))
                }
                return
            }

            let originalURL = record.sourceURL
            let originalParent = originalURL.deletingLastPathComponent()
            guard fileManager.fileExists(atPath: originalParent.path) else {
                operationJournal.markRestoreFailed(id, error: "原目录已不存在，请先恢复原目录后重试")
                publishRecoveryAttention("原目录已不存在，恢复操作暂时无法完成")
                let operationsSnapshot = operationJournal.operations
                DispatchQueue.main.async {
                    self.fileOperations = operationsSnapshot
                    completion(.failure(FileOperationError.originalFolderMissing))
                }
                return
            }

            let restoreURL: URL
            if fileManager.fileExists(atPath: originalURL.path) {
                let name = originalURL.lastPathComponent
                let ext = (name as NSString).pathExtension
                let base = (name as NSString).deletingPathExtension
                let restoredName = ext.isEmpty
                    ? "\(base) (恢复副本)"
                    : "\(base) (恢复副本).\(ext)"
                restoreURL = Self.uniqueDestination(in: originalParent, name: restoredName)
            } else {
                restoreURL = originalURL
            }

            do {
                try operationJournal.beginRestore(id, to: restoreURL)
                do {
                    try fileManager.moveItem(at: movedURL, to: restoreURL)
                } catch {
                    operationJournal.markRestoreFailed(id, error: error.localizedDescription)
                    throw error
                }

                do {
                    try operationJournal.markRestored(id, at: restoreURL)
                } catch {
                    operationJournal.markRecoveryPending(
                        id,
                        error: "文件已恢复，但恢复记录尚未完成写入；下次启动会自动核对。\(error.localizedDescription)"
                    )
                    publishRecoveryAttention("文件已恢复，操作记录正在等待恢复核对")
                }

                let operationsSnapshot = operationJournal.operations
                DispatchQueue.main.async {
                    self.replacePanelReferences(from: movedURL, to: restoreURL)
                    self.fileOperations = operationsSnapshot
                    self.saveNow()
                    self.onFileRestored?(restoreURL)
                    completion(.success(restoreURL))
                }
            } catch {
                let operationsSnapshot = operationJournal.operations
                DispatchQueue.main.async {
                    self.fileOperations = operationsSnapshot
                    completion(.failure(error))
                }
            }
        }
    }

    func restoreLatestOperation(
        for path: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let record = fileOperations
            .filter({ $0.canRestore && $0.destinationPath == URL(fileURLWithPath: path).standardizedFileURL.path })
            .max(by: { $0.createdAt < $1.createdAt })
        else {
            completion(.failure(FileOperationJournalError.operationNotRestorable))
            return
        }
        restoreOperation(record.id, completion: completion)
    }

    private func replacePanelReferences(from source: URL, to destination: URL) {
        let sourcePath = source.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path
        for panel in panels {
            panel.replacePath(from: sourcePath, to: destinationPath)
        }
    }

    private func publishRecoveryAttention(_ message: String) {
        DispatchQueue.main.async {
            self.updateAutoAbsorbStatus(phase: .attention, pendingCount: 1, message: message)
        }
    }

    func updateAutoAbsorbStatus(
        phase: AutoAbsorbPhase,
        pendingCount: Int = 0,
        message: String
    ) {
        autoAbsorbStatus = AutoAbsorbStatus(
            phase: phase,
            pendingCount: pendingCount,
            message: message,
            updatedAt: Date()
        )
    }

    // Enqueue a completion after all previously submitted file moves.
    func drainFileOperations(completion: @escaping () -> Void) {
        fileOperationQueue.async {
            DispatchQueue.main.async(execute: completion)
        }
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        persistence.save(panels.map(\.config))
    }

    private func attach(_ panel: PanelStore) {
        panel.onChange = { [weak self] in self?.scheduleSave() }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
}

enum FileOperationError: LocalizedError {
    case invalidName
    case sourceMissing
    case destinationExists
    case destinationMissing
    case fileIdentityChanged
    case originalFolderMissing

    var errorDescription: String? {
        switch self {
        case .invalidName: return "文件名不能为空，也不能包含路径分隔符或保留名称"
        case .sourceMissing: return "原文件已不存在"
        case .destinationExists: return "目标位置已有同名文件，请换一个名称"
        case .destinationMissing: return "收纳后的文件已不存在，无法恢复"
        case .fileIdentityChanged: return "目标文件身份已变化，为避免误操作已停止恢复"
        case .originalFolderMissing: return "原目录已不存在，请先恢复原目录后重试"
        }
    }
}
