import AppKit

final class IconProvider {
    static let shared = IconProvider()

    private var cache: [String: NSImage] = [:]
    private let missingIcon: NSImage

    private init() {
        missingIcon = NSImage(systemSymbolName: "questionmark.square.dashed", accessibilityDescription: "文件不存在")
            ?? NSImage(size: NSSize(width: 48, height: 48))
        missingIcon.size = NSSize(width: 48, height: 48)
    }

    func icon(for item: WidgetItem) -> NSImage {
        guard item.exists else { return missingIcon }
        if let cached = cache[item.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: item.path)
        image.size = NSSize(width: 64, height: 64)
        cache[item.path] = image
        return image
    }
}
