import Foundation
import CoreGraphics

struct PanelFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    func resized(width: Double, height: Double) -> PanelFrame {
        var resizedRect = rect
        resizedRect.origin.y += resizedRect.height - height
        resizedRect.size.width = width
        resizedRect.size.height = height
        return PanelFrame(rect: resizedRect)
    }

    func clamped(to visibleFrame: CGRect) -> PanelFrame {
        var clampedRect = rect

        clampedRect.origin.x = clampedRect.width >= visibleFrame.width
            ? visibleFrame.minX
            : min(max(clampedRect.minX, visibleFrame.minX), visibleFrame.maxX - clampedRect.width)
        clampedRect.origin.y = clampedRect.height >= visibleFrame.height
            ? visibleFrame.minY
            : min(max(clampedRect.minY, visibleFrame.minY), visibleFrame.maxY - clampedRect.height)

        return PanelFrame(rect: clampedRect)
    }

    static let `default` = PanelFrame(x: 140, y: 360, width: 390, height: 360)
}

struct WidgetItem: Codable, Identifiable, Equatable {
    var id: UUID
    var path: String
    var addedAt: Date

    init(id: UUID = UUID(), path: String, addedAt: Date = Date()) {
        self.id = id
        self.path = path
        self.addedAt = addedAt
    }

    var url: URL { URL(fileURLWithPath: path) }

    var name: String {
        let last = url.lastPathComponent
        return last.isEmpty ? path : last
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}

enum PanelLevelMode: String, Codable, CaseIterable, Identifiable {
    case desktop
    case floating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: return "桌面层"
        case .floating: return "悬浮置顶"
        }
    }
}

struct PanelConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var frame: PanelFrame
    var items: [WidgetItem]
    var backgroundHex: String
    var opacity: Double
    var columns: Int
    var levelMode: PanelLevelMode
    var isHidden: Bool
    var cornerRadius: Double
    var isLocked: Bool?

    init(
        id: UUID = UUID(),
        frame: PanelFrame = .default,
        items: [WidgetItem] = [],
        backgroundHex: String = PanelAppearance.defaultTintHex,
        opacity: Double = 0.92,
        columns: Int = 5,
        levelMode: PanelLevelMode = .desktop,
        isHidden: Bool = false,
        cornerRadius: Double = 22,
        isLocked: Bool? = nil
    ) {
        self.id = id
        self.frame = frame
        self.items = items
        self.backgroundHex = backgroundHex
        self.opacity = opacity
        self.columns = columns
        self.levelMode = levelMode
        self.isHidden = isHidden
        self.cornerRadius = cornerRadius
        self.isLocked = isLocked
    }

    var positionLocked: Bool {
        isLocked ?? false
    }

    static func makeDefault(index: Int) -> PanelConfig {
        var frame = PanelFrame.default
        frame.x += Double(index) * 36
        frame.y -= Double(index) * 36
        return PanelConfig(frame: frame)
    }
}
