//
//  TodayView.swift
//  schedy
//
//  「今天」视图：按卡片列表显示今天的课程
//

import SwiftData
import SwiftUI

private let maxWeeks = 25

/// 今日课程卡片：课程名、节次时间、老师、地点，与课程表一致的配色
private struct TodayCourseCard: View {
    let course: Course
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
                    Text("第 \(course.periodIndex)–\(course.effectivePeriodEnd) 节")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(cardAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(cardAccent.opacity(0.15))
                        .clipShape(Capsule())
                }

                HStack(spacing: 16) {
                    Label(course.teacher, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(course.location, systemImage: "mappin.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    @AppStorage("activeScheduleName") private var activeScheduleName: String = "我的课程表"

    private var activeSchedule: Schedule? {
        schedules.first { $0.name == activeScheduleName } ?? schedules.first
    }

    private var activePreset: TimeSlotPreset? {
        activeSchedule?.timeSlotPreset
    }

    private var sortedSlots: [TimeSlotItem] {
        guard let p = activePreset else { return [] }
        return p.slots.sorted { $0.periodIndex < $1.periodIndex }
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
        return min(max(1, week), maxWeeks)
    }

    /// 今天、当前周有课的课程，按节次排序
    private var todayCourses: [Course] {
        guard let schedule = activeSchedule else { return [] }
        return schedule.courses
            .filter { $0.dayOfWeek == todayDayOfWeek && $0.appliesToWeek(currentWeek) }
            .sorted { $0.periodIndex < $1.periodIndex }
    }

    /// 某节课的时间范围文案（从预设中取起止节的时间）
    private func timeRangeString(for course: Course) -> String {
        let startPeriod = course.periodIndex
        let endPeriod = course.effectivePeriodEnd
        let startSlot = sortedSlots.first { $0.periodIndex == startPeriod }
        let endSlot = sortedSlots.first { $0.periodIndex == endPeriod }
        if let start = startSlot, let end = endSlot {
            return "\(start.startTimeString) ~ \(end.endTimeString)"
        }
        return "第 \(startPeriod)–\(endPeriod) 节"
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
                if todayCourses.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            Text(todayDateString)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 4)

                            ForEach(todayCourses, id: \.id) { course in
                                TodayCourseCard(
                                    course: course,
                                    timeRangeString: timeRangeString(for: course)
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
        .modelContainer(for: [Schedule.self, Course.self, TimeSlotPreset.self, TimeSlotItem.self], inMemory: true)
}
