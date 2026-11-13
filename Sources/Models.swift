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

/// Visual-only classification: never changes a file's storage URL.
enum FileDisplayGroup: String, CaseIterable {
    case folders, images, documents, spreadsheets, presentations, videos, audio, archives, code, other

    var title: String {
        switch self {
        case .folders: return "文件夹"
        case .images: return "图片"
        case .documents: return "文档"
        case .spreadsheets: return "表格"
        case .presentations: return "演示文稿"
        case .videos: return "视频"
        case .audio: return "音频"
        case .archives: return "压缩包"
        case .code: return "代码"
        case .other: return "其他"
        }
    }

    static func forItem(_ item: WidgetItem) -> FileDisplayGroup {
        forItem(item, isDirectory: item.isDirectory)
    }

    static func forItem(_ item: WidgetItem, isDirectory: Bool) -> FileDisplayGroup {
        if isDirectory { return .folders }
        let ext = item.url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tif", "tiff", "svg", "raw", "dng":
            return .images
        case "pdf", "doc", "docx", "pages", "txt", "rtf", "rtfd", "md", "epub", "odt":
            return .documents
        case "xls", "xlsx", "numbers", "csv", "tsv", "ods":
            return .spreadsheets
        case "ppt", "pptx", "key", "odp":
            return .presentations
        case "mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm":
            return .videos
        case "mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "wma":
            return .audio
        case "zip", "7z", "rar", "tar", "gz", "bz2", "xz", "dmg", "pkg":
            return .archives
        case "swift", "py", "js", "ts", "html", "css", "json", "xml", "yaml", "yml", "sh", "sql", "ipynb", "java", "cpp", "c", "h":
            return .code
        default:
            return .other
        }
    }
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

    var displayGroup: FileDisplayGroup { FileDisplayGroup.forItem(self) }
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

enum PanelAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "自动"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

struct PanelConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var frame: PanelFrame
    var items: [WidgetItem]
    var columns: Int
    var levelMode: PanelLevelMode
    var isHidden: Bool
    var cornerRadius: Double
    var isLocked: Bool?
    var groupByType: Bool?
    var appearanceMode: PanelAppearanceMode?

    init(
        id: UUID = UUID(),
        frame: PanelFrame = .default,
        items: [WidgetItem] = [],
        columns: Int = 5,
        levelMode: PanelLevelMode = .desktop,
        isHidden: Bool = false,
        cornerRadius: Double = 22,
        isLocked: Bool? = nil,
        groupByType: Bool? = nil,
        appearanceMode: PanelAppearanceMode? = nil
    ) {
        self.id = id
        self.frame = frame
        self.items = items
        self.columns = columns
        self.levelMode = levelMode
        self.isHidden = isHidden
        self.cornerRadius = cornerRadius
        self.isLocked = isLocked
        self.groupByType = groupByType
        self.appearanceMode = appearanceMode
    }

    var positionLocked: Bool {
        isLocked ?? false
    }

    /// Existing panels default to visual grouping without a schema migration.
    var isTypeGroupingEnabled: Bool { groupByType ?? true }

    var effectiveAppearanceMode: PanelAppearanceMode { appearanceMode ?? .system }

    static func makeDefault(index: Int) -> PanelConfig {
        var frame = PanelFrame.default
        frame.x += Double(index) * 36
        frame.y -= Double(index) * 36
        return PanelConfig(frame: frame)
    }
}
