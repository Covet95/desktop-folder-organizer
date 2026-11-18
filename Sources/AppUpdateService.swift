import CryptoKit
import Foundation

struct SemanticVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [String]

    init?(_ raw: String) {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned.removeFirst()
        }
        if let plusIndex = cleaned.firstIndex(of: "+") {
            cleaned = String(cleaned[..<plusIndex])
        }

        let split = cleaned.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let coreParts = split[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(coreParts.count) else { return nil }

        var numbers: [Int] = []
        numbers.reserveCapacity(3)
        for part in coreParts {
            guard !part.isEmpty, let value = Int(part), value >= 0 else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 {
            numbers.append(0)
        }

        var prereleaseParts: [String] = []
        if split.count == 2 {
            let rawPrerelease = String(split[1])
            guard !rawPrerelease.isEmpty else { return nil }
            let parts = rawPrerelease.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.allSatisfy({ !$0.isEmpty }) else { return nil }
            prereleaseParts = parts.map(String.init)
        }

        self.major = numbers[0]
        self.minor = numbers[1]
        self.patch = numbers[2]
        self.prerelease = prereleaseParts
    }

    var displayString: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : "\(core)-\(prerelease.joined(separator: "."))"
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        if lhs.prerelease.isEmpty && rhs.prerelease.isEmpty { return false }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }

        let count = max(lhs.prerelease.count, rhs.prerelease.count)
        for index in 0..<count {
            if index >= lhs.prerelease.count { return true }
            if index >= rhs.prerelease.count { return false }
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            if left == right { continue }

            let leftInt = Int(left)
            let rightInt = Int(right)
            switch (leftInt, rightInt) {
            case let (l?, r?):
                return l < r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return left.compare(right, options: .literal) == .orderedAscending
            }
        }
        return false
    }
}

struct GitHubReleaseAsset: Decodable, Equatable {
    let name: String
    let browserDownloadURL: URL
    let size: Int64
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case digest
    }
}

struct GitHubRelease: Decodable, Equatable {
    let tagName: String
    let name: String
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }

    var checksumManifestAsset: GitHubReleaseAsset? {
        assets.first { $0.name.caseInsensitiveCompare("SHA256SUMS.txt") == .orderedSame }
    }

    var preferredZipAsset: GitHubReleaseAsset? {
        let zips = assets.filter {
            let lower = $0.name.lowercased()
            return lower.hasSuffix(".zip") && !lower.contains("dsym")
        }
        return zips.first(where: { $0.name.lowercased().contains("universal") })
            ?? zips.first(where: { $0.name.lowercased().contains("macos") })
            ?? zips.first
    }

    var preferredDmgAsset: GitHubReleaseAsset? {
        let dmgs = assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
        return dmgs.first(where: { $0.name.lowercased().contains("universal") })
            ?? dmgs.first(where: { $0.name.lowercased().contains("macos") })
            ?? dmgs.first
    }
}

enum AppUpdateCheckResult: Equatable {
    case upToDate(current: SemanticVersion, latest: SemanticVersion, release: GitHubRelease)
    case updateAvailable(release: GitHubRelease, latest: SemanticVersion)
}

enum AppUpdateInstallOutcome: Equatable {
    case relaunchingAfterInstall
    case savedToDownloads(URL)
}

enum AppUpdateError: LocalizedError, Equatable {
    case invalidCurrentVersion(String)
    case invalidRemoteVersion(String)
    case releaseUnavailable(Int)
    case rateLimited
    case invalidResponse
    case downloadFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case invalidArchive(String)
    case codeSignatureInvalid(String)

    var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion(let version):
            return "当前应用版本号无法解析：\(version)"
        case .invalidRemoteVersion(let version):
            return "远端发布版本号无法解析：\(version)"
        case .releaseUnavailable(let code):
            if code == 404 {
                return "未获取到发布信息（HTTP 404）。请确认仓库已公开且存在已发布的 Release。"
            }
            return "检查更新失败（HTTP \(code)）。"
        case .rateLimited:
            return "GitHub API 访问次数受限，请稍后再试或直接前往 Release 页面。"
        case .invalidResponse:
            return "服务器返回了无效的更新信息。"
        case .downloadFailed(let detail):
            return "安装包下载失败：\(detail)"
        case .checksumMismatch(let expected, let actual):
            return "安装包 SHA-256 校验未通过，已取消安装。\n期望：\(expected)\n实际：\(actual)"
        case .invalidArchive(let detail):
            return "安装包解析失败：\(detail)"
        case .codeSignatureInvalid(let detail):
            return "新版本签名校验失败，已取消安装：\(detail)"
        }
    }
}

