import Foundation

@main
struct PanelStateRepositoryTests {
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
            .appendingPathComponent("panel-state-tests-\(UUID().uuidString)", isDirectory: true)
        try! fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let missingRepository = JSONPanelStateRepository(
            directory: root.appendingPathComponent("Missing", isDirectory: true)
        )
        if case .missing = missingRepository.load() {
            expect(true, "missing state returns the missing result")
        } else {
            expect(false, "missing state returns the missing result")
        }

        let unreadableDirectory = root.appendingPathComponent("Unreadable", isDirectory: true)
        try! fileManager.createDirectory(at: unreadableDirectory, withIntermediateDirectories: true)
        let directoryAtStatePath = unreadableDirectory.appendingPathComponent("panels.json", isDirectory: true)
        try! fileManager.createDirectory(at: directoryAtStatePath, withIntermediateDirectories: true)
        let unreadableRepository = JSONPanelStateRepository(directory: unreadableDirectory)
        if case .recoveryRequired = unreadableRepository.load() {
            expect(true, "an unreadable existing state is not mistaken for a missing file")
        } else {
            expect(false, "an unreadable existing state is not mistaken for a missing file")
        }

        let validDirectory = root.appendingPathComponent("Valid", isDirectory: true)
        let validRepository = JSONPanelStateRepository(directory: validDirectory)
        let panel = PanelConfig.makeDefault(index: 2)
        do {
            try validRepository.save([panel])
        } catch {
            expect(false, "valid panel state saves: \(error)")
        }
        if case .loaded(let panels) = validRepository.load() {
            expect(panels == [panel], "valid panel state round-trips")
        } else {
            expect(false, "valid panel state round-trips")
        }

        let legacyDirectory = root.appendingPathComponent("LegacyAppearance", isDirectory: true)
        try! fileManager.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let legacyURL = legacyDirectory.appendingPathComponent("panels.json")
        let legacyJSON = """
        {
          "version": 1,
          "panels": [{
            "id": "11111111-2222-3333-4444-555555555555",
            "frame": {"x": 10, "y": 20, "width": 390, "height": 360},
            "items": [],
            "backgroundHex": "#1C1C1E",
            "opacity": 0.04,
            "columns": 5,
            "levelMode": "desktop",
            "isHidden": false,
            "cornerRadius": 22
          }]
        }
        """
        try! Data(legacyJSON.utf8).write(to: legacyURL)
        let legacyRepository = JSONPanelStateRepository(directory: legacyDirectory)
        if case .loaded(let panels) = legacyRepository.load() {
            expect(
                panels.count == 1 && panels[0].frame.width == 390,
                "legacy panel state loads while ignoring retired appearance keys"
            )
            do {
                try legacyRepository.save(panels)
                let saved = try Data(contentsOf: legacyURL)
                let object = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
                let savedPanel = (object["panels"] as! [[String: Any]])[0]
                expect(
                    savedPanel["opacity"] == nil && savedPanel["backgroundHex"] == nil,
                    "retired appearance keys are removed on the next normal save"
                )
            } catch {
                expect(false, "legacy panel state can be saved after migration: \(error)")
            }
        } else {
            expect(false, "legacy panel state loads while ignoring retired appearance keys")
        }

        let corruptDirectory = root.appendingPathComponent("Corrupt", isDirectory: true)
        try! fileManager.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        let corruptURL = corruptDirectory.appendingPathComponent("panels.json")
        let corruptData = Data("{not-json".utf8)
        try! corruptData.write(to: corruptURL)
        let corruptRepository = JSONPanelStateRepository(directory: corruptDirectory)
        if case .recoveryRequired = corruptRepository.load() {
            expect(true, "corrupt state requires recovery instead of appearing missing")
        } else {
            expect(false, "corrupt state requires recovery instead of appearing missing")
        }
        let backups = (try? fileManager.contentsOfDirectory(at: corruptDirectory, includingPropertiesForKeys: nil)) ?? []
        let backup = backups.first { $0.lastPathComponent.hasPrefix("panels.corrupt-") }
        expect(
            backup.flatMap { try? Data(contentsOf: $0) } == corruptData,
            "corrupt source bytes are preserved in a unique backup"
        )
        do {
            try corruptRepository.save([panel])
            expect(false, "corrupt state blocks writes that would overwrite the original")
        } catch {
            expect(
                fileManager.fileExists(atPath: corruptURL.path)
                    && (try? Data(contentsOf: corruptURL)) == corruptData,
                "blocked save leaves the original corrupt file unchanged"
            )
        }

        let directCorruptDirectory = root.appendingPathComponent("DirectCorrupt", isDirectory: true)
        try! fileManager.createDirectory(at: directCorruptDirectory, withIntermediateDirectories: true)
        let directCorruptURL = directCorruptDirectory.appendingPathComponent("panels.json")
        let directCorruptBytes = Data("{invalid-without-prior-load".utf8)
        try! directCorruptBytes.write(to: directCorruptURL)
        let directCorruptRepository = JSONPanelStateRepository(directory: directCorruptDirectory)
        do {
            try directCorruptRepository.save([panel])
            expect(false, "save cannot bypass corruption protection when load was not called first")
        } catch {
            expect(
                (try? Data(contentsOf: directCorruptURL)) == directCorruptBytes,
                "save checks existing state before writing even without an explicit load"
            )
        }

        let futureDirectory = root.appendingPathComponent("Future", isDirectory: true)
        try! fileManager.createDirectory(at: futureDirectory, withIntermediateDirectories: true)
        let futureURL = futureDirectory.appendingPathComponent("panels.json")
        let futureData = try! JSONEncoder().encode(
            PersistedState(version: JSONPanelStateRepository.currentVersion + 1, panels: [panel])
        )
        try! futureData.write(to: futureURL)
        let futureRepository = JSONPanelStateRepository(directory: futureDirectory)
        if case .recoveryRequired = futureRepository.load() {
            expect(true, "unsupported state versions require recovery")
        } else {
            expect(false, "unsupported state versions require recovery")
        }
        do {
            try futureRepository.save([])
            expect(false, "unsupported state version blocks downgrade writes")
        } catch {
            expect(
                (try? Data(contentsOf: futureURL)) == futureData,
                "unsupported-version source remains unchanged"
            )
        }

        let blocker = root.appendingPathComponent("not-a-directory")
        try! Data("block".utf8).write(to: blocker)
        let failingRepository = JSONPanelStateRepository(
            directory: blocker.appendingPathComponent("support", isDirectory: true)
        )
        do {
            try failingRepository.save([panel])
            expect(false, "filesystem save failures propagate to the caller")
        } catch {
            expect(true, "filesystem save failures propagate to the caller")
        }

        print(failures == 0 ? "ALL PANEL STATE TESTS PASSED" : "\(failures) PANEL STATE TEST(S) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
