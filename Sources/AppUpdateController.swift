import AppKit
import Foundation

final class AppUpdateController: NSObject, URLSessionDownloadDelegate {
    private enum State {
        case idle
        case checking(URLSessionDataTask)
        case preparingDownload(URLSessionDataTask?)
        case downloading(URLSessionDownloadTask)
        case verifying
    }

    private struct ActiveDownload {
        let release: GitHubRelease
        let asset: GitHubReleaseAsset
        let expectedDigest: String?
        let autoReplace: Bool
        let stagingRoot: URL
    }

    private let service = AppUpdateService()
    private var state: State = .idle
    private var activeDownload: ActiveDownload?
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    private var progressWindow: UpdateProgressWindowController?

    func checkForUpdates() {
        switch state {
        case .checking, .preparingDownload, .downloading, .verifying:
            NSApp.activate(ignoringOtherApps: true)
            progressWindow?.showWindow(nil)
            progressWindow?.window?.makeKeyAndOrderFront(nil)
            return
        case .idle:
            break
        }

        let currentVersion = currentShortVersion
        let window = ensureProgressWindow()
        window.configureChecking()
        NSApp.activate(ignoringOtherApps: true)
        window.showWindow(nil)
        window.window?.makeKeyAndOrderFront(nil)

        let task = service.checkForUpdate(currentVersionString: currentVersion) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .checking = self.state else { return }
                self.state = .idle
                self.closeProgressWindow()

                switch result {
                case .success(.upToDate(let current, _, let release)):
                    self.showUpToDateAlert(current: current, release: release)
                case .success(.updateAvailable(let release, _)):
                    self.showUpdateAvailableAlert(release: release)
                case .failure(let error):
                    if (error as NSError).code == NSURLErrorCancelled {
                        return
                    }
                    self.showErrorAlert(title: "检查更新失败", message: error.localizedDescription, releaseURL: AppUpdateService.releasesPageURL)
                }
            }
        }
        state = .checking(task)
    }

    private var currentShortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var currentBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }

    private func ensureProgressWindow() -> UpdateProgressWindowController {
        if let progressWindow {
            return progressWindow
        }
        let controller = UpdateProgressWindowController()
        controller.onCancel = { [weak self] in
            self?.cancelCurrentOperation()
        }
        progressWindow = controller
        return controller
    }

    private func closeProgressWindow() {
        progressWindow?.close()
    }

    private func cancelCurrentOperation() {
        switch state {
        case .checking(let task):
            state = .idle
            task.cancel()
            closeProgressWindow()
        case .preparingDownload(let manifestTask):
            state = .idle
            manifestTask?.cancel()
            cleanupActiveDownload()
            closeProgressWindow()
        case .downloading(let task):
            state = .idle
            task.cancel()
            cleanupActiveDownload()
            closeProgressWindow()
        case .verifying, .idle:
            break
        }
    }

    private func cleanupActiveDownload() {
        if let stagingRoot = activeDownload?.stagingRoot {
            try? FileManager.default.removeItem(at: stagingRoot)
        }
        activeDownload = nil
    }

    private func showUpToDateAlert(current: SemanticVersion, release: GitHubRelease) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "当前已是最新版本"
        alert.informativeText = "文档整理 \(current.displayString)（Build \(currentBuildNumber)）已是最新版本。"
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "查看 Release 页面")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private func showUpdateAvailableAlert(release: GitHubRelease) {
        let canAutoReplace = AppUpdateService.canReplaceBundle(at: Bundle.main.bundleURL)
        let preferredAsset = canAutoReplace
            ? (release.preferredZipAsset ?? release.preferredDmgAsset)
            : (release.preferredDmgAsset ?? release.preferredZipAsset)
        let willAutoInstall = canAutoReplace && preferredAsset?.name.lowercased().hasSuffix(".zip") == true

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现新版本 \(release.tagName)"

        var infoLines = [
            "当前版本：\(currentShortVersion)（Build \(currentBuildNumber)）",
            "最新版本：\(release.tagName)"
        ]
        if let preferredAsset, preferredAsset.size > 0 {
            let formattedSize = ByteCountFormatter.string(fromByteCount: preferredAsset.size, countStyle: .file)
            infoLines.append("安装包大小：\(formattedSize)（\(preferredAsset.name)）")
        }
        alert.informativeText = infoLines.joined(separator: "\n")

        let notesText = release.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        alert.accessoryView = makeReleaseNotesView(
            (notesText?.isEmpty == false ? notesText! : "暂无详细更新说明。")
        )

        if preferredAsset != nil {
            alert.addButton(withTitle: willAutoInstall ? "立即下载并安装" : "立即下载")
            alert.addButton(withTitle: "在浏览器中查看")
            alert.addButton(withTitle: "稍后")
        } else {
            alert.addButton(withTitle: "前往 Release 页面")
            alert.addButton(withTitle: "稍后")
        }

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if let preferredAsset {
            switch response {
            case .alertFirstButtonReturn:
                beginDownload(release: release, asset: preferredAsset, autoReplace: willAutoInstall)
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(release.htmlURL)
            default:
                break
            }
        } else if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private func makeReleaseNotesView(_ text: String) -> NSView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 160))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 364, height: 160))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.font = .systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    private func beginDownload(release: GitHubRelease, asset: GitHubReleaseAsset, autoReplace: Bool) {
        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dfw-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        } catch {
            showErrorAlert(title: "无法创建临时目录", message: error.localizedDescription, releaseURL: release.htmlURL)
            return
        }

        let window = ensureProgressWindow()
        window.configureDownloading(fileName: asset.name, received: 0, expected: asset.size)
        NSApp.activate(ignoringOtherApps: true)
        window.showWindow(nil)
        window.window?.makeKeyAndOrderFront(nil)

        activeDownload = ActiveDownload(
            release: release,
            asset: asset,
            expectedDigest: nil,
            autoReplace: autoReplace,
            stagingRoot: stagingRoot
        )

        state = .preparingDownload(nil)
        let manifestTask = AppUpdateService.fetchChecksumManifest(from: release.checksumManifestAsset) { [weak self] manifest in
            DispatchQueue.main.async {
                guard let self, case .preparingDownload = self.state,
                      let current = self.activeDownload,
                      current.asset == asset, current.stagingRoot == stagingRoot else { return }

                do {
                    let expected = try AppUpdateService.expectedSHA256(for: asset, manifest: manifest)
                    self.activeDownload = ActiveDownload(
                        release: release,
                        asset: asset,
                        expectedDigest: expected,
                        autoReplace: autoReplace,
                        stagingRoot: stagingRoot
                    )

                    var request = URLRequest(url: asset.browserDownloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
                    request.setValue("DesktopFolderWidget", forHTTPHeaderField: "User-Agent")
                    let downloadTask = self.downloadSession.downloadTask(with: request)
                    self.state = .downloading(downloadTask)
                    downloadTask.resume()
                } catch {
                    self.state = .idle
                    self.cleanupActiveDownload()
                    self.closeProgressWindow()
                    self.showErrorAlert(title: "更新校验失败", message: error.localizedDescription, releaseURL: release.htmlURL)
                }
            }
        }
        if case .preparingDownload = state {
            state = .preparingDownload(manifestTask)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard case .downloading(let activeTask) = state, activeTask === downloadTask,
              let current = activeDownload else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : current.asset.size
        progressWindow?.configureDownloading(fileName: current.asset.name, received: totalBytesWritten, expected: expected)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard case .downloading(let activeTask) = state, activeTask === downloadTask,
              let current = activeDownload else { return }

        let downloadedFileURL = current.stagingRoot.appendingPathComponent(current.asset.name)
        do {
            try FileManager.default.moveItem(at: location, to: downloadedFileURL)
        } catch {
            state = .idle
            cleanupActiveDownload()
            closeProgressWindow()
            showErrorAlert(title: "下载保存失败", message: error.localizedDescription, releaseURL: current.release.htmlURL)
            return
        }

        state = .verifying
        progressWindow?.configureVerifying()

        let expectedBundleID = Bundle.main.bundleIdentifier ?? "com.covet.DesktopFolderWidget"
        let currentBundleURL = Bundle.main.bundleURL

        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                try AppUpdateService.verifyDownloadedAsset(
                    at: downloadedFileURL,
                    asset: current.asset,
                    expectedDigest: current.expectedDigest
                )

                if current.autoReplace {
                    let extractedApp = try AppUpdateService.extractAndVerifyAppBundle(
                        fromZip: downloadedFileURL,
                        expectedBundleIdentifier: expectedBundleID,
                        into: current.stagingRoot
                    )
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.finishAutoReplace(
                            currentBundleURL: currentBundleURL,
                            newBundleURL: extractedApp,
                            stagingRoot: current.stagingRoot,
                            releaseURL: current.release.htmlURL
                        )
                    }
                } else {
                    let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
                    let destination = AppUpdateService.uniqueDestinationURL(in: downloadsDir, preferredName: current.asset.name)
                    try FileManager.default.copyItem(at: downloadedFileURL, to: destination)
                    try? FileManager.default.removeItem(at: current.stagingRoot)

                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.state = .idle
                        self.activeDownload = nil
                        self.closeProgressWindow()
                        NSWorkspace.shared.activateFileViewerSelecting([destination])
                        self.showDownloadedToFolderAlert(destination: destination)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.state = .idle
                    self.cleanupActiveDownload()
                    self.closeProgressWindow()
                    self.showErrorAlert(title: "安装更新失败", message: error.localizedDescription, releaseURL: current.release.htmlURL)
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        guard case .downloading(let activeTask) = state, activeTask === task else { return }

        let releaseURL = activeDownload?.release.htmlURL ?? AppUpdateService.releasesPageURL
        state = .idle
        cleanupActiveDownload()
        closeProgressWindow()

        if (error as NSError).code == NSURLErrorCancelled {
            return
        }
        showErrorAlert(title: "下载更新失败", message: error.localizedDescription, releaseURL: releaseURL)
    }

    private func finishAutoReplace(
        currentBundleURL: URL,
        newBundleURL: URL,
        stagingRoot: URL,
        releaseURL: URL
    ) {
        do {
            try AppUpdateService.launchReplaceAndRelaunch(
                currentBundleURL: currentBundleURL,
                newBundleURL: newBundleURL,
                stagingRoot: stagingRoot
            )
            state = .idle
            activeDownload = nil
            closeProgressWindow()
            NSApp.terminate(nil)
        } catch {
            state = .idle
            cleanupActiveDownload()
            closeProgressWindow()
            showErrorAlert(title: "自动替换应用失败", message: error.localizedDescription, releaseURL: releaseURL)
        }
    }

    private func showDownloadedToFolderAlert(destination: URL) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "更新包已下载并校验通过"
        alert.informativeText = "由于当前应用位置无法直接就地替换，安装包已保存到「下载」文件夹：\n\(destination.path)"
        alert.addButton(withTitle: "打开安装包")
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(destination)
        }
    }

    private func showErrorAlert(title: String, message: String, releaseURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "打开 Release 页面")
        alert.addButton(withTitle: "关闭")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releaseURL)
        }
    }
}