final class AppUpdateService {
    static let defaultLatestReleaseURL = URL(
        string: "https://api.github.com/repos/Covet95/desktop-folder-organizer/releases/latest"
    )!
    static let releasesPageURL = URL(
        string: "https://github.com/Covet95/desktop-folder-organizer/releases"
    )!

    private let session: URLSession
    private let latestReleaseURL: URL

    init(
        session: URLSession = .shared,
        latestReleaseURL: URL = AppUpdateService.defaultLatestReleaseURL
    ) {
        self.session = session
        self.latestReleaseURL = latestReleaseURL
    }

    @discardableResult
    func checkForUpdate(
        currentVersionString: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        completion: @escaping (Result<AppUpdateCheckResult, Error>) -> Void
    ) -> URLSessionDataTask {
        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let agentVersion = currentVersionString.isEmpty ? "unknown" : currentVersionString
        request.setValue("DesktopFolderWidget/\(agentVersion)", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(AppUpdateError.invalidResponse))
                return
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 403 || http.statusCode == 429 {
                    completion(.failure(AppUpdateError.rateLimited))
                } else {
                    completion(.failure(AppUpdateError.releaseUnavailable(http.statusCode)))
                }
                return
            }

            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let evaluation = try Self.evaluate(release: release, currentVersionString: currentVersionString)
                completion(.success(evaluation))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
        return task
    }

    static func evaluate(
        release: GitHubRelease,
        currentVersionString: String
    ) throws -> AppUpdateCheckResult {
        guard let current = SemanticVersion(currentVersionString) else {
            throw AppUpdateError.invalidCurrentVersion(currentVersionString)
        }
        guard !release.draft, !release.prerelease else {
            return .upToDate(current: current, latest: current, release: release)
        }
        guard let remote = SemanticVersion(release.tagName) else {
            throw AppUpdateError.invalidRemoteVersion(release.tagName)
        }
        if remote > current {
            return .updateAvailable(release: release, latest: remote)
        }
        return .upToDate(current: current, latest: remote, release: release)
    }

    static func parseSHA256Sums(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2 else { continue }
            let digest = String(parts[0]).lowercased()
            guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else { continue }
            var fileName = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if fileName.hasPrefix("*") {
                fileName.removeFirst()
            }
            if !fileName.isEmpty {
                result[fileName] = digest
            }
        }
        return result
    }

    static func expectedSHA256(
        for asset: GitHubReleaseAsset,
        manifest: [String: String]?
    ) throws -> String? {
        let manifestDigest = manifest?[asset.name]?.lowercased()
        let assetDigest: String?
        if let raw = asset.digest?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           raw.hasPrefix("sha256:") {
            let hex = String(raw.dropFirst("sha256:".count))
            assetDigest = (hex.count == 64 && hex.allSatisfy(\.isHexDigit)) ? hex : nil
        } else {
            assetDigest = nil
        }

        if let manifestDigest, let assetDigest, manifestDigest != assetDigest {
            throw AppUpdateError.checksumMismatch(expected: manifestDigest, actual: assetDigest)
        }
        return manifestDigest ?? assetDigest
    }

    static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func canReplaceBundle(at bundleURL: URL, fileManager: FileManager = .default) -> Bool {
        guard bundleURL.pathExtension == "app",
              !bundleURL.path.contains("/AppTranslocation/") else {
            return false
        }
        let parentDir = bundleURL.deletingLastPathComponent()
        return fileManager.isWritableFile(atPath: parentDir.path)
            && fileManager.isWritableFile(atPath: bundleURL.path)
    }

    static func uniqueDestinationURL(
        in directory: URL,
        preferredName: String,
        fileManager: FileManager = .default
    ) -> URL {
        let candidate = directory.appendingPathComponent(preferredName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let nsName = preferredName as NSString
        let ext = nsName.pathExtension
        let stem = nsName.deletingPathExtension
        var index = 1
        while true {
            let nextName = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            let nextURL = directory.appendingPathComponent(nextName)
            if !fileManager.fileExists(atPath: nextURL.path) {
                return nextURL
            }
            index += 1
        }
    }

    @discardableResult
    static func fetchChecksumManifest(
        from asset: GitHubReleaseAsset?,
        session: URLSession = .shared,
        completion: @escaping ([String: String]?) -> Void
    ) -> URLSessionDataTask? {
        guard let asset else {
            completion(nil)
            return nil
        }
        var request = URLRequest(url: asset.browserDownloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("DesktopFolderWidget", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request) { data, response, _ in
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let data,
                  let text = String(data: data, encoding: .utf8) else {
                completion(nil)
                return
            }
            completion(parseSHA256Sums(text))
        }
        task.resume()
        return task
    }

    static func verifyDownloadedAsset(
        at fileURL: URL,
        asset: GitHubReleaseAsset,
        expectedDigest: String?
    ) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let actualSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if asset.size > 0, actualSize != asset.size {
            throw AppUpdateError.downloadFailed("文件大小不匹配（\(actualSize) / \(asset.size) 字节）")
        }
        if let expectedDigest {
            let actualDigest = try sha256Hex(of: fileURL)
            guard actualDigest.caseInsensitiveCompare(expectedDigest) == .orderedSame else {
                throw AppUpdateError.checksumMismatch(expected: expectedDigest, actual: actualDigest)
            }
        }
    }

    static func extractAndVerifyAppBundle(
        fromZip zipURL: URL,
        expectedBundleIdentifier: String,
        into stagingRoot: URL
    ) throws -> URL {
        let extractDir = stagingRoot.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let dittoResult = try runProcess(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", zipURL.path, extractDir.path]
        )
        guard dittoResult.status == 0 else {
            throw AppUpdateError.invalidArchive(dittoResult.stderr.isEmpty ? "无法解压更新包" : dittoResult.stderr)
        }

        let topLevel = try FileManager.default.contentsOfDirectory(
            at: extractDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let appCandidates = topLevel.filter { $0.pathExtension == "app" }
        guard let appURL = appCandidates.first(where: {
            Bundle(url: $0)?.bundleIdentifier == expectedBundleIdentifier
        }) ?? (appCandidates.count == 1 ? appCandidates.first : nil) else {
            throw AppUpdateError.invalidArchive("压缩包中未找到有效的应用包")
        }

        if let bundleID = Bundle(url: appURL)?.bundleIdentifier, bundleID != expectedBundleIdentifier {
            throw AppUpdateError.invalidArchive("应用 Bundle Identifier 不匹配（\(bundleID)）")
        }

        let codesignResult = try runProcess(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", appURL.path]
        )
        guard codesignResult.status == 0 else {
            throw AppUpdateError.codeSignatureInvalid(
                codesignResult.stderr.isEmpty ? "codesign 返回状态 \(codesignResult.status)" : codesignResult.stderr
            )
        }
        return appURL
    }

    static func launchReplaceAndRelaunch(
        currentBundleURL: URL,
        newBundleURL: URL,
        stagingRoot: URL,
        currentPID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws {
        let scriptURL = stagingRoot.appendingPathComponent("apply-update.sh")
        let script = """
        #!/bin/sh
        set -eu
        OLD_PID="$1"
        CURRENT_APP="$2"
        NEW_APP="$3"
        STAGING_ROOT="$4"

        i=0
        while kill -0 "$OLD_PID" 2>/dev/null; do
            i=$((i + 1))
            if [ "$i" -ge 120 ]; then
                rm -rf "$STAGING_ROOT"
                exit 1
            fi
            sleep 0.25
        done

        PARENT_DIR="$(dirname "$CURRENT_APP")"
        APP_NAME="$(basename "$CURRENT_APP")"
        BACKUP_APP="${PARENT_DIR}/.${APP_NAME}.update-backup.$$"

        cleanup() {
            if [ -d "$BACKUP_APP" ]; then
                rm -rf "$CURRENT_APP" || true
                mv "$BACKUP_APP" "$CURRENT_APP" || true
            fi
            rm -rf "$STAGING_ROOT"
        }
        trap cleanup EXIT

        if [ -e "$CURRENT_APP" ]; then
            mv "$CURRENT_APP" "$BACKUP_APP"
        fi
        mv "$NEW_APP" "$CURRENT_APP"
        rm -rf "$BACKUP_APP"
        rm -rf "$STAGING_ROOT"
        trap - EXIT

        open "$CURRENT_APP"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            scriptURL.path,
            String(currentPID),
            currentBundleURL.path,
            newBundleURL.path,
            stagingRoot.path
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static func runProcess(
        executable: String,
        arguments: [String]
    ) throws -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, stderr)
    }
}
