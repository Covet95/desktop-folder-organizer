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

    init(
        appStore: AppStore,
        desktopURL: URL? = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    ) {
        self.appStore = appStore
        self.desktopURL = desktopURL
    }

    func start() {
        guard watcher == nil else { return }
        guard let desktopURL else {
            appStore.updateAutoAbsorbStatus(
                phase: .attention,
                message: "无法定位桌面目录，自动收纳未启动"
            )
            return
        }

        if appStore.autoAbsorbStatus.phase != .attention {
            appStore.updateAutoAbsorbStatus(phase: .monitoring, message: "正在监控桌面")
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
        appStore.onFileRestored = nil
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
                        ? "已自动收纳 \(movedCount) 个项目，继续监控桌面"
                        : "桌面监控正常"
                )
            }

            completion(handledPaths)
        }
    }
}
