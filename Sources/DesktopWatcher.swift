import CoreServices
import Foundation

final class DesktopWatcher {
    private static let temporaryExtensions: Set<String> = ["download", "crdownload", "part"]
    // A quiet period after the latest event keeps intake responsive without fixed polling.
    private static let stabilityInterval: TimeInterval = 0.5
    private static let eventLatency: TimeInterval = 0.1
    private static let retryBaseInterval: TimeInterval = 2
    private static let retryMaximumInterval: TimeInterval = 60
    private static let fallbackScanInterval: TimeInterval = 30
    private static let missingDesktopRetryInterval: TimeInterval = 3

    private struct FileStability {
        var size: Int64
        var modifiedAt: Date?
        var resourceIdentifier: String?
        var lastActivityAt: Date

        func matches(_ other: FileStability) -> Bool {
            size == other.size
                && modifiedAt == other.modifiedAt
                && resourceIdentifier == other.resourceIdentifier
        }
    }

    private let desktopURL: URL
    private let desktopRootPath: String
    private let desktopRootPrefix: String
    private let onStableItems: ([URL], @escaping (Set<String>) -> Void) -> Void
    private let watcherQueue = DispatchQueue(
        label: "com.covet.DesktopFolderWidget.desktop-watcher",
        qos: .utility
    )
    private let watcherQueueKey = DispatchSpecificKey<UInt8>()
    private var eventStream: FSEventStreamRef?
    private var stabilityTimer: DispatchSourceTimer?
    private var stabilityTimerGeneration: UInt64 = 0
    private var fallbackTimer: DispatchSourceTimer?
    private var missingDesktopTimer: DispatchSourceTimer?
    private var known: [String: FileStability] = [:]
    private var inFlight: Set<String> = []
    private var pendingPaths: Set<String> = []
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

    private static let eventCallback: FSEventStreamCallback = {
        _, info, eventCount, eventPaths, eventFlags, _ in
        guard let info else { return }

        let watcher = Unmanaged<DesktopWatcher>.fromOpaque(info).takeUnretainedValue()
        let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
        var events: [(String, FSEventStreamEventFlags)] = []
        events.reserveCapacity(eventCount)

        for index in 0..<eventCount {
            guard let path = paths[index] else { continue }
            events.append((String(cString: path), eventFlags[index]))
        }

        watcher.handleFileSystemEvents(events)
    }

    init(
        desktopURL: URL,
        onNewItems: @escaping ([URL], @escaping (Set<String>) -> Void) -> Void
    ) {
        self.desktopURL = desktopURL
        let rootPath = desktopURL.standardizedFileURL.path
        self.desktopRootPath = rootPath
        self.desktopRootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        self.onStableItems = onNewItems
        self.watcherQueue.setSpecific(key: watcherQueueKey, value: 1)
        watcherQueue.async { [weak self] in
            self?.startWatching()
        }
    }

    deinit {
        stopOnQueue()
    }

    func stop() {
        if DispatchQueue.getSpecific(key: watcherQueueKey) != nil {
            stopOnQueue()
        } else {
            watcherQueue.sync {
                stopOnQueue()
            }
        }
    }

    private func stopOnQueue() {
        guard !isStopped else { return }
        isStopped = true

        stabilityTimer?.cancel()
        stabilityTimer = nil
        fallbackTimer?.cancel()
        fallbackTimer = nil
        missingDesktopTimer?.cancel()
        missingDesktopTimer = nil

        stopEventStream()
    }

    private func stopEventStream() {
        guard let eventStream else { return }
        FSEventStreamStop(eventStream)
        FSEventStreamInvalidate(eventStream)
        FSEventStreamRelease(eventStream)
        self.eventStream = nil
    }

    private func restartAfterRootChange() {
        guard !isStopped else { return }
        stopEventStream()
        startWatching()
    }

    // A user-initiated restore into Desktop is an intentional destination, not a new intake.
    // Keep the restored file acknowledged until its identity or metadata changes.
    func markHandled(_ url: URL) {
        watcherQueue.async { [weak self] in
            guard let self, !self.isStopped else { return }
            let path = Self.pathKey(url)
            guard let fingerprint = self.fingerprint(for: url) else { return }
            self.known[path] = fingerprint
            self.fileStability.removeValue(forKey: path)
            self.pendingPaths.remove(path)
            self.retryAttempts.removeValue(forKey: path)
            self.retryAfter.removeValue(forKey: path)
            self.updateStabilityTimer()
        }
    }

    private func startWatching() {
        guard !isStopped else { return }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: desktopURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            fallbackTimer?.cancel()
            fallbackTimer = nil
            startMissingDesktopRetry()
            return
        }

        missingDesktopTimer?.cancel()
        missingDesktopTimer = nil

