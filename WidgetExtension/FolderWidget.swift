import SwiftUI
import WidgetKit

struct FolderWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: DesktopWidgetSnapshot?
}

struct FolderWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FolderWidgetEntry {
        FolderWidgetEntry(
            date: .now,
            snapshot: DesktopWidgetSnapshot(
                updatedAt: .now,
                itemCount: 12,
                items: [
                    WidgetSummaryItem(name: "项目资料", isFolder: true),
                    WidgetSummaryItem(name: "报告.pdf", isFolder: false),
                    WidgetSummaryItem(name: "数据.csv", isFolder: false)
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FolderWidgetEntry) -> Void) {
        completion(FolderWidgetEntry(date: .now, snapshot: DesktopWidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FolderWidgetEntry>) -> Void) {
        let entry = FolderWidgetEntry(date: .now, snapshot: DesktopWidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct FolderWidgetView: View {
    let entry: FolderWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var visibleLimit: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 5
        default: return 8
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .widgetAccentable()
                Text("文档整理")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            if let snapshot = entry.snapshot {
                Text("\(snapshot.itemCount) 个项目")
                    .font(.title2.weight(.semibold))
                    .contentTransition(.numericText())
                    .widgetAccentable()

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(snapshot.items.prefix(visibleLimit).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 7) {
                            Image(systemName: item.isFolder ? "folder" : "doc")
                                .font(.caption)
                                .widgetAccentable()
                            Text(item.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text("打开文档整理以同步文件")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            if family != .systemSmall {
                Text("点击打开完整文件面板")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "dfw-organizer://open"))
    }
}

struct DesktopFolderSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: DesktopWidgetSnapshot.kind,
            provider: FolderWidgetProvider()
        ) { entry in
            FolderWidgetView(entry: entry)
        }
        .configurationDisplayName("文档整理")
        .description("在桌面查看整理目录概况，点击打开完整文件管理面板。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct DesktopFolderWidgetBundle: WidgetBundle {
    var body: some Widget {
        DesktopFolderSummaryWidget()
    }
}
