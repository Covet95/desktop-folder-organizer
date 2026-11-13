import AppKit
import QuickLookThumbnailing

struct FileMetadata: Equatable {
    let exists: Bool
    let isDirectory: Bool
    let modificationTimestamp: TimeInterval

    static let missing = FileMetadata(exists: false, isDirectory: false, modificationTimestamp: 0)
}

final class IconProvider {
    static let shared = IconProvider()

    private static let thumbnailExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "bmp", "tif", "tiff", "pdf",
        "mov", "mp4", "m4v"
    ]
    private static let metadataTTL: TimeInterval = 0.5

    private let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        return cache
    }()
    private let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()
    private var metadataCache: [String: (value: FileMetadata, fetchedAt: TimeInterval)] = [:]
    private var inFlightThumbnails: [String: [(NSImage) -> Void]] = [:]
    private let missingIcon: NSImage

    private init() {
        missingIcon = NSImage(
            systemSymbolName: "questionmark.square.dashed",
            accessibilityDescription: "文件不存在"
        ) ?? NSImage(size: NSSize(width: 48, height: 48))
        missingIcon.size = NSSize(width: 48, height: 48)
    }

    func metadata(for item: WidgetItem, forceRefresh: Bool = false) -> FileMetadata {
        let now = ProcessInfo.processInfo.systemUptime
        if !forceRefresh,
           let cached = metadataCache[item.path],
           now - cached.fetchedAt < Self.metadataTTL {
            return cached.value
        }

        let url = item.url
        let value: FileMetadata
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]) {
            value = FileMetadata(
                exists: true,
                isDirectory: values.isDirectory ?? false,
                modificationTimestamp: values.contentModificationDate?.timeIntervalSince1970 ?? 0
            )
        } else if FileManager.default.fileExists(atPath: item.path) {
            value = FileMetadata(exists: true, isDirectory: false, modificationTimestamp: 0)
        } else {
            value = .missing
        }

        if metadataCache.count > 600 {
            metadataCache.removeAll(keepingCapacity: true)
        }
        metadataCache[item.path] = (value, now)
        return value
    }

    func icon(for item: WidgetItem) -> NSImage {
        icon(for: item, metadata: metadata(for: item))
    }

    func icon(for item: WidgetItem, metadata: FileMetadata) -> NSImage {
        guard metadata.exists else { return missingIcon }

        let thumbKey = thumbnailKey(for: item.path, timestamp: metadata.modificationTimestamp)
        if let cachedThumb = thumbnailCache.object(forKey: thumbKey as NSString) {
            return cachedThumb
        }

        let iconKey = item.path as NSString
        if let cachedIcon = iconCache.object(forKey: iconKey) {
            return cachedIcon
        }

        let image = NSWorkspace.shared.icon(forFile: item.path)
        image.size = NSSize(width: 64, height: 64)
        iconCache.setObject(image, forKey: iconKey)
        return image
    }

    func requestThumbnailIfNeeded(
        for item: WidgetItem,
        metadata: FileMetadata,
        scale: CGFloat,
        completion: @escaping (NSImage) -> Void
    ) {
        guard metadata.exists, !metadata.isDirectory else { return }
        let ext = item.url.pathExtension.lowercased()
        guard Self.thumbnailExtensions.contains(ext) else { return }

        let thumbKey = thumbnailKey(for: item.path, timestamp: metadata.modificationTimestamp)
        if let cached = thumbnailCache.object(forKey: thumbKey as NSString) {
            completion(cached)
            return
        }

        if inFlightThumbnails[thumbKey] != nil {
            inFlightThumbnails[thumbKey]?.append(completion)
            return
        }
        inFlightThumbnails[thumbKey] = [completion]

        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 64, height: 64),
            scale: max(1, scale),
            representationTypes: .thumbnail
        )
        request.iconMode = true

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let callbacks = self.inFlightThumbnails.removeValue(forKey: thumbKey) ?? []
                guard let representation, representation.type == .thumbnail else { return }
                let nsImage = representation.nsImage
                nsImage.size = NSSize(width: 64, height: 64)
                self.thumbnailCache.setObject(nsImage, forKey: thumbKey as NSString)
                for callback in callbacks {
                    callback(nsImage)
                }
            }
        }
    }

    func invalidate(path: String) {
        metadataCache.removeValue(forKey: path)
        iconCache.removeObject(forKey: path as NSString)
    }

    private func thumbnailKey(for path: String, timestamp: TimeInterval) -> String {
        "\(path)#\(Int64(timestamp * 1000))"
    }
}
