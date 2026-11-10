import Foundation

@main
struct StoreTests {
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

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("dfw-tests-\(UUID().uuidString)", isDirectory: true)
        try! fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let report = root.appendingPathComponent("报告.pdf")
        let budget = root.appendingPathComponent("预算表.xlsx")
        let projectFolder = root.appendingPathComponent("项目资料")
        let missingFile = root.appendingPathComponent("不存在.txt")

        fileManager.createFile(atPath: report.path, contents: Data("x".utf8))
        fileManager.createFile(atPath: budget.path, contents: Data("x".utf8))
        try! fileManager.createDirectory(at: projectFolder, withIntermediateDirectories: true)

        let intakeExisting = root.appendingPathComponent("IntakeExisting.txt")
        let intakeNew = root.appendingPathComponent("IntakeNew.txt")
        let intakeTemporary = root.appendingPathComponent("IntakePartial.download")
        let intakeBatch = DesktopIntakeBatch.make(
            urls: [intakeExisting, intakeNew, intakeNew, intakeTemporary],
            existingPaths: [DesktopWatcher.pathKey(intakeExisting)]
        )
        expect(
            intakeBatch.candidates == [intakeNew],
            "desktop intake excludes existing, duplicate, and temporary paths"
        )
        expect(
            intakeBatch.handledPaths == [DesktopWatcher.pathKey(intakeExisting)],
            "duplicate candidate paths are not acknowledged before their move succeeds"
        )

        let store = PanelStore(config: .makeDefault(index: 0))

        store.add(urls: [report, budget, projectFolder])
        expect(store.config.items.count == 3, "add three items")
        expect(store.config.items.map(\.name).contains("项目资料"), "folder item added")

        store.add(urls: [report])
        expect(store.config.items.count == 3, "duplicate path ignored")

        store.searchText = "预算"
        expect(store.filteredItems.count == 1, "Chinese search filters")
        expect(store.filteredItems.first?.name == "预算表.xlsx", "Chinese search matches name")

        store.searchText = "pdf"
        expect(store.filteredItems.count == 1, "search is case insensitive")

        store.searchText = "   "
        expect(store.filteredItems.count == 3, "blank search returns all")

        store.searchText = ""
        let lastID = store.config.items[2].id
        store.move(id: lastID, toIndex: 0)
        expect(store.config.items.first?.id == lastID, "move item to first position")

        store.remove(id: lastID)
        expect(store.config.items.count == 2, "remove item")

        store.add(urls: [missingFile])
        expect(store.config.items.last?.exists == false, "missing file detected")
        store.removeMissing()
        expect(!store.config.items.contains(where: { $0.name == "不存在.txt" }), "missing file removed")

        let supportDir = root.appendingPathComponent("support", isDirectory: true)
        let persistence = Persistence(directory: supportDir)
        let appStore = AppStore(persistence: persistence)
        expect(appStore.panels.count == 1, "app store creates one default panel")

        appStore.panels[0].add(urls: [report, budget])
        appStore.saveNow()
        let loaded = persistence.load()
        expect(loaded?.count == 1, "panels persist")
        expect(loaded?.first?.items.count == 2, "items persist")
        expect(loaded?.first?.items.first?.name == "报告.pdf", "saved item name survives")

        let encoded = try! JSONEncoder().encode(store.config)
        let decoded = try! JSONDecoder().decode(PanelConfig.self, from: encoded)
        expect(decoded.id == store.config.id, "config id round-trips")
        expect(decoded.items.count == store.config.items.count, "config items round-trip")

        let legacyJSON = """
        {"id":"11111111-2222-3333-4444-555555555555","frame":{"x":10,"y":20,"width":390,"height":360},"items":[],"backgroundHex":"#1C1C1E","opacity":0.92,"columns":5,"levelMode":"desktop","isHidden":false,"cornerRadius":22}
        """
        var legacy = try! JSONDecoder().decode(PanelConfig.self, from: Data(legacyJSON.utf8))
        expect(!legacy.positionLocked, "legacy config defaults to unlocked")
        legacy.isLocked = true
        let lockedData = try! JSONEncoder().encode(legacy)
        let lockedDecoded = try! JSONDecoder().decode(PanelConfig.self, from: lockedData)
        expect(lockedDecoded.positionLocked, "position lock persists")

