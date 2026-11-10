import Foundation

enum FileOperationKind: String, Codable, CaseIterable {
    case automaticAbsorb
    case manualAbsorb
    case rename

    var title: String {
        switch self {
        case .automaticAbsorb: return "自动收纳"
        case .manualAbsorb: return "手动收纳"
        case .rename: return "重命名"
        }
    }
}

enum FileOperationState: String, Codable, CaseIterable {
    case prepared
    case completed
    case restoring
    case restored
    case needsAttention
    case failed

    var title: String {
        switch self {
        case .prepared: return "处理中断，正在核对"
        case .completed: return "已完成，可恢复"
        case .restoring: return "正在恢复"
        case .restored: return "已恢复"
        case .needsAttention: return "需要检查"
        case .failed: return "未完成"
        }
    }
}

struct FileOperationRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: FileOperationKind
    var state: FileOperationState
    var sourcePath: String
    var destinationPath: String
    var restorePath: String?
    var restoredPath: String?
    var fileResourceIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    var errorMessage: String?

    var fileName: String {
        URL(fileURLWithPath: destinationPath).lastPathComponent
    }

    var canRestore: Bool {
        state == .completed
    }

    var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
    var destinationURL: URL { URL(fileURLWithPath: destinationPath) }
}

private struct FileOperationJournalState: Codable {
    var version: Int
    var operations: [FileOperationRecord]
}

final class FileOperationJournal {
    private let directory: URL
    private let fileURL: URL
    private let fileManager = FileManager.default

    private(set) var operations: [FileOperationRecord] = []
    private(set) var loadWarning: String?

