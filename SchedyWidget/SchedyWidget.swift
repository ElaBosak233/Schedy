//
//  SchedyWidget.swift
//  SchedyWidget
//
//  课程表小组件：1x1（小方）与 2x1（长条），显示课程表名 | 日期 星期几，以及接下来两节课或提示文案。
//

import WidgetKit
import SwiftUI

// MARK: - Timeline

struct SchedyWidgetEntry: TimelineEntry {
    let date: Date
    let entry: WidgetEntry
}

struct SchedyWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SchedyWidgetEntry {
        SchedyWidgetEntry(
            date: Date(),
            entry: WidgetEntry(
                scheduleName: "我的课程表",
                dateString: "2月26日",
                weekdayString: "周四",
                status: "next",
                course1: ("高等数学", "08:00", "A101"),
                course2: ("英语", "09:50", "B202")
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SchedyWidgetEntry) -> Void) {
        // 预览 / 小组件选择器里显示示例数据，避免只看到“今天没课”
        if context.isPreview {
            let sample = WidgetEntry(
                scheduleName: "我的课程表",
                dateString: "2月26日",
                weekdayString: "周四",
                status: "next",
                course1: ("高等数学", "08:00", "A101"),
                course2: ("英语", "09:50", "B202")
            )
            completion(SchedyWidgetEntry(date: Date(), entry: sample))
            return
        }
        let suite = UserDefaults(suiteName: kWidgetAppGroupSuiteName)
        let entry = WidgetEntry.load(from: suite)
        completion(SchedyWidgetEntry(date: Date(), entry: entry))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SchedyWidgetEntry>) -> Void) {
        let suite = UserDefaults(suiteName: kWidgetAppGroupSuiteName)
        let entry = WidgetEntry.load(from: suite)
        let widgetEntry = SchedyWidgetEntry(date: Date(), entry: entry)
        // 每 15 分钟刷新一次；主 App 写入数据后会调用 reloadTimelines，小组件会即时更新
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [widgetEntry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Views

struct SchedyWidgetView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var widgetFamily

    private var headerText: String {
        if entry.dateString.isEmpty && entry.weekdayString.isEmpty {
            return entry.scheduleName
        }
        return "\(entry.scheduleName) ｜ \(entry.dateString) \(entry.weekdayString)"
    }

    /// 是否从未同步过（主 App 未写入过日期则视为未同步）
    private var hasNeverSynced: Bool {
        entry.dateString.isEmpty && entry.weekdayString.isEmpty
    }

    private var bodyView: some View {
        Group {
            switch entry.status {
            case "noClass":
                Text(hasNeverSynced ? "打开 App 同步课程" : "今天没课哦，好好休息吧")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case "allDone":
                VStack(alignment: .leading, spacing: 6) {
                    Text("今天的课上完啦，辛苦～")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    if entry.course1 != nil || entry.course2 != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            if let c1 = entry.course1 {
                                courseRow(name: c1.name, time: c1.time, location: c1.location)
                            }
                            if let c2 = entry.course2 {
                                courseRow(name: c2.name, time: c2.time, location: c2.location)
                            }
                        }
                    }
                }
            case "next":
                VStack(alignment: .leading, spacing: 6) {
                    if let c1 = entry.course1 {
                        courseRow(name: c1.name, time: c1.time, location: c1.location)
                    }
                    if let c2 = entry.course2 {
                        courseRow(name: c2.name, time: c2.time, location: c2.location)
                    }
                }
            default:
                Text(hasNeverSynced ? "打开 App 同步课程" : "今天没课哦，好好休息吧")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func courseRow(name: String, time: String, location: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(time)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if !location.isEmpty {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            bodyView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: widgetFamily == WidgetFamily.systemSmall ? .center : .leading)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// 1x1 小方
struct SchedyWidgetSmallView: View {
    let entry: WidgetEntry

    var body: some View {
        SchedyWidgetView(entry: entry)
    }
}

// 2x1 长条
struct SchedyWidgetMediumView: View {
    let entry: WidgetEntry

    var body: some View {
        SchedyWidgetView(entry: entry)
    }
}

// MARK: - Widget

struct SchedyWidget: Widget {
    let kind: String = "SchedyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SchedyWidgetProvider()) { entry in
            SchedyWidgetView(entry: entry.entry)
        }
        .configurationDisplayName("今日课程")
        .description("显示当前课程表名称、日期与接下来两节课。")
        .supportedFamilies([WidgetFamily.systemSmall, WidgetFamily.systemMedium])
    }
}

// MARK: - Bundle

@main
struct SchedyWidgetBundle: WidgetBundle {
    var body: some Widget {
        SchedyWidget()
    }
}

// MARK: - Previews

private let previewEntry = WidgetEntry(
    scheduleName: "我的课程表",
    dateString: "2月26日",
    weekdayString: "周四",
    status: "next",
    course1: ("高等数学", "08:00", "A101"),
    course2: ("英语", "09:50", "B202")
)

struct SchedyWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SchedyWidgetSmallView(entry: previewEntry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            SchedyWidgetMediumView(entry: previewEntry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}