        let moveStore = PanelStore(config: .makeDefault(index: 0))
        moveStore.add(urls: [report, budget, projectFolder])
        let moveFirstID = moveStore.config.items[0].id
        moveStore.move(id: moveFirstID, toIndex: 2)
        expect(moveStore.config.items[2].id == moveFirstID, "move item to index")

        let firstDefault = PanelConfig.makeDefault(index: 0)
        let secondDefault = PanelConfig.makeDefault(index: 1)
        expect(firstDefault.frame != secondDefault.frame, "new panels cascade")

        appStore.newPanel()
        expect(appStore.panels.count == 2, "new panel appended")
        expect(appStore.canDeletePanel, "panel deletion allowed with two panels")
        appStore.removePanel(appStore.panels[1])
        expect(appStore.panels.count == 1, "panel removed")
        expect(!appStore.canDeletePanel, "last panel cannot be deleted")

        appStore.toggleAll()
        expect(appStore.allHidden, "toggle hides all panels")
        appStore.toggleAll()
        expect(!appStore.allHidden, "toggle shows all panels")

        let resizeStore = PanelStore(config: .makeDefault(index: 0))
        let oldTop = resizeStore.config.frame.y + resizeStore.config.frame.height
        resizeStore.resize(width: 480, height: 440)
        expect(resizeStore.config.frame.width == 480 && resizeStore.config.frame.height == 440, "resize sets requested size")
        let newTop = resizeStore.config.frame.y + resizeStore.config.frame.height
        expect(abs(newTop - oldTop) < 0.001, "resize keeps the top edge fixed")

        let absorbFixture = root.appendingPathComponent("AbsorbFixture", isDirectory: true)
        let storageFixture = root.appendingPathComponent("AbsorbStorage", isDirectory: true)
        try! fileManager.createDirectory(at: absorbFixture, withIntermediateDirectories: true)
        try! fileManager.createDirectory(at: storageFixture, withIntermediateDirectories: true)

        let appFolder = absorbFixture.appendingPathComponent("桌面文件整理组件", isDirectory: true)
        let fakeApp = appFolder.appendingPathComponent("build/文档整理.app", isDirectory: true)
        try! fileManager.createDirectory(at: fakeApp, withIntermediateDirectories: true)

        let appPath = FileOperationService.canonicalPath(fakeApp)
        let storagePath = FileOperationService.canonicalPath(storageFixture)
        expect(
            FileOperationService.absorbDisposition(
                for: appFolder,
                storagePath: storagePath,
                appPath: appPath
            ) == .reject,
            "absorb refuses a directory containing the application bundle"
        )
        expect(
            FileOperationService.absorbDisposition(
                for: fakeApp,
                storagePath: storagePath,
                appPath: appPath
            ) == .reject,
            "absorb refuses application bundles"
        )

        let alreadyStored = storageFixture.appendingPathComponent("已收纳.txt")
        fileManager.createFile(atPath: alreadyStored.path, contents: Data("stored".utf8))
        expect(
            FileOperationService.absorbDisposition(
                for: alreadyStored,
                storagePath: storagePath,
                appPath: appPath
            ) == .alreadyStored,
            "absorb acknowledges items already inside managed storage"
        )

        let storageAncestor = root.appendingPathComponent("StorageAncestor", isDirectory: true)
        let nestedStorage = storageAncestor.appendingPathComponent("Managed", isDirectory: true)
        try! fileManager.createDirectory(at: storageAncestor, withIntermediateDirectories: true)
        expect(
            FileOperationService.absorbDisposition(
                for: storageAncestor,
                storagePath: FileOperationService.canonicalPath(nestedStorage),
                appPath: appPath
            ) == .reject,
            "absorb refuses a directory that contains the storage directory"
        )

        let externalFile = absorbFixture.appendingPathComponent("普通桌面文件.txt")
        fileManager.createFile(atPath: externalFile.path, contents: Data("move".utf8))
        expect(
            FileOperationService.absorbDisposition(
                for: externalFile,
                storagePath: storagePath,
                appPath: appPath
            ) == .move,
            "absorb accepts an ordinary external file for the journaled move path"
        )

