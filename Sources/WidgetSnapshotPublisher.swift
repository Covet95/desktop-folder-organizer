import Foundation
import WidgetKit

final class WidgetSnapshotPublisher {
    private var lastNamesAndCount: [WidgetSummaryItem] = []
    private var lastCount = -1

    func publish(_ urls: [URL]) {
        let snapshot = DesktopWidgetSnapshot.make(from: urls)
        guard snapshot.itemCount != lastCount || snapshot.items != lastNamesAndCount else { return }

        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: DesktopWidgetSnapshot.appGroup
        ) else {
            NSLog("DesktopFolderWidget: widget app group unavailable")
            return
        }

        let url = directory.appendingPathComponent(DesktopWidgetSnapshot.filename)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoded = try JSONEncoder().encode(snapshot)
            try encoded.write(to: url, options: .atomic)
            lastCount = snapshot.itemCount
            lastNamesAndCount = snapshot.items
            WidgetCenter.shared.reloadTimelines(ofKind: DesktopWidgetSnapshot.kind)
        } catch {
            NSLog("DesktopFolderWidget: widget snapshot write failed: \(error)")
        }
    }
}
