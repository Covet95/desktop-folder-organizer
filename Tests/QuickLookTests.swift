import AppKit
import Foundation
import QuickLookUI

@main
struct QuickLookTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // 创建临时 fixture 文件（避免硬编码用户路径）
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("ql-test-\(UUID().uuidString)", isDirectory: true)
        try! fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let fixtureURL = tempDir.appendingPathComponent("test-preview.pdf")
        fileManager.createFile(atPath: fixtureURL.path, contents: Data("QuickLook test content".utf8))

        let item = WidgetItem(path: fixtureURL.path)
        guard item.exists else {
            print("FAIL  preview fixture missing")
            exit(1)
        }

        let controller = QuickLookController()
        controller.preview(item)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let panel = QLPreviewPanel.shared() else {
                print("FAIL  no preview panel")
                exit(1)
            }

            let count = controller.numberOfPreviewItems(in: panel)
            let previewItem = controller.previewPanel(panel, previewItemAt: 0)
            let previewPath = (previewItem as? URL)?.path
                ?? (previewItem as? NSURL)?.path
                ?? "nil"

            print("panel visible:", panel.isVisible)
            print("preview count:", count)
            print("preview path:", previewPath)

            let ok = panel.isVisible && count == 1 && previewPath == fixtureURL.path
            panel.orderOut(nil)
            print(ok ? "PASS  quick look" : "FAIL  quick look")
            exit(ok ? 0 : 1)
        }

        app.run()
    }
}