        let idempotentStorage = root.appendingPathComponent("IdempotentStorage", isDirectory: true)
        let idempotentSupport = root.appendingPathComponent("IdempotentSupport", isDirectory: true)
        let idempotentSource = root.appendingPathComponent("IdempotentSource.txt")
        fileManager.createFile(atPath: idempotentSource.path, contents: Data("same file".utf8))
        let idempotentStore = AppStore(
            persistence: Persistence(directory: idempotentSupport),
            storageDirectory: idempotentStorage
        )
        var firstAsyncResult: AppStore.AbsorbResult?
        idempotentStore.absorb(urls: [idempotentSource]) { firstAsyncResult = $0 }
        let firstDeadline = Date().addingTimeInterval(5)
        while firstAsyncResult == nil && Date() < firstDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(firstAsyncResult?.added.count == 1, "first asynchronous absorb succeeds")

        var secondAsyncResult: AppStore.AbsorbResult?
        idempotentStore.absorb(urls: [idempotentSource]) { secondAsyncResult = $0 }
        let secondDeadline = Date().addingTimeInterval(5)
        while secondAsyncResult == nil && Date() < secondDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(
            secondAsyncResult?.added.first == firstAsyncResult?.added.first,
            "repeated absorb resolves to the existing destination"
        )
        expect(
            secondAsyncResult?.failed.isEmpty == true,
            "repeated absorb does not report a false file-move failure"
        )

        let collisionStorage = root.appendingPathComponent("CollisionStorage", isDirectory: true)
        let collisionFolderA = root.appendingPathComponent("CollisionA", isDirectory: true)
        let collisionFolderB = root.appendingPathComponent("CollisionB", isDirectory: true)
        try! fileManager.createDirectory(at: collisionFolderA, withIntermediateDirectories: true)
        try! fileManager.createDirectory(at: collisionFolderB, withIntermediateDirectories: true)
        let collisionSourceA = collisionFolderA.appendingPathComponent("同名文件.txt")
        let collisionSourceB = collisionFolderB.appendingPathComponent("同名文件.txt")
        let collisionDirectory = collisionFolderA.appendingPathComponent("资料文件夹", isDirectory: true)
        try! fileManager.createDirectory(at: collisionDirectory, withIntermediateDirectories: true)
        fileManager.createFile(atPath: collisionSourceA.path, contents: Data("first".utf8))
        fileManager.createFile(atPath: collisionSourceB.path, contents: Data("second".utf8))
        fileManager.createFile(
            atPath: collisionDirectory.appendingPathComponent("子文件.txt").path,
            contents: Data("nested".utf8)
        )
        let collisionStore = AppStore(
            persistence: Persistence(directory: root.appendingPathComponent("CollisionSupport")),
            storageDirectory: collisionStorage
        )
        var collisionResult: AppStore.AbsorbResult?
        collisionStore.absorb(urls: [collisionSourceA, collisionSourceA, collisionSourceB, collisionDirectory]) { collisionResult = $0 }
        let collisionDeadline = Date().addingTimeInterval(5)
        while collisionResult == nil && Date() < collisionDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let collisionNames = Set(collisionResult?.added.map(\.lastPathComponent) ?? [])
        expect(collisionResult?.added.count == 3, "journaled absorb deduplicates repeated paths and moves files plus folders")
        expect(
            collisionNames.contains("同名文件.txt") && collisionNames.contains("同名文件 2.txt"),
            "journaled absorb resolves name collisions without overwriting"
        )
        expect(
            fileManager.fileExists(
                atPath: collisionStorage.appendingPathComponent("资料文件夹/子文件.txt").path
            ),
            "journaled absorb preserves folder contents when moving a directory"
        )

        var pendingAbsorbCallbackCompleted = false
        var fileOperationsDrained = false
        idempotentStore.absorb(urls: [idempotentSource]) { _ in
            pendingAbsorbCallbackCompleted = true
        }
        idempotentStore.drainFileOperations {
            fileOperationsDrained = true
        }
        let drainDeadline = Date().addingTimeInterval(5)
        while !fileOperationsDrained && Date() < drainDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(fileOperationsDrained, "file operation queue can be drained")
        expect(
            pendingAbsorbCallbackCompleted,
            "file operation callbacks complete before the drain callback"
        )