private final class UpdateProgressWindowController: NSWindowController {
    var onCancel: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 126),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "软件更新"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        setupViews(in: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews(in window: NSWindow) {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 126))
        window.contentView = root

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(titleLabel)

        detailLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(detailLabel)

        progressBar.style = .bar
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(progressBar)

        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(didTapCancel)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            iconView.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

            progressBar.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            progressBar.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 12),

            cancelButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            cancelButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])
    }

    func configureChecking() {
        titleLabel.stringValue = "正在检查更新…"
        detailLabel.stringValue = "正在连接 GitHub Releases…"
        progressBar.isIndeterminate = true
        progressBar.startAnimation(nil)
        cancelButton.isEnabled = true
    }

    func configureDownloading(fileName: String, received: Int64, expected: Int64) {
        titleLabel.stringValue = "正在下载 \(fileName)…"
        if expected > 0 {
            progressBar.isIndeterminate = false
            progressBar.minValue = 0
            progressBar.maxValue = Double(expected)
            progressBar.doubleValue = Double(min(received, expected))
            let receivedText = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
            let expectedText = ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
            let percent = Int((Double(received) / Double(expected) * 100).rounded())
            detailLabel.stringValue = "\(receivedText) / \(expectedText)（\(min(100, max(0, percent)))%）"
        } else {
            progressBar.isIndeterminate = true
            progressBar.startAnimation(nil)
            detailLabel.stringValue = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
        }
        cancelButton.isEnabled = true
    }

    func configureVerifying() {
        titleLabel.stringValue = "正在校验并准备安装…"
        detailLabel.stringValue = "正在校验 SHA-256 与代码签名，请稍候"
        progressBar.isIndeterminate = true
        progressBar.startAnimation(nil)
        cancelButton.isEnabled = false
    }

    @objc private func didTapCancel() {
        onCancel?()
    }
}
