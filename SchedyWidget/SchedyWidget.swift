//
//  SchedyWidget.swift
//  SchedyWidget
//
//  今日课程小组件：小/中尺寸，从 App Group 读取当前课表今日数据，显示日期、星期与最多两节课信息。
//

import WidgetKit
import SwiftUI

// MARK: - Timeline

struct SchedyWidgetEntry: TimelineEntry {
    let date: Date
    let entry: WidgetEntry
}

private let sampleEntry = WidgetEntry(
    scheduleName: String(localized: "schedule.default.name", defaultValue: "My Timetable"),
    dateString: String(localized: "widget.preview.date", defaultValue: "Feb 26"),
    weekdayString: String(localized: "calendar.weekday.thursday.short", defaultValue: "Thu"),
    status: "next",
    course1: (String(localized: "widget.preview.course.calculus", defaultValue: "Calculus"), "08:00", "A101"),
    course2: (String(localized: "widget.preview.course.english", defaultValue: "English"), "09:50", "B202")
)

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
struct SchedyWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = SchedyWidgetEntry
    typealias Intent = SchedyWidgetConfigIntent

    func placeholder(in context: Context) -> SchedyWidgetEntry {
        SchedyWidgetEntry(date: Date(), entry: sampleEntry)
    }

    func snapshot(for configuration: SchedyWidgetConfigIntent, in context: Context) async -> SchedyWidgetEntry {
        if context.isPreview {
            return SchedyWidgetEntry(date: Date(), entry: sampleEntry)
        }
        let suite = UserDefaults(suiteName: kWidgetAppGroupSuiteName)
        let scheduleChoice = configuration.scheduleName.flatMap { $0.isEmpty ? nil : $0 } ?? kWidgetScheduleOptionFollowApp
        let resolvedSchedule = WidgetEntry.resolveScheduleNameToShow(suite: suite, configuredName: scheduleChoice)
        let resolvedPreset = WidgetEntry.resolvePresetName(forScheduleName: resolvedSchedule, suite: suite)
        var widgetEntry = WidgetEntry.load(from: suite, scheduleName: resolvedSchedule, presetName: resolvedPreset)
        if widgetEntry.dateString.isEmpty, let legacy = WidgetEntry.loadLegacy(from: suite) {
            widgetEntry = legacy
        }
        return SchedyWidgetEntry(date: Date(), entry: widgetEntry)
    }

    func timeline(for configuration: SchedyWidgetConfigIntent, in context: Context) async -> Timeline<SchedyWidgetEntry> {
        let suite = UserDefaults(suiteName: kWidgetAppGroupSuiteName)
        let scheduleChoice = configuration.scheduleName.flatMap { $0.isEmpty ? nil : $0 } ?? kWidgetScheduleOptionFollowApp
        let resolvedSchedule = WidgetEntry.resolveScheduleNameToShow(suite: suite, configuredName: scheduleChoice)
        let resolvedPreset = WidgetEntry.resolvePresetName(forScheduleName: resolvedSchedule, suite: suite)

        let now = Date()
        let timelineData = WidgetEntry.loadTimeline(from: suite, scheduleName: resolvedSchedule, presetName: resolvedPreset)

        var entries: [SchedyWidgetEntry] = []
        if !timelineData.isEmpty {
            // 多日时间线：先选当前时刻对应状态，再附上未来所有切换点
            let pastEntries = timelineData.filter { $0.trigger <= now }
            let futureEntries = timelineData.filter { $0.trigger > now }
            let currentEntry = pastEntries.last ?? timelineData.first
            if let current = currentEntry {
                entries.append(SchedyWidgetEntry(date: now, entry: current.entry))
            }
            for item in futureEntries {
                entries.append(SchedyWidgetEntry(date: item.trigger, entry: item.entry))
            }
        }

        if entries.isEmpty {
            var widgetEntry = WidgetEntry.load(from: suite, scheduleName: resolvedSchedule, presetName: resolvedPreset)
            if widgetEntry.dateString.isEmpty, let legacy = WidgetEntry.loadLegacy(from: suite) {
                widgetEntry = legacy
            }
            entries.append(SchedyWidgetEntry(date: now, entry: widgetEntry))
        }

        // 用 .atEnd 让系统在最后一个切换点后请求下一段时间线
        return Timeline(entries: entries, policy: .atEnd)
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
                Text(hasNeverSynced ? String(localized: "widget.sync_required.description", defaultValue: "Open Schedy to sync classes") : String(localized: "widget.empty.description", defaultValue: "No classes today. Enjoy your break!"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case "allDone":
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "widget.finished.description", defaultValue: "All done for today. Nice work!"))
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
                Text(hasNeverSynced ? String(localized: "widget.sync_required.description", defaultValue: "Open Schedy to sync classes") : String(localized: "widget.empty.description", defaultValue: "No classes today. Enjoy your break!"))
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
        AppIntentConfiguration(kind: kind, intent: SchedyWidgetConfigIntent.self, provider: SchedyWidgetProvider()) { entry in
            SchedyWidgetView(entry: entry.entry)
        }
        .configurationDisplayName(String(localized: "widget.title", defaultValue: "Today's Classes"))
        .description(String(localized: "widget.description", defaultValue: "Choose a timetable to see the date and next two classes using its assigned time preset."))
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

struct SchedyWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SchedyWidgetSmallView(entry: sampleEntry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            SchedyWidgetMediumView(entry: sampleEntry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}
