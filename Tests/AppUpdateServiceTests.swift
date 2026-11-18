import CryptoKit
import Foundation

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@main
struct AppUpdateServiceTests {
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

        // 1. SemanticVersion parsing & ordering
        expect(SemanticVersion("v0.2.17")! > SemanticVersion("0.2.16")!, "v0.2.17 > 0.2.16")
        expect(SemanticVersion("0.3") == SemanticVersion("0.3.0"), "0.3 equals 0.3.0")
        expect(SemanticVersion("0.3")! > SemanticVersion("0.2.16")!, "0.3 > 0.2.16")
        expect(SemanticVersion("v0.2.16") == SemanticVersion("0.2.16"), "v prefix normalized")
        expect(SemanticVersion("0.2.17-beta.1")! < SemanticVersion("0.2.17")!, "prerelease < stable")
        expect(SemanticVersion("0.2.17-beta.1")! < SemanticVersion("0.2.17-beta.2")!, "prerelease numeric comparison")
        expect(SemanticVersion("0.2.16+29") == SemanticVersion("0.2.16"), "build metadata ignored in SemVer")
        expect(SemanticVersion("") == nil, "empty version rejected")
        expect(SemanticVersion("1.2.3.4") == nil, "4-component version rejected")

        // 2. GitHub release decoding & asset selection
        let sampleJSON = """
        {
          "tag_name": "v0.2.17",
          "name": "文档整理 v0.2.17 (Build 30)",
          "body": "新增在线检查更新",
          "html_url": "https://github.com/Covet95/desktop-folder-organizer/releases/tag/v0.2.17",
          "draft": false,
          "prerelease": false,
          "assets": [
            {
              "name": "DesktopFolderOrganizer-v0.2.17-dSYM.zip",
              "browser_download_url": "https://example.com/dsym.zip",
              "size": 100,
              "digest": null
            },
            {
              "name": "DesktopFolderOrganizer-v0.2.17-macOS-universal.dmg",
              "browser_download_url": "https://example.com/app.dmg",
              "size": 2000,
              "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            },
            {
              "name": "DesktopFolderOrganizer-v0.2.17-macOS-universal.zip",
              "browser_download_url": "https://example.com/app.zip",
              "size": 1500,
              "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            },
            {
              "name": "SHA256SUMS.txt",
              "browser_download_url": "https://example.com/SHA256SUMS.txt",
              "size": 200,
              "digest": null
            }
          ]
        }
        """.data(using: .utf8)!

        let decodedRelease = try! JSONDecoder().decode(GitHubRelease.self, from: sampleJSON)
        expect(
            decodedRelease.preferredZipAsset?.name == "DesktopFolderOrganizer-v0.2.17-macOS-universal.zip",
            "preferredZipAsset chooses universal zip and skips dSYM"
        )
        expect(
            decodedRelease.preferredDmgAsset?.name == "DesktopFolderOrganizer-v0.2.17-macOS-universal.dmg",
            "preferredDmgAsset chooses universal dmg"
        )
        expect(
            decodedRelease.checksumManifestAsset?.name == "SHA256SUMS.txt",
            "checksumManifestAsset finds SHA256SUMS.txt"
        )

        let evalUpdate = try! AppUpdateService.evaluate(release: decodedRelease, currentVersionString: "0.2.16")
        if case .updateAvailable(_, let latest) = evalUpdate {
            expect(latest == SemanticVersion("0.2.17"), "evaluate detects available update")
        } else {
            expect(false, "evaluate detects available update")
        }

        let evalCurrent = try! AppUpdateService.evaluate(release: decodedRelease, currentVersionString: "0.2.17")
        if case .upToDate = evalCurrent {
            expect(true, "evaluate reports up to date on same version")
        } else {
            expect(false, "evaluate reports up to date on same version")
        }

        // 3. SHA-256 manifest parsing and file verification
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("dfw-update-tests-\(UUID().uuidString)", isDirectory: true)
        try! fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let payloadFile = root.appendingPathComponent("payload.zip")
        let payloadData = Data("release-archive-bytes".utf8)
        try! payloadData.write(to: payloadFile)
        let actualHex = try! AppUpdateService.sha256Hex(of: payloadFile)
        let expectedCryptoHex = SHA256.hash(data: payloadData).map { String(format: "%02x", $0) }.joined()
        expect(actualHex == expectedCryptoHex, "sha256Hex matches CryptoKit digest")

        let sumsText = """
        \(actualHex)  payload.zip
        1111111111111111111111111111111111111111111111111111111111111111 *other.dmg
        """
        let parsedSums = AppUpdateService.parseSHA256Sums(sumsText)
        expect(parsedSums["payload.zip"] == actualHex, "parseSHA256Sums parses space-separated entry")
        expect(
            parsedSums["other.dmg"] == "1111111111111111111111111111111111111111111111111111111111111111",
            "parseSHA256Sums strips leading asterisk"
        )

        let assetWithDigest = GitHubReleaseAsset(
            name: "payload.zip",
            browserDownloadURL: URL(string: "https://example.com/payload.zip")!,
            size: Int64(payloadData.count),
            digest: "sha256:\(actualHex)"
        )
        let resolvedDigest = try! AppUpdateService.expectedSHA256(for: assetWithDigest, manifest: parsedSums)
        expect(resolvedDigest == actualHex, "expectedSHA256 agrees between manifest and asset digest")

