//
//  CourseEditSheet.swift
//  schedy
//
//  添加/编辑课程：课程名、时间（周次范围/单双周/星期/节次）、老师、地点
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
    @AppStorage("activeScheduleName") private var activeScheduleName: String = "我的课程表"

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
    @State private var weekParity: WeekParity
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
        return p.slots.sorted { $0.periodIndex < $1.periodIndex }
    }

    /// 结束节可选范围：起始节及之后
    private var endPeriodOptions: [TimeSlotItem] {
        sortedPeriods.filter { $0.periodIndex >= periodStart }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("课程信息") {
                    TextField("课程名", text: $name)
                    TextField("任课老师", text: $teacher)
                    TextField("地点", text: $location)
                    TextField("学分", text: $creditsText)
                        .keyboardType(.decimalPad)
                }

                Section("上课时间") {
                    Group {
                        Text("周次范围")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach($weekRanges) { $range in
                            HStack(spacing: 12) {
                                Picker("起", selection: $range.start) {
                                    ForEach(1...25, id: \.self) { w in
                                        Text("第 \(w) 周").tag(w)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                Text("至")
                                Picker("止", selection: $range.end) {
                                    ForEach(1...25, id: \.self) { w in
                                        Text("第 \(w) 周").tag(w)
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
                            Label("添加一段周次", systemImage: "plus.circle")
                        }
                    }

                    Picker("单双周", selection: $weekParity) {
                        ForEach(WeekParity.allCases, id: \.rawValue) { p in
                            Text(p.displayName).tag(p)
                        }
                    }

                    Picker("星期", selection: $dayOfWeek) {
                        ForEach(1...7, id: \.self) { d in
                            Text(dayName(d)).tag(d)
                        }
                    }

                    Picker("起始节", selection: $periodStart) {
                        ForEach(sortedPeriods, id: \.periodIndex) { slot in
                            Text("第 \(slot.periodIndex) 节 (\(slot.timeRangeString))")
                                .tag(slot.periodIndex)
                        }
                        if sortedPeriods.isEmpty {
                            Text("请先在设置中配置时间段").tag(1)
                        }
                    }
                    .onChange(of: periodStart) { _, newStart in
                        if periodEnd < newStart { periodEnd = newStart }
                    }

                    Picker("结束节", selection: $periodEnd) {
                        ForEach(endPeriodOptions, id: \.periodIndex) { slot in
                            Text("第 \(slot.periodIndex) 节 (\(slot.timeRangeString))")
                                .tag(slot.periodIndex)
                        }
                        if endPeriodOptions.isEmpty {
                            Text("请先在设置中配置时间段").tag(1)
                        }
                    }
                    .disabled(sortedPeriods.isEmpty)
                }
            }
            .navigationTitle(isEditing ? "编辑课程" : "添加课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("删除", role: .destructive) {
                            delete()
                        }
                    }
                }
            }
        }
    }

    private func dayName(_ d: Int) -> String {
        let names = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        return names.indices.contains(d) ? names[d] : "?"
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
        scheduleCourseReminders(modelContext: modelContext, activeScheduleName: activeScheduleName)
        dismiss()
    }

    private func delete() {
        if let c = course {
            modelContext.delete(c)
            try? modelContext.save()
        }
        refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
        scheduleCourseReminders(modelContext: modelContext, activeScheduleName: activeScheduleName)
        dismiss()
    }
}

#Preview {
    CourseEditSheet(course: nil, schedule: nil, preset: nil, defaultWeek: 1, defaultDay: 1, defaultPeriod: 1)
        .modelContainer(for: [Schedule.self, Course.self, CourseReschedule.self, TimeSlotPreset.self, TimeSlotItem.self], inMemory: true)
}
