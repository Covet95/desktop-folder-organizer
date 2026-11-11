import Darwin
import Foundation

struct DesktopIntakeBatch {
    let candidates: [URL]
    let handledPaths: Set<String>

    static func make(urls: [URL], existingPaths: Set<String>) -> DesktopIntakeBatch {
        var handledPaths = Set<String>()
        var seenPaths = Set<String>()
        var candidates: [URL] = []

        for url in urls {
            let path = DesktopWatcher.pathKey(url)
            guard !DesktopWatcher.isTemporary(url) else { continue }

            if existingPaths.contains(path) {
                handledPaths.insert(path)
                continue
            }

            // A duplicate candidate must not be marked handled: its first attempt may fail
            // and still needs to remain eligible for DesktopWatcher's retry path.
            guard seenPaths.insert(path).inserted else { continue }
            candidates.append(url)
        }

        return DesktopIntakeBatch(candidates: candidates, handledPaths: handledPaths)
    }
}

final class DesktopIntakeCoordinator {
    private let appStore: AppStore
    private let desktopURL: URL?
    private var watcher: DesktopWatcher?
    private var storageMonitor: DispatchSourceFileSystemObject?

    init(
        appStore: AppStore,
        desktopURL: URL? = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    ) {
        self.appStore = appStore
        self.desktopURL = desktopURL
    }

    func start() {
        guard watcher == nil else { return }
        startStorageMonitoring()
        guard let desktopURL else {
            appStore.updateAutoAbsorbStatus(
                phase: .attention,
                message: "无法定位桌面目录，自动收纳未启动"
            )
            return
        }

        if appStore.autoAbsorbStatus.phase != .attention {
            appStore.updateAutoAbsorbStatus(phase: .monitoring, message: "自动收纳已开启，等待桌面文件变化")
        }
        if let warning = appStore.fileOperations.first(where: { $0.state == .needsAttention })?.errorMessage {
            let count = appStore.fileOperations.filter { $0.state == .needsAttention }.count
            appStore.updateAutoAbsorbStatus(
                phase: .attention,
                pendingCount: count,
                message: "有 \(count) 条文件操作需要检查：\(warning)"
            )
        }

        appStore.onFileRestored = { [weak self] url in
            self?.watcher?.markHandled(url)
        }

        watcher = DesktopWatcher(desktopURL: desktopURL) { [weak self] urls, finish in
            guard let self else {
                finish([])
                return
            }
            self.absorbDesktopItems(urls, completion: finish)
        }
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        storageMonitor?.cancel()
        storageMonitor = nil
        appStore.onFileRestored = nil
    }

    private func startStorageMonitoring() {
        guard storageMonitor == nil else { return }
        let directory = appStore.storageDirectory

        // Do not recreate a missing managed folder and erase its saved panel references.
        if !FileManager.default.fileExists(atPath: directory.path),
           appStore.panels.first?.config.items.contains(where: {
               URL(fileURLWithPath: $0.path).standardizedFileURL
                   .deletingLastPathComponent().path == directory.standardizedFileURL.path
           }) == true {
            appStore.updateAutoAbsorbStatus(
                phase: .attention,
                message: "原收纳目录不存在，请先恢复目录位置"
            )
            return
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            appStore.updateAutoAbsorbStatus(
                phase: .attention,
                message: "无法访问收纳目录：\(error.localizedDescription)"
            )
            return
        }

        // Reconcile existing items before watching new changes.
        refreshStoredItems()
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            appStore.updateAutoAbsorbStatus(
                phase: .attention,
                message: "无法监听收纳目录的文件变化"
            )
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self, let source = self.storageMonitor else { return }
            if source.data.intersection([.rename, .delete, .revoke]) != [] {
                source.cancel()
                self.storageMonitor = nil
                if FileManager.default.fileExists(atPath: directory.path) {
                    self.startStorageMonitoring()
                } else {
                    self.appStore.updateAutoAbsorbStatus(
                        phase: .attention,
                        message: "收纳目录已移动或不可用，请检查目录位置"
                    )
                }
                return
            }
            // Wait for internal move/rename/restore callbacks so their panel references
            // are updated before reconciling directory changes.
            self.appStore.drainFileOperations { [weak self] in
                self?.refreshStoredItems()
            }
        }
        source.setCancelHandler { close(descriptor) }
        storageMonitor = source
        source.resume()
    }

    private func refreshStoredItems() {
        let directory = appStore.storageDirectory
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            NSLog("DesktopFolderWidget: cannot list storage directory: \(error)")
            return
        }
        appStore.panels.first?.synchronizeManagedItems(urls, directory: directory)
    }

    private func absorbDesktopItems(
        _ urls: [URL],
        completion: @escaping (Set<String>) -> Void
    ) {
        let existingPaths = Set(
            appStore.panels.flatMap { $0.config.items.map {
                DesktopWatcher.pathKey(URL(fileURLWithPath: $0.path))
            }}
        )
        let batch = DesktopIntakeBatch.make(urls: urls, existingPaths: existingPaths)

        guard !batch.candidates.isEmpty else {
            completion(batch.handledPaths)
            return
        }

        appStore.updateAutoAbsorbStatus(
            phase: .processing,
            pendingCount: batch.candidates.count,
            message: "正在收纳桌面新项目"
        )
        appStore.absorb(urls: batch.candidates, kind: .automaticAbsorb) { [weak self] result in
            guard let self else {
                completion(batch.handledPaths)
                return
            }

            if let panel = self.appStore.panels.first {
                panel.add(urls: result.added)
                if !result.added.isEmpty {
                    self.appStore.saveNow()
                }
            }

            var handledPaths = batch.handledPaths
            // Only successfully resolved or permanently rejected items are acknowledged.
            // Transient failures remain eligible for retry by DesktopWatcher.
            handledPaths.formUnion(result.resolved.keys)
            handledPaths.formUnion(result.rejected.map(DesktopWatcher.pathKey))

            if !result.failed.isEmpty {
                let names = result.failed.map(\.lastPathComponent).joined(separator: ", ")
                self.appStore.updateAutoAbsorbStatus(
                    phase: .retrying,
                    pendingCount: result.failed.count,
                    message: "有 \(result.failed.count) 个项目暂时无法收纳，将自动重试：\(names)"
                )
                NSLog(
                    "DesktopFolderWidget: auto-absorb failed for \(result.failed.count) item(s): \(names)"
                )
            } else {
                let movedCount = result.moved.count
                self.appStore.updateAutoAbsorbStatus(
                    phase: .monitoring,
                    message: movedCount > 0
                        ? "已自动收纳 \(movedCount) 个项目，自动收纳已开启"
                        : "自动收纳已开启，等待桌面文件变化"
                )
            }

            completion(handledPaths)
        }
    }
}
