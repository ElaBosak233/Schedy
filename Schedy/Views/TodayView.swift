//
//  TodayView.swift
//  Schedy
//
//  「今天」Tab：根据当前选中的课表与时间段，用 EffectiveCourseService 取当日有效课次并以卡片列表展示。
//

import SwiftData
import SwiftUI

/// 今日课程卡片：课程名、节次时间、老师、地点，与课程表一致的配色（支持调课后的节次）
private struct TodayCourseCard: View {
    let course: Course
    /// 本次显示的节次范围（正常排课或调课后的新节次）
    let periodStart: Int
    let periodEnd: Int
    let timeRangeString: String

    private var cardAccent: Color {
        TodayView.MacaronPalette.color(forCourseName: course.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部色条
            RoundedRectangle(cornerRadius: 0)
                .fill(cardAccent.gradient)
                .frame(height: 4)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(course.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text(timeRangeString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text("第 \(periodStart)–\(periodEnd) 节")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(cardAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(cardAccent.opacity(0.15))
                        .clipShape(Capsule())
                }

                HStack(spacing: 16) {
                    if let t = course.teacher, !t.isEmpty {
                        Label(t, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let loc = course.location, !loc.isEmpty {
                        Label(loc, systemImage: "mappin.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let credits = course.credits {
                        Label(String(format: "%g", credits) + " 学分", systemImage: "number.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Schedule.name) private var schedules: [Schedule]
    @Query(sort: \TimeSlotPreset.name) private var presets: [TimeSlotPreset]
    @AppStorage(ScheduleDisplayKeys.activeScheduleName) private var activeScheduleName: String = "我的课程表"
    @AppStorage(ScheduleDisplayKeys.activeTimeSlotPresetName) private var activeTimeSlotPresetName: String = ""

    private var activeSchedule: Schedule? {
        schedules.first { $0.name == activeScheduleName } ?? schedules.first
    }

    /// 当前课表绑定的时间段；未绑定时使用全局默认预设
    private var activePreset: TimeSlotPreset? {
        if let bound = activeSchedule?.timeSlotPreset { return bound }
        if !activeTimeSlotPresetName.isEmpty {
            return presets.first { $0.name == activeTimeSlotPresetName }
        }
        return presets.first
    }

    private var sortedSlots: [TimeSlotItem] {
        guard let p = activePreset else { return [] }
        return (p.slots ?? []).sorted { $0.periodIndex < $1.periodIndex }
    }

    /// 当前是周几（1=周一 … 7=周日），与 Course.dayOfWeek 一致
    private var todayDayOfWeek: Int {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: Date()) // 1=Sun, 2=Mon, ...
        return weekday == 1 ? 7 : (weekday - 1)
    }

    /// 当前是第几周（基于学期第一天）
    private var currentWeek: Int {
        guard let schedule = activeSchedule else { return 1 }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.startOfDay(for: schedule.semesterStartDate)
        if today < start { return 1 }
        let days = cal.dateComponents([.day], from: start, to: today).day ?? 0
        let week = days / 7 + 1
        return min(max(1, week), activeSchedule?.effectiveMaxWeeks ?? 25)
    }

    /// 今天、当前周的有效课次（含调课：排除被调出、包含被调入），按节次排序
    @State private var effectiveOccurrences: [EffectiveCourseOccurrence] = []

    /// 从时间段取节次对应的时间范围文案
    private func timeRangeString(periodStart: Int, periodEnd: Int) -> String {
        let startSlot = sortedSlots.first { $0.periodIndex == periodStart }
        let endSlot = sortedSlots.first { $0.periodIndex == periodEnd }
        if let start = startSlot, let end = endSlot {
            return "\(start.startTimeString) ~ \(end.endTimeString)"
        }
        return "第 \(periodStart)–\(periodEnd) 节"
    }

    /// 今日日期文案
    private var todayDateString: String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            Group {
                if effectiveOccurrences.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            Text(todayDateString)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 4)

                            ForEach(effectiveOccurrences) { occurrence in
                                TodayCourseCard(
                                    course: occurrence.course,
                                    periodStart: occurrence.periodStart,
                                    periodEnd: occurrence.periodEnd,
                                    timeRangeString: timeRangeString(periodStart: occurrence.periodStart, periodEnd: occurrence.periodEnd)
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .padding(.bottom, 24)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("今天")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                seedDefaultScheduleIfNeeded(modelContext: modelContext)
                if activeScheduleName.isEmpty {
                    activeScheduleName = schedules.first?.name ?? "我的课程表"
                }
            }
            .task(id: "\(activeSchedule?.name ?? "")_\(currentWeek)_\(todayDayOfWeek)") {
                guard let schedule = activeSchedule else {
                    effectiveOccurrences = []
                    return
                }
                var descriptor = FetchDescriptor<Course>()
                descriptor.relationshipKeyPathsForPrefetching = [\Course.reschedules]
                let allCourses = (try? modelContext.fetch(descriptor)) ?? []
                let scheduleID = schedule.persistentModelID
                let courses = allCourses.filter { $0.schedule?.persistentModelID == scheduleID }
                effectiveOccurrences = EffectiveCourseService.effectiveCourseOccurrences(
                    courses: courses,
                    week: currentWeek,
                    dayOfWeek: todayDayOfWeek
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("今天没有课")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            Text("在课程表中添加课程后，有课的日子会在这里显示")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 与 ScheduleGridView 一致的课程名配色（供 TodayCourseCard 使用）
    enum MacaronPalette {
        static let colors: [Color] = [
            Color(red: 214/255.0, green: 69/255.0, blue: 80/255.0),
            Color(red: 230/255.0, green: 126/255.0, blue: 34/255.0),
            Color(red: 197/255.0, green: 157/255.0, blue: 15/255.0),
            Color(red: 46/255.0, green: 139/255.0, blue: 87/255.0),
            Color(red: 31/255.0, green: 175/255.0, blue: 139/255.0),
            Color(red: 47/255.0, green: 128/255.0, blue: 237/255.0),
            Color(red: 27/255.0, green: 108/255.0, blue: 168/255.0),
            Color(red: 123/255.0, green: 97/255.0, blue: 255/255.0),
            Color(red: 91/255.0, green: 79/255.0, blue: 207/255.0),
            Color(red: 214/255.0, green: 51/255.0, blue: 132/255.0),
            Color(red: 141/255.0, green: 85/255.0, blue: 36/255.0),
        ]

        private static func stableHash(for string: String) -> Int {
            var hash = 5381
            for codeUnit in string.utf8 {
                hash = ((hash << 5) &+ hash) &+ Int(codeUnit)
            }
            return hash
        }

        static func color(forCourseName name: String) -> Color {
            let index = abs(stableHash(for: name)) % colors.count
            return colors[index]
        }
    }
}

#Preview {
    TodayView()
        .modelContainer(for: [Schedule.self, Course.self, CourseReschedule.self, TimeSlotPreset.self, TimeSlotItem.self], inMemory: true)
}