        if startEventStream() {
            scanDesktop()
        } else {
            NSLog(
                "DesktopFolderWidget: FSEvents unavailable; using a %d-second fallback scan",
                Int(Self.fallbackScanInterval)
            )
            scanDesktop()
            startFallbackScan()
        }
    }

    private func startEventStream() -> Bool {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.eventCallback,
            &context,
            [desktopURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.eventLatency,
            flags
        ) else {
            return false
        }

        FSEventStreamSetDispatchQueue(stream, watcherQueue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }

        eventStream = stream
        return true
    }

    private func startMissingDesktopRetry() {
        guard missingDesktopTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: watcherQueue)
        timer.schedule(
            deadline: .now() + Self.missingDesktopRetryInterval,
            repeating: Self.missingDesktopRetryInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self, !self.isStopped else { return }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: self.desktopURL.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else { return }
            self.startWatching()
        }
        timer.resume()
        missingDesktopTimer = timer
    }

    private func startFallbackScan() {
        guard fallbackTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: watcherQueue)
        timer.schedule(
            deadline: .now() + Self.fallbackScanInterval,
            repeating: Self.fallbackScanInterval
        )
        timer.setEventHandler { [weak self] in
            self?.scanDesktop()
        }
        timer.resume()
        fallbackTimer = timer
    }

    private func scanDesktop(resetQuietPeriod: Bool = false) {
        guard !isStopped else { return }

        let items: [URL]
        do {
            items = try FileManager.default.contentsOfDirectory(
                at: desktopURL,
                includingPropertiesForKeys: [
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .fileResourceIdentifierKey
                ],
                options: [.skipsHiddenFiles]
            )
            lastScanError = nil
            if eventStream != nil {
                fallbackTimer?.cancel()
                fallbackTimer = nil
            }
        } catch {
            let message = error.localizedDescription
            if lastScanError != message {
                NSLog("DesktopFolderWidget: desktop scan failed; will retry: %@", message)
                lastScanError = message
            }
            startFallbackScan()
            return
        }

        let now = Date()
        var currentPaths = Set<String>()
        currentPaths.reserveCapacity(items.count)
        var keyedItems: [(url: URL, path: String)] = []
        keyedItems.reserveCapacity(items.count)

        for item in items {
            let path = Self.pathKey(item)
            currentPaths.insert(path)
            keyedItems.append((item, path))
        }

        removeMissingPaths(from: currentPaths)

        let readyItems = keyedItems.compactMap {
            observe($0.url, pathKey: $0.path, eventObserved: resetQuietPeriod, now: now)
        }
        submitStableItems(readyItems)
        updateStabilityTimer()
    }

    private func handleFileSystemEvents(_ events: [(String, FSEventStreamEventFlags)]) {
        guard !isStopped else { return }

        let recoveryFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagRootChanged
        )
        var requiresFullScan = false
        var rootChanged = false
        var changedPaths = Set<String>()
        var nestedChangedPaths = Set<String>()

        for (eventPath, flags) in events {
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
                rootChanged = true
                break
            }
            if flags & recoveryFlags != 0 {
                requiresFullScan = true
                break
            }

            let eventURL = URL(fileURLWithPath: eventPath).standardizedFileURL
            if let itemURL = topLevelItem(for: eventURL.path) {
                if eventURL.path == itemURL.standardizedFileURL.path {
                    changedPaths.insert(itemURL.path)
                } else {
                    nestedChangedPaths.insert(itemURL.path)
                }
            } else if eventURL.path == desktopRootPath {
                requiresFullScan = true
                break
            }
        }

        if rootChanged {
            watcherQueue.async { [weak self] in
                self?.restartAfterRootChange()
            }
            return
        }
        if requiresFullScan {
            scanDesktop(resetQuietPeriod: true)
            return
        }

        let now = Date()
        for path in nestedChangedPaths {
            resetStability(for: URL(fileURLWithPath: path), now: now)
        }
        let readyItems = changedPaths.compactMap { path -> URL? in
            let url = URL(fileURLWithPath: path)
            return observe(url, pathKey: Self.pathKey(url), eventObserved: true, now: now)
        }
        submitStableItems(readyItems)
        updateStabilityTimer()
    }

    private func topLevelItem(for standardizedEventPath: String) -> URL? {
        guard standardizedEventPath.hasPrefix(desktopRootPrefix) else { return nil }
        let relativePath = standardizedEventPath.dropFirst(desktopRootPrefix.count)
        guard let firstComponent = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: true
        ).first else { return nil }

        let name = String(firstComponent)
        guard !name.hasPrefix(".") else { return nil }
        return desktopURL.appendingPathComponent(name)
    }

    private func removeMissingPaths(from currentPaths: Set<String>) {
        let trackedPaths = Set(known.keys)
            .union(fileStability.keys)
            .union(pendingPaths)
            .union(retryAttempts.keys)

        for path in trackedPaths where !currentPaths.contains(path) {
            removeTracking(for: path)
        }
    }

    private func resetStability(for url: URL, now: Date = Date()) {
        let path = Self.pathKey(url)
        guard !inFlight.contains(path) else { return }
        guard let current = fingerprint(for: url, now: now) else {
            removeTracking(for: path)
            return
        }
        known.removeValue(forKey: path)
        fileStability[path] = current
        pendingPaths.insert(path)
    }

    private func observe(
        _ url: URL,
        pathKey path: String,
        eventObserved: Bool,
        now: Date = Date()
    ) -> URL? {
        guard !isStopped else { return nil }

        guard !inFlight.contains(path) else { return nil }
        guard !Self.isTemporary(url) else {
            removeTracking(for: path)
            return nil
        }

        guard let current = fingerprint(for: url, now: now) else {
            removeTracking(for: path)
            return nil
        }

        if let previous = known[path] {
            if previous.matches(current) {
                return nil
            }

            known.removeValue(forKey: path)
            fileStability[path] = current
            pendingPaths.insert(path)
            return nil
        }

        if var previous = fileStability[path] {
            if !previous.matches(current) || eventObserved {
                previous.size = current.size
                previous.modifiedAt = current.modifiedAt
                previous.resourceIdentifier = current.resourceIdentifier
                previous.lastActivityAt = now
                fileStability[path] = previous
            }
        } else {
            fileStability[path] = current
        }
        pendingPaths.insert(path)

        guard let stability = fileStability[path],
              now >= stability.lastActivityAt.addingTimeInterval(Self.stabilityInterval),
              retryAfter[path].map({ now >= $0 }) ?? true
        else { return nil }

        return url
    }

    private func fingerprint(for url: URL, now: Date = Date()) -> FileStability? {
        guard let values = try? url.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        ) else { return nil }

        return FileStability(
            size: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate,
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
            lastActivityAt: now
        )
    }

    private func checkPendingPaths() {
        guard !isStopped else { return }
        let now = Date()
        let paths = pendingPaths.subtracting(inFlight)
        let readyItems = paths.compactMap { path in
            observe(URL(fileURLWithPath: path), pathKey: path, eventObserved: false, now: now)
        }
        submitStableItems(readyItems)
        updateStabilityTimer()
    }

    private func cancelStabilityTimer() {
        stabilityTimerGeneration &+= 1
        stabilityTimer?.cancel()
        stabilityTimer = nil
    }

    private func updateStabilityTimer() {
        guard !isStopped else { return }

        let nextDeadline = pendingPaths.subtracting(inFlight).compactMap { path -> Date? in
            guard let stability = fileStability[path] else { return nil }
            let quietDeadline = stability.lastActivityAt.addingTimeInterval(Self.stabilityInterval)
            return max(quietDeadline, retryAfter[path] ?? .distantPast)
        }.min()

        guard let nextDeadline else {
            cancelStabilityTimer()
            return
        }

        cancelStabilityTimer()
        let generation = stabilityTimerGeneration
        let timer = DispatchSource.makeTimerSource(queue: watcherQueue)
        let delay = max(0.01, nextDeadline.timeIntervalSinceNow)
        timer.schedule(deadline: .now() + delay, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self,
                  !self.isStopped,
                  self.stabilityTimerGeneration == generation
            else { return }

            self.stabilityTimer?.cancel()
            self.stabilityTimer = nil
            self.checkPendingPaths()
        }
        timer.resume()
        stabilityTimer = timer
    }

    private func submitStableItems(_ urls: [URL]) {
        var candidatePaths = Set<String>()
        var readyItems: [URL] = []
        for url in urls {
            let path = Self.pathKey(url)
            guard pendingPaths.contains(path), !inFlight.contains(path) else { continue }
            if candidatePaths.insert(path).inserted {
                readyItems.append(url)
            }
        }
        guard !readyItems.isEmpty else { return }

        inFlight.formUnion(candidatePaths)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onStableItems(readyItems) { [weak self] handledPaths in
                guard let self else { return }
                self.watcherQueue.async { [weak self] in
                    guard let self, !self.isStopped else { return }
                    self.inFlight.subtract(candidatePaths)

                    for path in candidatePaths {
                        if handledPaths.contains(path) {
                            if let fingerprint = self.fileStability.removeValue(forKey: path) {
                                self.known[path] = fingerprint
                            }
                            self.pendingPaths.remove(path)
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
                    self.updateStabilityTimer()
                }
            }
        }
    }

    private func removeTracking(for path: String) {
        known.removeValue(forKey: path)
        fileStability.removeValue(forKey: path)
        pendingPaths.remove(path)
        retryAttempts.removeValue(forKey: path)
        retryAfter.removeValue(forKey: path)
    }
}