        do {
            try AppUpdateService.verifyDownloadedAsset(at: payloadFile, asset: assetWithDigest, expectedDigest: actualHex)
            expect(true, "verifyDownloadedAsset succeeds for matching size and SHA-256")
        } catch {
            expect(false, "verifyDownloadedAsset succeeds for matching size and SHA-256")
        }

        do {
            try AppUpdateService.verifyDownloadedAsset(
                at: payloadFile,
                asset: assetWithDigest,
                expectedDigest: String(repeating: "0", count: 64)
            )
            expect(false, "verifyDownloadedAsset rejects mismatched SHA-256")
        } catch let error as AppUpdateError {
            if case .checksumMismatch = error {
                expect(true, "verifyDownloadedAsset rejects mismatched SHA-256")
            } else {
                expect(false, "verifyDownloadedAsset rejects mismatched SHA-256")
            }
        } catch {
            expect(false, "verifyDownloadedAsset rejects mismatched SHA-256")
        }

        // 4. Bundle extraction, codesign verification, writability & Downloads deduplication
        let writableApp = root.appendingPathComponent("文档整理.app", isDirectory: true)
        let macOSDir = writableApp.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try! fileManager.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        let exeURL = macOSDir.appendingPathComponent("DesktopFolderWidget")
        try! "#!/bin/sh\nexit 0\n".write(to: exeURL, atomically: true, encoding: .utf8)
        try! fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exeURL.path)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.covet.DesktopFolderWidget</string>
        <key>CFBundleExecutable</key><string>DesktopFolderWidget</string>
        <key>CFBundleShortVersionString</key><string>0.2.17</string>
        </dict></plist>
        """
        try! plist.write(to: writableApp.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)

        expect(AppUpdateService.canReplaceBundle(at: writableApp), "canReplaceBundle returns true for writable .app")
        expect(
            !AppUpdateService.canReplaceBundle(at: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/y/d/App.app")),
            "canReplaceBundle rejects AppTranslocation bundles"
        )

        let existingDmg = root.appendingPathComponent("Update.dmg")
        fileManager.createFile(atPath: existingDmg.path, contents: Data())
        let dedupedDmg = AppUpdateService.uniqueDestinationURL(in: root, preferredName: "Update.dmg")
        expect(dedupedDmg.lastPathComponent == "Update (1).dmg", "uniqueDestinationURL appends numeric suffix")

        // Ad-hoc sign the test app, zip with ditto, and verify extractAndVerifyAppBundle
        let signProc = Process()
        signProc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signProc.arguments = ["--force", "--sign", "-", writableApp.path]
        try! signProc.run()
        signProc.waitUntilExit()
        expect(signProc.terminationStatus == 0, "test bundle ad-hoc signed")

        let signedZip = root.appendingPathComponent("signed.zip")
        let zipProc = Process()
        zipProc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zipProc.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", writableApp.path, signedZip.path]
        try! zipProc.run()
        zipProc.waitUntilExit()
        expect(zipProc.terminationStatus == 0, "test bundle zipped with ditto")

        let extractStaging = root.appendingPathComponent("staging", isDirectory: true)
        try! fileManager.createDirectory(at: extractStaging, withIntermediateDirectories: true)
        let extractedApp = try? AppUpdateService.extractAndVerifyAppBundle(
            fromZip: signedZip,
            expectedBundleIdentifier: "com.covet.DesktopFolderWidget",
            into: extractStaging
        )
        expect(extractedApp?.lastPathComponent == "文档整理.app", "extractAndVerifyAppBundle validates bundle ID and codesign")

        // 5. Network update check using MockURLProtocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        let service = AppUpdateService(
            session: mockSession,
            latestReleaseURL: URL(string: "https://api.github.com/repos/Covet95/desktop-folder-organizer/releases/latest")!
        )

        let group1 = DispatchGroup()
        group1.enter()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, sampleJSON)
        }
        var checkResult: Result<AppUpdateCheckResult, Error>?
        service.checkForUpdate(currentVersionString: "0.2.16") { result in
            checkResult = result
            group1.leave()
        }
        group1.wait()
        if case .success(.updateAvailable(_, let latest)) = checkResult {
            expect(latest == SemanticVersion("0.2.17"), "checkForUpdate returns updateAvailable on newer release")
        } else {
            expect(false, "checkForUpdate returns updateAvailable on newer release")
        }

        let group2 = DispatchGroup()
        group2.enter()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        var notFoundResult: Result<AppUpdateCheckResult, Error>?
        service.checkForUpdate(currentVersionString: "0.2.16") { result in
            notFoundResult = result
            group2.leave()
        }
        group2.wait()
        if case .failure(let err as AppUpdateError) = notFoundResult, err == .releaseUnavailable(404) {
            expect(true, "checkForUpdate surfaces HTTP 404 clearly")
        } else {
            expect(false, "checkForUpdate surfaces HTTP 404 clearly")
        }

        print(failures == 0 ? "ALL APP UPDATE SERVICE TESTS PASSED" : "\(failures) APP UPDATE SERVICE TESTS FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
