import Foundation

@main
struct FileOperationServiceTests {
    static func main() {
        var failures = 0
        func expect(_ condition: Bool, _ message: String) {
            if condition {
                print("PASS  \(message)")
            } else {
                print("FAIL  \(message)")
                failures += 1
            }
        }

        func waitUntil(
            timeout: TimeInterval = 5,
            condition: () -> Bool
        ) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition() && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            return condition()
        }

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("file-operation-service-tests-\(UUID().uuidString)", isDirectory: true)
        try! fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        let storage = root.appendingPathComponent("Managed", isDirectory: true)
        let journalDirectory = root.appendingPathComponent("Support", isDirectory: true)
        try! fileManager.createDirectory(at: desktop, withIntermediateDirectories: true)

        let source = desktop.appendingPathComponent("收纳测试.txt")
        try! Data("service-owned move".utf8).write(to: source)

        let service = FileOperationService(directory: journalDirectory)
        var latestOperations: [FileOperationRecord] = []
        service.onOperationsChanged = { latestOperations = $0 }

        var absorbResult: FileOperationService.AbsorbResult?
        service.absorb(urls: [source], storageURL: storage) { absorbResult = $0 }
        expect(waitUntil { absorbResult != nil }, "service completes an asynchronous absorb")
        let movedURL = absorbResult?.added.first
        expect(
            movedURL.map { fileManager.fileExists(atPath: $0.path) } == true
                && !fileManager.fileExists(atPath: source.path),
            "service moves the file without AppStore mediation"
        )
        let absorbRecord = latestOperations.first { $0.kind == .manualAbsorb && $0.state == .completed }
        expect(absorbRecord != nil, "service records the completed move in its journal")

        if let operationID = absorbRecord?.id {
            var restoreResult: Result<FileOperationService.RestoreOutcome, Error>?
            service.restoreOperation(operationID) { restoreResult = $0 }
            expect(waitUntil { restoreResult != nil }, "service completes an asynchronous restore")
            if case .success(let outcome) = restoreResult {
                expect(
                    outcome.restoredURL == source
                        && fileManager.fileExists(atPath: source.path)
                        && movedURL.map { !fileManager.fileExists(atPath: $0.path) } == true,
                    "service restores the original file and updates its journal"
                )
            } else {
                expect(false, "service restores the original file and updates its journal")
            }
        } else {
            expect(false, "service restores the original file and updates its journal")
        }

        let renameSource = desktop.appendingPathComponent("重命名前.txt")
        try! Data("rename".utf8).write(to: renameSource)
        var renameResult: Result<URL, Error>?
        service.renameItem(at: renameSource, to: "重命名后.txt") { renameResult = $0 }
        expect(waitUntil { renameResult != nil }, "service completes a journaled rename")
        var renamedURL: URL?
        if case .success(let url) = renameResult {
            renamedURL = url
        }
        expect(
            renamedURL.map { fileManager.fileExists(atPath: $0.path) } == true
                && !fileManager.fileExists(atPath: renameSource.path),
            "rename is performed by the service without UI-state dependencies"
        )
        let renameRecord = latestOperations.first { $0.kind == .rename && $0.state == .completed }
        expect(renameRecord != nil, "rename is independently journaled")

        if let operationID = renameRecord?.id {
            var undoResult: Result<FileOperationService.RestoreOutcome, Error>?
            service.restoreOperation(operationID) { undoResult = $0 }
            expect(waitUntil { undoResult != nil }, "service can undo a rename from its journal")
            if case .success(let outcome) = undoResult {
                expect(
                    outcome.restoredURL == renameSource
                        && fileManager.fileExists(atPath: renameSource.path),
                    "undoing rename returns the file to its original path"
                )
            } else {
                expect(false, "undoing rename returns the file to its original path")
            }
        } else {
            expect(false, "undoing rename returns the file to its original path")
        }

        let blocker = root.appendingPathComponent("storage-blocker")
        try! Data("not a directory".utf8).write(to: blocker)
        let failedSource = desktop.appendingPathComponent("保留原件.txt")
        try! Data("must remain".utf8).write(to: failedSource)
        let failingService = FileOperationService(
            directory: root.appendingPathComponent("FailureSupport", isDirectory: true)
        )
        var failedAbsorb: FileOperationService.AbsorbResult?
        failingService.absorb(
            urls: [failedSource],
            storageURL: blocker.appendingPathComponent("Managed", isDirectory: true)
        ) { failedAbsorb = $0 }
        expect(waitUntil { failedAbsorb != nil }, "service reports a storage failure")
        expect(
            failedAbsorb?.failed == [failedSource]
                && fileManager.fileExists(atPath: failedSource.path),
            "failed storage operation leaves the original file untouched"
        )

        print(failures == 0 ? "ALL FILE OPERATION SERVICE TESTS PASSED" : "\(failures) FILE OPERATION SERVICE TEST(S) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
