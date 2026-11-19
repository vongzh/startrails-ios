import SwiftUI
import WidgetKit

struct StartrailsWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct StartrailsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StartrailsWidgetEntry {
        StartrailsWidgetEntry(date: Date(), snapshot: Self.sampleSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (StartrailsWidgetEntry) -> Void) {
        let snap = WidgetSnapshotStore.load() ?? (context.isPreview ? Self.sampleSnapshot : nil)
        completion(StartrailsWidgetEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StartrailsWidgetEntry>) -> Void) {
        let entry = StartrailsWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.load())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private static let sampleSnapshot = WidgetSnapshot(
        serverName: "家宽主控",
        profileName: "default",
        totalSources: 3,
        totalNodes: 42,
        activeTokens: 2,
        updatedAt: Date(),
        sources: [
            WidgetSourceItem(
                id: "s1",
                name: "主力机场",
                uploadBytes: 12_000_000_000,
                downloadBytes: 68_000_000_000,
                totalBytes: 200_000_000_000,
                expireTimestamp: Date().addingTimeInterval(86_400 * 18).timeIntervalSince1970,
                lastError: nil,
                snapshotStale: false
            ),
            WidgetSourceItem(
                id: "s2",
                name: "备用轻量",
                uploadBytes: 4_000_000_000,
                downloadBytes: 26_000_000_000,
                totalBytes: 100_000_000_000,
                expireTimestamp: Date().addingTimeInterval(86_400 * 5).timeIntervalSince1970,
                lastError: nil,
                snapshotStale: false
            ),
        ]
    )
}

@main
struct StartrailsWidget: Widget {
    let kind = "com.vongzh.startrails.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StartrailsTimelineProvider()) { entry in
            StartrailsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Startrails 订阅余量")
        .description("实时查看机场订阅流量进度、到期倒计时与节点总数。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct StartrailsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StartrailsWidgetEntry

    var body: some View {
        if let snap = entry.snapshot {
            switch family {
            case .systemSmall:
                smallView(snap)
            default:
                mediumView(snap)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "circle.hexagonpath")
                    .font(.title3)
                    .foregroundStyle(.blue)
                Text("Startrails")
                    .font(.headline)
                Text("打开 App 连接控制台即可显示流量与节点概览")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func smallView(_ snap: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snap.profileName)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Spacer()
                Text("\(snap.totalNodes) 节点")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let primary = snap.sources.first(where: { $0.totalBytes > 0 }) {
                Spacer(minLength: 2)
                Text(primary.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                ProgressView(value: primary.usageRatio)
                    .tint(primary.usageRatio > 0.9 ? .red : .blue)
                HStack {
                    Text("余 \(formatGB(primary.remainingBytes))")
                        .font(.caption2.weight(.medium).monospacedDigit())
                    Spacer()
                    if let days = primary.daysRemaining {
                        Text(days >= 0 ? "\(days)天" : "已过期")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(days <= 7 ? .orange : .secondary)
                    }
                }
            } else {
                Spacer()
                Text("\(snap.totalSources) 订阅源")
                    .font(.title3.bold())
                Text("\(snap.activeTokens) 生效链接")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func mediumView(_ snap: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(snap.serverName) · \(snap.profileName)", systemImage: "circle.hexagonpath")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Spacer()
                Text("\(snap.totalNodes) 节点 · \(snap.activeTokens) 链接")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            let topSources = Array(snap.sources.filter { $0.totalBytes > 0 }.prefix(2))
            if topSources.isEmpty {
                Spacer()
                Text("暂无带流量统计的远端订阅源")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(topSources) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            Text("余 \(formatGB(item.remainingBytes))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if let days = item.daysRemaining {
                                Text(days >= 0 ? "· \(days)天" : "· 已过期")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(days <= 7 ? .orange : .secondary)
                            }
                        }
                        ProgressView(value: item.usageRatio)
                            .tint(item.usageRatio > 0.9 ? .red : .blue)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func formatGB(_ bytes: Double) -> String {
        let gb = bytes / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        return String(format: "%.0f MB", bytes / 1_048_576)
    }
}