        let blockedStorageParent = root.appendingPathComponent("StorageBlocker")
        fileManager.createFile(atPath: blockedStorageParent.path, contents: Data("block".utf8))
        let blockedStorage = blockedStorageParent.appendingPathComponent("Managed", isDirectory: true)
        let recoverableSource = root.appendingPathComponent("可恢复收纳.txt")
        fileManager.createFile(atPath: recoverableSource.path, contents: Data("recover".utf8))
        let recoverableStore = AppStore(
            persistence: Persistence(directory: root.appendingPathComponent("RecoverableSupport")),
            storageDirectory: blockedStorage
        )
        var blockedResult: AppStore.AbsorbResult?
        recoverableStore.absorb(urls: [recoverableSource]) { blockedResult = $0 }
        let blockedDeadline = Date().addingTimeInterval(5)
        while blockedResult == nil && Date() < blockedDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(blockedResult?.failed.count == 1, "storage failure is returned as retryable")
        expect(fileManager.fileExists(atPath: recoverableSource.path), "source remains safe after storage failure")
        try! fileManager.removeItem(at: blockedStorageParent)

        var recoveredResult: AppStore.AbsorbResult?
        recoverableStore.absorb(urls: [recoverableSource]) { recoveredResult = $0 }
        let recoveredDeadline = Date().addingTimeInterval(5)
        while recoveredResult == nil && Date() < recoveredDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(recoveredResult?.resolved.count == 1, "automatic intake succeeds after storage recovers")
        expect(!fileManager.fileExists(atPath: recoverableSource.path), "recovered file moves into managed storage")

        // Write-ahead journal recovery: a move completed just before a crash is reconciled on launch.
        let corruptJournalDirectory = root.appendingPathComponent("CorruptJournal", isDirectory: true)
        try! fileManager.createDirectory(at: corruptJournalDirectory, withIntermediateDirectories: true)
        let corruptJournalFile = corruptJournalDirectory.appendingPathComponent("file-operations.json")
        try! Data("{not-json".utf8).write(to: corruptJournalFile)
        let corruptJournal = FileOperationJournal(directory: corruptJournalDirectory)
        expect(corruptJournal.loadWarning != nil, "corrupt operation journal is surfaced as a recovery warning")
        expect(
            (try? fileManager.contentsOfDirectory(atPath: corruptJournalDirectory.path))?.contains(where: { $0.hasPrefix("file-operations.corrupt-") }) == true,
            "corrupt operation journal is preserved as a backup"
        )

        let journalDirectory = root.appendingPathComponent("JournalRecovery", isDirectory: true)
        let crashSource = root.appendingPathComponent("崩溃前原文件.txt")
        let crashDestination = root.appendingPathComponent("JournalRecovery/崩溃前原文件.txt")
        fileManager.createFile(atPath: crashSource.path, contents: Data("journal".utf8))
        let journalBeforeCrash = FileOperationJournal(directory: journalDirectory)
        let crashOperationID = try! journalBeforeCrash.prepareMove(
            kind: .automaticAbsorb,
            source: crashSource,
            destination: crashDestination
        )
        try! fileManager.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        try! fileManager.moveItem(at: crashSource, to: crashDestination)
        let journalAfterCrash = FileOperationJournal(directory: journalDirectory)
        expect(
            journalAfterCrash.record(for: crashOperationID)?.state == .completed,
            "startup reconciles a move completed before a crash"
        )

        // A prepared record with the source still present means the move never happened.
        let interruptedSource = root.appendingPathComponent("中断但未移动.txt")
        let interruptedDestination = journalDirectory.appendingPathComponent("中断但未移动.txt")
        fileManager.createFile(atPath: interruptedSource.path, contents: Data("safe".utf8))
        let interruptedID = try! journalAfterCrash.prepareMove(
            kind: .manualAbsorb,
            source: interruptedSource,
            destination: interruptedDestination
        )
        let journalAfterUnmovedCrash = FileOperationJournal(directory: journalDirectory)
        expect(
            journalAfterUnmovedCrash.record(for: interruptedID)?.state == .failed,
            "startup marks an interrupted pre-move operation without moving the source"
        )
        expect(fileManager.fileExists(atPath: interruptedSource.path), "crash recovery keeps the original file safe")

