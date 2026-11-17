//
//  CourseEditSheet.swift
//  Schedy
//
//  添加/编辑课程 Sheet：课程名、周次范围与单双周、星期与节次、教师、地点、学分。
//

import SwiftData
import SwiftUI

/// 可编辑的一条周次范围（用于列表展示与增删）
private struct EditableWeekRange: Identifiable {
    let id = UUID()
    var start: Int
    var end: Int
}

struct CourseEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ScheduleDisplayKeys.activeScheduleName) private var activeScheduleName: String = String(localized: "schedule.default.name", defaultValue: "My Timetable")

    let course: Course?
    let schedule: Schedule?
    let preset: TimeSlotPreset?
    var defaultWeek: Int?
    var defaultDay: Int?
    var defaultPeriod: Int?

    @State private var name = ""
    @State private var teacher = ""
    @State private var location = ""
    @State private var creditsText = ""  // 学分，空表示未填
    @State private var weekRanges: [EditableWeekRange]
    @State private var weekParity: Course.WeekParity
    @State private var dayOfWeek: Int
    @State private var periodStart: Int
    @State private var periodEnd: Int

    private var isEditing: Bool { course != nil }

    init(
        course: Course?,
        schedule: Schedule? = nil,
        preset: TimeSlotPreset?,
        defaultWeek: Int? = nil,
        defaultDay: Int? = nil,
        defaultPeriod: Int? = nil
    ) {
        self.course = course
        self.schedule = schedule
        self.preset = preset
        self.defaultWeek = defaultWeek
        self.defaultDay = defaultDay
        self.defaultPeriod = defaultPeriod

        if let c = course {
            _name = State(initialValue: c.name)
            _teacher = State(initialValue: c.teacher ?? "")
            _location = State(initialValue: c.location ?? "")
            _creditsText = State(initialValue: c.credits.map { String(format: "%g", $0) } ?? "")
            _weekRanges = State(initialValue: Self.parseRanges(c.weekRangesString ?? "", fallbackWeek: c.weekIndex))
            _weekParity = State(initialValue: c.weekParity)
            _dayOfWeek = State(initialValue: c.dayOfWeek)
            _periodStart = State(initialValue: c.periodIndex)
            _periodEnd = State(initialValue: c.effectivePeriodEnd)
        } else {
            _name = State(initialValue: "")
            _teacher = State(initialValue: "")
            _location = State(initialValue: "")
            _creditsText = State(initialValue: "")
            let w = defaultWeek ?? 1
            _weekRanges = State(initialValue: [EditableWeekRange(start: w, end: w)])
            _weekParity = State(initialValue: .all)
            _dayOfWeek = State(initialValue: defaultDay ?? 1)
            let p = defaultPeriod ?? 1
            _periodStart = State(initialValue: p)
            _periodEnd = State(initialValue: p)
        }
    }

    private static func parseRanges(_ s: String, fallbackWeek: Int) -> [EditableWeekRange] {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            let w = max(1, fallbackWeek)
            return [EditableWeekRange(start: w, end: w)]
        }
        var out: [EditableWeekRange] = []
        let parts = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts {
            let nums = part.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if nums.count >= 2 {
                let a = max(1, nums[0])
                let b = max(a, nums[1])
                out.append(EditableWeekRange(start: a, end: b))
            } else if let single = nums.first {
                let w = max(1, single)
                out.append(EditableWeekRange(start: w, end: w))
            }
        }
        return out.isEmpty ? [EditableWeekRange(start: max(1, fallbackWeek), end: max(1, fallbackWeek))] : out
    }

    private static func formatRanges(_ ranges: [EditableWeekRange]) -> String {
        ranges
            .map { r in
                let a = max(1, r.start)
                let b = max(a, r.end)
                return a == b ? "\(a)" : "\(a)-\(b)"
            }
            .joined(separator: ",")
    }

    private var sortedPeriods: [TimeSlotItem] {
        guard let p = preset else { return [] }
        return (p.slots ?? []).sorted { $0.periodIndex < $1.periodIndex }
    }

    /// 结束节可选范围：起始节及之后
    private var endPeriodOptions: [TimeSlotItem] {
        sortedPeriods.filter { $0.periodIndex >= periodStart }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "course.details.title", defaultValue: "Course Details")) {
                    TextField(String(localized: "course.field.name", defaultValue: "Course Name"), text: $name)
                    TextField(String(localized: "course.field.teacher", defaultValue: "Teacher"), text: $teacher)
                    TextField(String(localized: "course.field.location", defaultValue: "Location"), text: $location)
                    TextField(String(localized: "course.field.credits", defaultValue: "Credits"), text: $creditsText)
                        .keyboardType(.decimalPad)
                }

                Section(String(localized: "course.schedule.title", defaultValue: "Class Schedule")) {
                    Group {
                        Text(String(localized: "course.field.week_ranges", defaultValue: "Week Ranges"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach($weekRanges) { $range in
                            HStack(spacing: 12) {
                                Picker(String(localized: "course.week_range.start", defaultValue: "Start"), selection: $range.start) {
                                    ForEach(1...25, id: \.self) { w in
                                        Text(String(localized: "schedule.week.label", defaultValue: "Week \(w)")).tag(w)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                Text(String(localized: "course.week_range.separator", defaultValue: "to"))
                                Picker(String(localized: "course.week_range.end", defaultValue: "End"), selection: $range.end) {
                                    ForEach(1...25, id: \.self) { w in
                                        Text(String(localized: "schedule.week.label", defaultValue: "Week \(w)")).tag(w)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .onChange(of: range.start) { _, new in
                                    if range.end < new { range.end = new }
                                }
                                if weekRanges.count > 1 {
                                    Button(role: .destructive) {
                                        weekRanges.removeAll { $0.id == range.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                    }
                                }
                            }
                        }
                        Button {
                            let lastEnd = weekRanges.last?.end ?? 1
                            weekRanges.append(EditableWeekRange(start: lastEnd, end: min(25, lastEnd + 1)))
                        } label: {
                            Label(String(localized: "course.week_range.add_action", defaultValue: "Add Week Range"), systemImage: "plus.circle")
                        }
                    }

                    Picker(String(localized: "course.field.week_pattern", defaultValue: "Week Pattern"), selection: $weekParity) {
                        ForEach(Course.WeekParity.allCases, id: \.rawValue) { p in
                            Text(p.displayName).tag(p)
                        }
                    }

                    Picker(String(localized: "course.field.weekday", defaultValue: "Weekday"), selection: $dayOfWeek) {
                        ForEach(1...7, id: \.self) { d in
                            Text(dayName(d)).tag(d)
                        }
                    }

                    Picker(String(localized: "course.field.start_period", defaultValue: "Start Period"), selection: $periodStart) {
                        ForEach(sortedPeriods, id: \.periodIndex) { slot in
                            Text(String(localized: "course.period.time_label", defaultValue: "Period \(slot.periodIndex) (\(slot.timeRangeString))"))
                                .tag(slot.periodIndex)
                        }
                        if sortedPeriods.isEmpty {
                            Text(String(localized: "course.period.setup_required", defaultValue: "Set up period times in Settings first.")).tag(1)
                        }
                    }
                    .onChange(of: periodStart) { _, newStart in
                        if periodEnd < newStart { periodEnd = newStart }
                    }

                    Picker(String(localized: "course.field.end_period", defaultValue: "End Period"), selection: $periodEnd) {
                        ForEach(endPeriodOptions, id: \.periodIndex) { slot in
                            Text(String(localized: "course.period.time_label", defaultValue: "Period \(slot.periodIndex) (\(slot.timeRangeString))"))
                                .tag(slot.periodIndex)
                        }
                        if endPeriodOptions.isEmpty {
                            Text(String(localized: "course.period.setup_required", defaultValue: "Set up period times in Settings first.")).tag(1)
                        }
                    }
                    .disabled(sortedPeriods.isEmpty)
                }
            }
            .schedyPageStyle()
            .navigationTitle(isEditing ? String(localized: "course.edit.title", defaultValue: "Edit Course") : String(localized: "course.create.title", defaultValue: "Add Course"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.action.cancel", defaultValue: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.action.save", defaultValue: "Save")) {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(String(localized: "common.action.delete", defaultValue: "Delete"), role: .destructive) {
                            delete()
                        }
                    }
                }
            }
        }
    }

    private func dayName(_ d: Int) -> String {
        WeekdayLabels.name(forDayOfWeek: d)
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }

        var ranges = weekRanges
        if ranges.isEmpty { ranges = [EditableWeekRange(start: 1, end: 1)] }
        let rangesString = Self.formatRanges(ranges)
        let firstStart = ranges.first.map { max(1, $0.start) } ?? 1

        let endPeriod = periodEnd >= periodStart ? periodEnd : periodStart
        let creditsValue = Double(creditsText.trimmingCharacters(in: .whitespaces)).flatMap { $0 >= 0 ? $0 : nil }

        let teacherTrimmed = teacher.trimmingCharacters(in: .whitespaces)
        let locationTrimmed = location.trimmingCharacters(in: .whitespaces)
        if let c = course {
            c.name = n
            c.teacher = teacherTrimmed.isEmpty ? nil : teacherTrimmed
            c.location = locationTrimmed.isEmpty ? nil : locationTrimmed
            c.credits = creditsValue
            c.weekRangesString = rangesString
            c.weekParity = weekParity
            c.weekIndex = firstStart
            c.dayOfWeek = dayOfWeek
            c.periodIndex = periodStart
            c.periodEnd = endPeriod == periodStart ? nil : endPeriod
        } else {
            let newCourse = Course(
                name: n,
                teacher: teacherTrimmed.isEmpty ? nil : teacherTrimmed,
                location: locationTrimmed.isEmpty ? nil : locationTrimmed,
                credits: creditsValue,
                weekRangesString: rangesString,
                weekParity: weekParity,
                weekIndex: firstStart,
                dayOfWeek: dayOfWeek,
                periodIndex: periodStart,
                periodEnd: endPeriod == periodStart ? nil : endPeriod,
                schedule: schedule
            )
            modelContext.insert(newCourse)
        }
        try? modelContext.save()
        refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
        scheduleCourseReminders(modelContext: modelContext)
        dismiss()
    }

    private func delete() {
        if let c = course {
            modelContext.delete(c)
            try? modelContext.save()
        }
        refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
        scheduleCourseReminders(modelContext: modelContext)
        dismiss()
    }
}

#Preview {
    CourseEditSheet(course: nil, schedule: nil, preset: nil, defaultWeek: 1, defaultDay: 1, defaultPeriod: 1)
        .modelContainer(for: [Schedule.self, Course.self, CourseReschedule.self, TimeSlotPreset.self, TimeSlotItem.self], inMemory: true)
}