    init(directory: URL) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("file-operations.json")
        load()
        recoverInterruptedOperations()
    }

    @discardableResult
    func prepareMove(
        kind: FileOperationKind,
        source: URL,
        destination: URL
    ) throws -> UUID {
        let record = FileOperationRecord(
            id: UUID(),
            kind: kind,
            state: .prepared,
            sourcePath: source.standardizedFileURL.path,
            destinationPath: destination.standardizedFileURL.path,
            restorePath: nil,
            restoredPath: nil,
            fileResourceIdentifier: nil,
            createdAt: Date(),
            updatedAt: Date(),
            errorMessage: nil
        )
        operations.append(record)
        do {
            try persist()
            return record.id
        } catch {
            operations.removeAll { $0.id == record.id }
            throw error
        }
    }

    func markCompleted(_ id: UUID) throws {
        try update(id) { record in
            record.state = .completed
            record.fileResourceIdentifier = Self.resourceIdentifier(at: record.destinationURL)
            record.updatedAt = Date()
            record.errorMessage = nil
        }
    }

    // Keep the write-ahead state recoverable if the filesystem move succeeded but
    // the final journal commit could not be persisted.
    func markRecoveryPending(_ id: UUID, error: String) {
        do {
            try update(id) { record in
                record.updatedAt = Date()
                record.errorMessage = error
            }
        } catch {
            NSLog("DesktopFolderWidget: failed to persist pending recovery note: \(error)")
        }
    }

    func markFailed(_ id: UUID, error: String) {
        do {
            try update(id) { record in
                record.state = .failed
                record.updatedAt = Date()
                record.errorMessage = error
            }
        } catch {
            NSLog("DesktopFolderWidget: failed to persist file operation failure: \(error)")
        }
    }

    func beginRestore(_ id: UUID, to destination: URL) throws {
        try update(id) { record in
            guard record.state == .completed else {
                throw FileOperationJournalError.operationNotRestorable
            }
            record.state = .restoring
            record.restorePath = destination.standardizedFileURL.path
            record.updatedAt = Date()
            record.errorMessage = nil
        }
    }

    func markRestored(_ id: UUID, at url: URL) throws {
        try update(id) { record in
            record.state = .restored
            record.restoredPath = url.standardizedFileURL.path
            record.restorePath = nil
            record.updatedAt = Date()
            record.errorMessage = nil
        }
    }

    func markRestoreFailed(_ id: UUID, error: String) {
        do {
            try update(id) { record in
                record.state = .completed
                record.restorePath = nil
                record.updatedAt = Date()
                record.errorMessage = error
            }
        } catch {
            NSLog("DesktopFolderWidget: failed to persist restore failure: \(error)")
        }
    }

    func markNeedsAttention(_ id: UUID, error: String) {
        do {
            try update(id) { record in
                record.state = .needsAttention
                record.updatedAt = Date()
                record.errorMessage = error
            }
        } catch {
            NSLog("DesktopFolderWidget: failed to persist recovery warning: \(error)")
        }
    }

    func record(for id: UUID) -> FileOperationRecord? {
        operations.first { $0.id == id }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            operations = try decoder.decode(FileOperationJournalState.self, from: data).operations
        } catch {
            NSLog("DesktopFolderWidget: operation journal load failed: \(error)")
            loadWarning = "操作记录文件损坏，已备份原文件；请检查文档整理目录中的文件"
            let backup = directory.appendingPathComponent(
                "file-operations.corrupt-\(Int(Date().timeIntervalSince1970)).json"
            )
            try? data.write(to: backup, options: .atomic)
            operations = []
        }
    }

    private func recoverInterruptedOperations() {
        var changed = false

        for index in operations.indices {
            let state = operations[index].state
            let sourceExists = fileManager.fileExists(atPath: operations[index].sourcePath)
            let destinationExists = fileManager.fileExists(atPath: operations[index].destinationPath)

            switch state {
            case .prepared:
                if !sourceExists && destinationExists {
                    operations[index].state = .completed
                    operations[index].fileResourceIdentifier = Self.resourceIdentifier(
                        at: operations[index].destinationURL
                    )
                    operations[index].errorMessage = "应用上次退出时移动已完成，已自动补全操作记录"
                } else if sourceExists && !destinationExists {
                    operations[index].state = .failed
                    operations[index].errorMessage = "应用上次退出时尚未移动文件，原文件仍在原位置"
                } else {
                    operations[index].state = .needsAttention
                    operations[index].errorMessage = "无法仅凭文件路径判断上次操作结果，请检查原位置和目标位置"
                }
                operations[index].updatedAt = Date()
                changed = true

            case .restoring:
                let restorePath = operations[index].restorePath
                let restoreExists = restorePath.map { fileManager.fileExists(atPath: $0) } ?? false
                if restoreExists && !destinationExists, let restorePath {
                    operations[index].state = .restored
                    operations[index].restoredPath = restorePath
                    operations[index].restorePath = nil
                    operations[index].errorMessage = "应用上次退出时恢复已完成，已自动补全操作记录"
                } else if destinationExists && !restoreExists {
                    operations[index].state = .completed
                    operations[index].restorePath = nil
                    operations[index].errorMessage = "上次恢复未执行完成，文件仍保留在收纳目录"
                } else {
                    operations[index].state = .needsAttention
                    operations[index].errorMessage = "恢复操作中断且文件位置不唯一，请人工检查，应用不会覆盖文件"
                }
                operations[index].updatedAt = Date()
                changed = true

            case .completed, .restored, .needsAttention, .failed:
                break
            }
        }

        if changed {
            do {
                try persist()
            } catch {
                NSLog("DesktopFolderWidget: failed to persist crash recovery: \(error)")
            }
        }
    }

    private func update(
        _ id: UUID,
        mutation: (inout FileOperationRecord) throws -> Void
    ) throws {
        guard let index = operations.firstIndex(where: { $0.id == id }) else {
            throw FileOperationJournalError.operationNotFound
        }
        let previous = operations[index]
        try mutation(&operations[index])
        do {
            try persist()
        } catch {
            operations[index] = previous
            throw error
        }
    }

    private func persist() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(FileOperationJournalState(version: 1, operations: operations))
        try data.write(to: fileURL, options: .atomic)
    }

    static func resourceIdentifier(at url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
              let identifier = values.fileResourceIdentifier
        else { return nil }
        if let data = identifier as? Data {
            return data.base64EncodedString()
        }
        return String(describing: identifier)
    }
}

enum FileOperationJournalError: LocalizedError {
    case operationNotFound
    case operationNotRestorable

    var errorDescription: String? {
        switch self {
        case .operationNotFound: return "找不到对应的文件操作记录"
        case .operationNotRestorable: return "该操作当前不能恢复"
        }
    }
}