        // A restore interrupted after the physical move is also reconciled.
        let restoreTarget = root.appendingPathComponent("崩溃后已恢复.txt")
        try! journalAfterCrash.beginRestore(crashOperationID, to: restoreTarget)
        try! fileManager.moveItem(at: crashDestination, to: restoreTarget)
        let journalAfterRestoreCrash = FileOperationJournal(directory: journalDirectory)
        expect(
            journalAfterRestoreCrash.record(for: crashOperationID)?.state == .restored,
            "startup reconciles a restore completed before a crash"
        )
        expect(fileManager.fileExists(atPath: restoreTarget.path), "crash recovery leaves restored file in place")

        // Ambiguous crash state must be surfaced instead of guessing or overwriting either file.
        let ambiguousSource = root.appendingPathComponent("歧义原文件.txt")
        let ambiguousDestination = journalDirectory.appendingPathComponent("歧义原文件.txt")
        fileManager.createFile(atPath: ambiguousSource.path, contents: Data("source".utf8))
        let ambiguousID = try! journalAfterRestoreCrash.prepareMove(
            kind: .manualAbsorb,
            source: ambiguousSource,
            destination: ambiguousDestination
        )
        fileManager.createFile(atPath: ambiguousDestination.path, contents: Data("destination".utf8))
        let journalAfterAmbiguousCrash = FileOperationJournal(directory: journalDirectory)
        expect(
            journalAfterAmbiguousCrash.record(for: ambiguousID)?.state == .needsAttention,
            "startup flags an ambiguous crash state for manual inspection"
        )
        expect(
            String(data: (try? Data(contentsOf: ambiguousSource)) ?? Data(), encoding: .utf8) == "source",
            "ambiguous recovery preserves the original source"
        )
        expect(
            String(data: (try? Data(contentsOf: ambiguousDestination)) ?? Data(), encoding: .utf8) == "destination",
            "ambiguous recovery preserves the destination without overwriting"
        )

        // End-to-end undo updates every panel reference, then a physical rename is journaled too.
        let undoDesktop = root.appendingPathComponent("UndoDesktop", isDirectory: true)
        let undoStorage = root.appendingPathComponent("UndoStorage", isDirectory: true)
        try! fileManager.createDirectory(at: undoDesktop, withIntermediateDirectories: true)
        let undoSource = undoDesktop.appendingPathComponent("待恢复.txt")
        fileManager.createFile(atPath: undoSource.path, contents: Data("undo".utf8))
        let undoStore = AppStore(
            persistence: Persistence(directory: root.appendingPathComponent("UndoSupport")),
            storageDirectory: undoStorage
        )
        undoStore.newPanel()
        undoStore.updateAutoAbsorbStatus(
            phase: .retrying,
            pendingCount: 2,
            message: "两个项目等待重试"
        )
        expect(
            undoStore.autoAbsorbStatus.phase == .retrying && undoStore.autoAbsorbStatus.pendingCount == 2,
            "automatic intake status exposes pending failures to the UI"
        )
        var undoAbsorbResult: AppStore.AbsorbResult?
        undoStore.absorb(urls: [undoSource], kind: .automaticAbsorb) { undoAbsorbResult = $0 }
        let undoAbsorbDeadline = Date().addingTimeInterval(5)
        while undoAbsorbResult == nil && Date() < undoAbsorbDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let undoDestination = undoAbsorbResult?.added.first
        let undoOperationID = undoAbsorbResult?.operationIDs.first
        expect(undoDestination != nil && undoOperationID != nil, "automatic absorb creates a reversible journal entry")
        if let undoDestination, let undoOperationID {
            undoStore.panels[0].add(urls: [undoDestination])
            undoStore.panels[1].add(urls: [undoDestination])
            var renameResult: Result<URL, Error>?
            undoStore.renameItem(at: undoDestination, to: "重命名后.txt") { renameResult = $0 }
            let renameDeadline = Date().addingTimeInterval(5)
            while renameResult == nil && Date() < renameDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            let renamedURL = try? renameResult?.get()
            expect(renamedURL?.lastPathComponent == "重命名后.txt", "rename physically moves the file and returns the new path")
            expect(
                undoStore.panels[0].config.items.first?.path == renamedURL?.path
                    && undoStore.panels[1].config.items.first?.path == renamedURL?.path,
                "rename updates references in every panel"
            )
            let renameOperation = undoStore.fileOperations.first { $0.kind == .rename }
            var renameRestoreResult: Result<URL, Error>?
            if let renameOperation {
                undoStore.restoreOperation(renameOperation.id) { renameRestoreResult = $0 }
            }
            let renameRestoreDeadline = Date().addingTimeInterval(5)
            while renameRestoreResult == nil && Date() < renameRestoreDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            expect(
                (try? renameRestoreResult?.get().lastPathComponent) == undoDestination.lastPathComponent,
                "undo rename restores the previous filename"
            )
            expect(
                undoStore.panels[0].config.items.first?.path == undoDestination.path
                    && undoStore.panels[1].config.items.first?.path == undoDestination.path,
                "undo rename updates references in every panel"
            )

            var undoResult: Result<URL, Error>?
            undoStore.restoreOperation(undoOperationID) { undoResult = $0 }
            let undoDeadline = Date().addingTimeInterval(5)
            while undoResult == nil && Date() < undoDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            expect((try? undoResult?.get())?.path == undoSource.path, "undo automatic absorb restores the original location")
            expect(fileManager.fileExists(atPath: undoSource.path), "undo restores the original file")
            expect(
                undoStore.panels[0].config.items.first?.path == undoSource.path
                    && undoStore.panels[1].config.items.first?.path == undoSource.path,
                "undo updates references in every panel to the restored path"
            )
            expect(
                undoStore.fileOperations.first(where: { $0.id == undoOperationID })?.state == .restored,
                "undo is recorded as restored in the operation history"
            )
        }

