import Foundation

@main
struct WidgetSnapshotTests {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(
            "dfw-widget-snapshot-\(UUID().uuidString)", isDirectory: true
        )
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let folder = root.appendingPathComponent("A-资料", isDirectory: true)
        let file = root.appendingPathComponent("B-报告.pdf")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("test".utf8).write(to: file)

        let snapshot = DesktopWidgetSnapshot.make(from: [file, folder])
        precondition(snapshot.itemCount == 2)
        precondition(snapshot.items.map(\.name) == ["A-资料", "B-报告.pdf"])
        precondition(snapshot.items[0].isFolder && !snapshot.items[1].isFolder)

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DesktopWidgetSnapshot.self, from: data)
        precondition(decoded == snapshot)
        print("PASS: widget metadata is sorted, folder-aware and JSON round-trippable")
    }
}
