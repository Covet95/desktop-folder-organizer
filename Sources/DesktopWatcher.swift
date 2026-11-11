import Foundation

final class DesktopWatcher {
    private static let temporaryExtensions: Set<String> = ["download", "crdownload", "part"]
    // Three matching observations provide two full intervals without size or modification changes.
    private static let stabilityCheckCount = 3
    private static let retryBaseInterval: TimeInterval = 2
    private static let retryMaximumInterval: TimeInterval = 60

    private struct FileStability {
        var size: Int64
        var modifiedAt: Date?
        var resourceIdentifier: String?
        var checks: Int

        func matches(_ other: FileStability) -> Bool {
            size == other.size
                && modifiedAt == other.modifiedAt
                && resourceIdentifier == other.resourceIdentifier
        }
    }

    private let desktopURL: URL
    private let onStableItems: ([URL], @escaping (Set<String>) -> Void) -> Void
    private var timer: DispatchSourceTimer?
    private var known: [String: FileStability] = [:]
    private var inFlight: Set<String> = []
    private var retryAttempts: [String: Int] = [:]
    private var retryAfter: [String: Date] = [:]
    private var fileStability: [String: FileStability] = [:]
    private var lastScanError: String?
    private var isStopped = false

    static func pathKey(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func isTemporary(_ url: URL) -> Bool {
        temporaryExtensions.contains(url.pathExtension.lowercased())
    }

    init(
        desktopURL: URL,
        onNewItems: @escaping ([URL], @escaping (Set<String>) -> Void) -> Void
    ) {
        self.desktopURL = desktopURL
        self.onStableItems = onNewItems

        // Existing desktop items are intentionally not pre-marked as known:
        // they must pass the same stability checks as files created after launch.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.scan()
        }
        timer.resume()
        self.timer = timer
    }

    deinit {
        stop()
    }

    func stop() {
        isStopped = true
        timer?.cancel()
        timer = nil
    }

    // A user-initiated restore into Desktop is an intentional destination, not a new intake.
    // Keep the restored file acknowledged until its identity or metadata changes.
    func markHandled(_ url: URL) {
        let path = Self.pathKey(url)
        guard let values = try? url.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        ) else { return }
        known[path] = FileStability(
            size: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate,
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
            checks: Self.stabilityCheckCount
        )
        fileStability.removeValue(forKey: path)
    }

    private func scan() {
        guard !isStopped else { return }

        let items: [URL]
        do {
            items = try FileManager.default.contentsOfDirectory(
                at: desktopURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            lastScanError = nil
        } catch {
            let message = error.localizedDescription
            if lastScanError != message {
                NSLog("DesktopFolderWidget: desktop scan failed; will retry: %@", message)
                lastScanError = message
            }
            return
        }

        let now = Date()
        let currentPaths = Set(items.map(Self.pathKey))

        known = known.filter { currentPaths.contains($0.key) }
        fileStability = fileStability.filter {
            currentPaths.contains($0.key) && known[$0.key] == nil
        }
        retryAttempts = retryAttempts.filter { currentPaths.contains($0.key) }
        retryAfter = retryAfter.filter { currentPaths.contains($0.key) }

        var readyItems: [URL] = []

        for item in items {
            let path = Self.pathKey(item)
            guard !inFlight.contains(path), !Self.isTemporary(item) else { continue }

            guard let values = try? item.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
            ) else {
                fileStability.removeValue(forKey: path)
                continue
            }

            let current = FileStability(
                size: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate,
                resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
                checks: 1
            )

            if let previous = known[path] {
                if previous.matches(current) {
                    continue
                }

                // The path still exists, but its file identity or metadata changed.
                // Treat it as a new item even if deletion and recreation happened between scans.
                known.removeValue(forKey: path)
                fileStability[path] = current
                continue
            }

            if var previous = fileStability[path], previous.matches(current) {
                previous.checks += 1
                fileStability[path] = previous
            } else {
                fileStability[path] = current
            }

            guard let stability = fileStability[path],
                  stability.checks >= Self.stabilityCheckCount,
                  retryAfter[path].map({ now >= $0 }) ?? true
            else { continue }

            readyItems.append(item)
        }

        guard !readyItems.isEmpty else { return }

        let candidatePaths = Set(readyItems.map(Self.pathKey))
        inFlight.formUnion(candidatePaths)

        onStableItems(readyItems) { [weak self] handledPaths in
            guard let self else { return }
            let finish = { [weak self] in
                guard let self, !self.isStopped else { return }
                self.inFlight.subtract(candidatePaths)

                for path in candidatePaths {
                    if handledPaths.contains(path) {
                        if let fingerprint = self.fileStability.removeValue(forKey: path) {
                            self.known[path] = fingerprint
                        }
                        self.retryAttempts.removeValue(forKey: path)
                        self.retryAfter.removeValue(forKey: path)
                    } else {
                        let attempts = (self.retryAttempts[path] ?? 0) + 1
                        self.retryAttempts[path] = attempts
                        let exponent = min(attempts - 1, 10)
                        let delay = min(
                            Self.retryMaximumInterval,
                            Self.retryBaseInterval * pow(2, Double(exponent))
                        )
                        self.retryAfter[path] = Date().addingTimeInterval(delay)
                        NSLog(
                            "DesktopFolderWidget: auto-absorb will retry \(path) in \(Int(delay)) seconds (attempt \(attempts + 1))"
                        )
                    }
                }
            }

            if Thread.isMainThread {
                finish()
            } else {
                DispatchQueue.main.async(execute: finish)
            }
        }
    }
}