        // A replacement file at the old destination path must not be mistaken for the moved file.
        let identitySource = undoDesktop.appendingPathComponent("身份校验.txt")
        fileManager.createFile(atPath: identitySource.path, contents: Data("original".utf8))
        var identityAbsorbResult: AppStore.AbsorbResult?
        undoStore.absorb(urls: [identitySource]) { identityAbsorbResult = $0 }
        let identityAbsorbDeadline = Date().addingTimeInterval(5)
        while identityAbsorbResult == nil && Date() < identityAbsorbDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        if let identityID = identityAbsorbResult?.operationIDs.first,
           let identityDestination = identityAbsorbResult?.added.first {
            try! fileManager.removeItem(at: identityDestination)
            fileManager.createFile(atPath: identityDestination.path, contents: Data("replacement".utf8))
            var identityRestoreResult: Result<URL, Error>?
            undoStore.restoreOperation(identityID) { identityRestoreResult = $0 }
            let identityRestoreDeadline = Date().addingTimeInterval(5)
            while identityRestoreResult == nil && Date() < identityRestoreDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            expect({ if case .failure? = identityRestoreResult { return true }; return false }(), "restore refuses a replacement file with a different identity")
            expect(
                undoStore.fileOperations.first(where: { $0.id == identityID })?.state == .needsAttention,
                "identity mismatch is recorded for manual inspection"
            )
            expect(
                String(data: (try? Data(contentsOf: identityDestination)) ?? Data(), encoding: .utf8) == "replacement",
                "identity mismatch leaves the replacement file untouched"
            )
        }

        // Restore must never overwrite a file created at the original path after the absorb.
        let conflictSource = undoDesktop.appendingPathComponent("恢复冲突.txt")
        fileManager.createFile(atPath: conflictSource.path, contents: Data("first".utf8))
        var conflictAbsorbResult: AppStore.AbsorbResult?
        undoStore.absorb(urls: [conflictSource]) { conflictAbsorbResult = $0 }
        let conflictAbsorbDeadline = Date().addingTimeInterval(5)
        while conflictAbsorbResult == nil && Date() < conflictAbsorbDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        if let conflictID = conflictAbsorbResult?.operationIDs.first {
            fileManager.createFile(atPath: conflictSource.path, contents: Data("keep-existing".utf8))
            var conflictRestoreResult: Result<URL, Error>?
            undoStore.restoreOperation(conflictID) { conflictRestoreResult = $0 }
            let conflictRestoreDeadline = Date().addingTimeInterval(5)
            while conflictRestoreResult == nil && Date() < conflictRestoreDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            let restoredCopy = try? conflictRestoreResult?.get()
            expect(restoredCopy?.lastPathComponent.contains("恢复副本") == true, "restore uses a recovery-copy name when the original path is occupied")
            expect(
                String(data: (try? Data(contentsOf: conflictSource)) ?? Data(), encoding: .utf8) == "keep-existing",
                "restore never overwrites a file already at the original path"
            )
        }

