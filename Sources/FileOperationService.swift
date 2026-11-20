import Darwin
import Foundation

/// Owns serialized filesystem operations and their write-ahead journal.
/// All journal mutations and filesystem moves run on one private queue.
final class FileOperationService {
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

    struct RestoreOutcome {
        let kind: FileOperationKind
        let movedURL: URL
        let restoredURL: URL
    }

    let initialOperations: [FileOperationRecord]
    let loadWarning: String?

    var onOperationsChanged: (([FileOperationRecord]) -> Void)?
    var onRecoveryAttention: ((String) -> Void)?

    private let operationJournal: FileOperationJournal
    private let trashMover: (URL) throws -> URL
    private let fileOperationQueue = DispatchQueue(
        label: "com.covet.DesktopFolderWidget.file-operations",
        qos: .userInitiated
    )
    // Accessed only on fileOperationQueue. Makes overlapping watcher/UI requests idempotent.
    private var absorbedDestinations: [String: URL] = [:]

    init(
        directory: URL,
        trashMover: @escaping (URL) throws -> URL = FileOperationService.systemTrashItem
    ) {
        let journal = FileOperationJournal(directory: directory)
        self.operationJournal = journal
        self.trashMover = trashMover
        self.initialOperations = journal.operations
        self.loadWarning = journal.loadWarning
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

    static func systemTrashItem(at url: URL) throws -> URL {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        if let trashed = resulting as URL? {
            return trashed.standardizedFileURL
        }
        return defaultTrashPlaceholderURL(for: url)
    }

    static func defaultTrashPlaceholderURL(for url: URL) -> URL {
        let trashDirectory = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        return trashDirectory.appendingPathComponent(url.lastPathComponent).standardizedFileURL
    }

    static func canTrash(
        url: URL,
        storageURL: URL,
        appURL: URL = currentAppBundleURL
    ) -> Bool {
        let targetPath = canonicalPath(url)
        let storagePath = canonicalPath(storageURL)
        let appPath = canonicalPath(appURL)
        if isSameOrDescendant(appPath, of: targetPath) {
            return false
        }
        if isSameOrDescendant(storagePath, of: targetPath) {
            return false
        }
        return true
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
        storageURL: URL,
        kind: FileOperationKind = .manualAbsorb,
        completion: @escaping (AbsorbResult) -> Void
    ) {
        fileOperationQueue.async { [self] in
            let result = performJournaledAbsorb(urls: urls, storageURL: storageURL, kind: kind)
            publishOperations {
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
                publishOperations { completion(.failure(FileOperationError.sourceMissing)) }
                return
            }
            guard Self.canonicalPath(sourceURL) != Self.canonicalPath(destination) else {
                DispatchQueue.main.async { completion(.success(sourceURL)) }
                return
            }
            guard !fileManager.fileExists(atPath: destination.path) else {
                publishOperations { completion(.failure(FileOperationError.destinationExists)) }
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

                publishOperations {
                    completion(.success(destination))
                }
            } catch {
                publishOperations {
                    completion(.failure(error))
                }
            }
        }
    }

    func trashItem(
        at source: URL,
        storageURL: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        fileOperationQueue.async { [self] in
            let fileManager = FileManager.default
            let sourceURL = source.standardizedFileURL

            guard Self.canTrash(url: sourceURL, storageURL: storageURL) else {
                publishOperations { completion(.failure(FileOperationError.protectedLocation)) }
                return
            }
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                publishOperations { completion(.failure(FileOperationError.sourceMissing)) }
                return
            }

            let placeholderDestination = Self.defaultTrashPlaceholderURL(for: sourceURL)
            do {
                let operationID = try operationJournal.prepareMove(
                    kind: .trash,
                    source: sourceURL,
                    destination: placeholderDestination
                )

                let trashedURL: URL
                do {
                    trashedURL = try trashMover(sourceURL).standardizedFileURL
                } catch {
                    operationJournal.markFailed(operationID, error: error.localizedDescription)
                    throw error
                }

                do {
                    try operationJournal.markCompleted(operationID, destination: trashedURL)
                } catch {
                    operationJournal.markRecoveryPending(
                        operationID,
                        error: "文件已移到废纸篓，但操作记录尚未完成写入；下次启动会自动核对。\(error.localizedDescription)"
                    )
                    publishRecoveryAttention("文件已移到废纸篓，操作记录正在等待恢复核对")
                }

                publishOperations {
                    completion(.success(trashedURL))
                }
            } catch {
                publishOperations {
                    completion(.failure(error))
                }
            }
        }
    }

    func restoreOperation(
        _ id: UUID,
        completion: @escaping (Result<RestoreOutcome, Error>) -> Void
    ) {
        fileOperationQueue.async { [self] in
            let fileManager = FileManager.default
            guard let record = operationJournal.record(for: id), record.state == .completed else {
                DispatchQueue.main.async {
                    completion(.failure(FileOperationJournalError.operationNotRestorable))
                }
                return
            }

            let movedURL = record.destinationURL
            guard fileManager.fileExists(atPath: movedURL.path) else {
                let missingDetail = record.kind == .trash
                    ? "废纸篓中的文件已不存在，无法自动恢复"
                    : "收纳后的文件已不存在，无法自动恢复"
                operationJournal.markNeedsAttention(id, error: missingDetail)
                publishRecoveryAttention(
                    record.kind == .trash ? "废纸篓中的文件已不存在，无法自动恢复" : "有文件已不在收纳目录，无法自动恢复"
                )
                publishOperations {
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
                publishOperations {
                    completion(.failure(FileOperationError.fileIdentityChanged))
                }
                return
            }

            let originalURL = record.sourceURL
            let originalParent = originalURL.deletingLastPathComponent()
            guard fileManager.fileExists(atPath: originalParent.path) else {
                operationJournal.markRestoreFailed(id, error: "原目录已不存在，请先恢复原目录后重试")
                publishRecoveryAttention("原目录已不存在，恢复操作暂时无法完成")
                publishOperations {
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

                publishOperations {
                    completion(.success(RestoreOutcome(
                        kind: record.kind,
                        movedURL: movedURL,
                        restoredURL: restoreURL
                    )))
                }
            } catch {
                publishOperations {
                    completion(.failure(error))
                }
            }
        }
    }

    // Enqueue a completion after all previously submitted file operations.
    func drain(completion: @escaping () -> Void) {
        fileOperationQueue.async {
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func publishOperations(completion: @escaping () -> Void) {
        let snapshot = operationJournal.operations
        DispatchQueue.main.async { [weak self] in
            self?.onOperationsChanged?(snapshot)
            completion()
        }
    }

    private func publishRecoveryAttention(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onRecoveryAttention?(message)
        }
    }
}

enum FileOperationError: LocalizedError {
    case invalidName
    case sourceMissing
    case destinationExists
    case destinationMissing
    case fileIdentityChanged
    case originalFolderMissing
    case protectedLocation

    var errorDescription: String? {
        switch self {
        case .invalidName: return "文件名不能为空，也不能包含路径分隔符或保留名称"
        case .sourceMissing: return "原文件已不存在"
        case .destinationExists: return "目标位置已有同名文件，请换一个名称"
        case .destinationMissing: return "目标位置的文件已不存在，无法恢复"
        case .fileIdentityChanged: return "目标文件身份已变化，为避免误操作已停止恢复"
        case .originalFolderMissing: return "原目录已不存在，请先恢复原目录后重试"
        case .protectedLocation: return "不能将应用自身或文档整理目录移到废纸篓"
        }
    }
}