        let watchDesktop = root.appendingPathComponent("WatchDesktop", isDirectory: true)
        try! fileManager.createDirectory(at: watchDesktop, withIntermediateDirectories: true)
        let preexisting = watchDesktop.appendingPathComponent("已有文件.txt")
        fileManager.createFile(atPath: preexisting.path, contents: Data("x".utf8))
        var watched: [URL] = []
        let watcher = DesktopWatcher(desktopURL: watchDesktop) { urls, finish in
            watched.append(contentsOf: urls)
            finish(Set(urls.map(DesktopWatcher.pathKey)))
        }
        expect(
            watcher.initialItems.contains {
                $0.standardizedFileURL.path == preexisting.standardizedFileURL.path
            },
            "watcher snapshots existing files"
        )

        let startupDeadline = Date().addingTimeInterval(6)
        while !watched.contains(where: { $0.lastPathComponent == "已有文件.txt" }),
              Date() < startupDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(
            watched.contains { $0.lastPathComponent == "已有文件.txt" },
            "watcher automatically submits pre-existing desktop items after stability checks"
        )

        let userRestoredFile = watchDesktop.appendingPathComponent("用户主动恢复.txt")
        fileManager.createFile(atPath: userRestoredFile.path, contents: Data("restored".utf8))
        watcher.markHandled(userRestoredFile)
        let restoredQuietDeadline = Date().addingTimeInterval(2.2)
        while Date() < restoredQuietDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(
            !watched.contains { $0.lastPathComponent == "用户主动恢复.txt" },
            "automatic watcher does not immediately re-absorb a file restored by the user"
        )

        let partialDownload = watchDesktop.appendingPathComponent("下载中.download")
        fileManager.createFile(atPath: partialDownload.path, contents: Data("x".utf8))
        let partialDeadline = Date().addingTimeInterval(2.5)
        while Date() < partialDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(
            !watched.contains { $0.lastPathComponent == "下载中.download" },
            "watcher ignores in-progress downloads"
        )

        let growingFile = watchDesktop.appendingPathComponent("正在写入但没有临时后缀.txt")
        fileManager.createFile(atPath: growingFile.path, contents: Data("part".utf8))
        let firstWriteDeadline = Date().addingTimeInterval(1.8)
        while Date() < firstWriteDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        try! Data("completed-content".utf8).write(to: growingFile)
        let postWriteDeadline = Date().addingTimeInterval(1.2)
        while Date() < postWriteDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(
            !watched.contains { $0.lastPathComponent == "正在写入但没有临时后缀.txt" },
            "watcher resets stability checks when a file changes during observation"
        )
        let growingStableDeadline = Date().addingTimeInterval(5)
        while !watched.contains(where: { $0.lastPathComponent == "正在写入但没有临时后缀.txt" }),
              Date() < growingStableDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(
            watched.contains { $0.lastPathComponent == "正在写入但没有临时后缀.txt" },
            "watcher eventually accepts the file after writing stops"
        )

        let finishedDownload = watchDesktop.appendingPathComponent("下载完成.txt")
        fileManager.createFile(atPath: finishedDownload.path, contents: Data("x".utf8))
        let finishedDeadline = Date().addingTimeInterval(6)
        while !watched.contains(where: { $0.lastPathComponent == "下载完成.txt" }),
              Date() < finishedDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(
            watched.contains { $0.lastPathComponent == "下载完成.txt" },
            "watcher reports a newly created stable file"
        )

        let firstDetectionCount = watched.filter {
            $0.lastPathComponent == "下载完成.txt"
        }.count
        let stableWaitDeadline = Date().addingTimeInterval(2.2)
        while Date() < stableWaitDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(
            watched.filter({ $0.lastPathComponent == "下载完成.txt" }).count == firstDetectionCount,
            "successfully acknowledged files are not repeatedly submitted"
        )

        try! fileManager.removeItem(at: finishedDownload)
        let removalDeadline = Date().addingTimeInterval(2.2)
        while Date() < removalDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        fileManager.createFile(atPath: finishedDownload.path, contents: Data("recreated".utf8))
        let recreationDeadline = Date().addingTimeInterval(6)
        while watched.filter({ $0.lastPathComponent == "下载完成.txt" }).count <= firstDetectionCount,
              Date() < recreationDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(
            watched.filter({ $0.lastPathComponent == "下载完成.txt" }).count == firstDetectionCount + 1,
            "watcher detects a file recreated at a previously used path"
        )

        let rapidReplacement = watchDesktop.appendingPathComponent("快速替换.txt")
        fileManager.createFile(atPath: rapidReplacement.path, contents: Data("old".utf8))
        let firstReplacementDeadline = Date().addingTimeInterval(6)
        while watched.filter({ $0.lastPathComponent == "快速替换.txt" }).isEmpty,
              Date() < firstReplacementDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let firstReplacementCount = watched.filter {
            $0.lastPathComponent == "快速替换.txt"
        }.count
        try! fileManager.removeItem(at: rapidReplacement)
        fileManager.createFile(atPath: rapidReplacement.path, contents: Data("new-content".utf8))
        let secondReplacementDeadline = Date().addingTimeInterval(6)
        while watched.filter({ $0.lastPathComponent == "快速替换.txt" }).count <= firstReplacementCount,
              Date() < secondReplacementDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(
            watched.filter({ $0.lastPathComponent == "快速替换.txt" }).count == firstReplacementCount + 1,
            "watcher detects same-path replacement even without an intervening scan"
        )
        watcher.stop()

        let retryDesktop = root.appendingPathComponent("RetryDesktop", isDirectory: true)
        try! fileManager.createDirectory(at: retryDesktop, withIntermediateDirectories: true)
        let retryFile = retryDesktop.appendingPathComponent("暂时不可移动.txt")
        fileManager.createFile(atPath: retryFile.path, contents: Data("retry".utf8))
        var retryAttempts = 0
        let retryWatcher = DesktopWatcher(desktopURL: retryDesktop) { urls, finish in
            retryAttempts += 1
            if retryAttempts == 1 {
                finish([])
            } else {
                finish(Set(urls.map(DesktopWatcher.pathKey)))
            }
        }
        let retryDeadline = Date().addingTimeInterval(10)
        let firstRetryWaitDeadline = Date().addingTimeInterval(4.0)
        while retryAttempts == 0 && Date() < firstRetryWaitDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(retryAttempts == 1, "watcher starts one intake attempt for a stable file")
        let backoffWaitDeadline = Date().addingTimeInterval(1.2)
        while Date() < backoffWaitDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(retryAttempts == 1, "watcher respects the retry backoff interval")
        while retryAttempts < 2 && Date() < retryDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(retryAttempts >= 2, "watcher retries an item after a transient intake failure")
        let noDuplicateDeadline = Date().addingTimeInterval(2.2)
        while Date() < noDuplicateDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(retryAttempts == 2, "watcher stops retrying after successful acknowledgement")
        retryWatcher.stop()

        let lateDesktop = root.appendingPathComponent("LateDesktop", isDirectory: true)
        var lateItemDetected = false
        let lateWatcher = DesktopWatcher(desktopURL: lateDesktop) { urls, finish in
            lateItemDetected = urls.contains { $0.lastPathComponent == "延迟创建桌面中的文件.txt" }
            finish(Set(urls.map(DesktopWatcher.pathKey)))
        }
        expect(lateWatcher.initialItems.isEmpty, "watcher can start before the desktop directory is readable")
        try! fileManager.createDirectory(at: lateDesktop, withIntermediateDirectories: true)
        let lateFile = lateDesktop.appendingPathComponent("延迟创建桌面中的文件.txt")
        fileManager.createFile(atPath: lateFile.path, contents: Data("late".utf8))
        let lateDeadline = Date().addingTimeInterval(8)
        while !lateItemDetected && Date() < lateDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(lateItemDetected, "watcher recovers when desktop access becomes available")
        lateWatcher.stop()

        print("")
        if failures == 0 {
            print("ALL TESTS PASSED")
            exit(0)
        } else {
            print("\(failures) FAILURES")
            exit(1)
        }
    }
}
