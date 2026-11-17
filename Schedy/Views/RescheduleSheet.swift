//
//  RescheduleSheet.swift
//  Schedy
//
//  单次调课：将「来源周」的这一次课调至「目标周」的某天某节（如第1周周一 → 第2周周四第x节）。
//

import SwiftData
import SwiftUI

private func dayName(_ day: Int) -> String {
    WeekdayLabels.name(forDayOfWeek: day)
}

struct RescheduleSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let course: Course
    /// 来源周次（用户点进来时所在周），固定不可改
    let sourceWeek: Int
    let preset: TimeSlotPreset?
    /// 可选目标周上限，与课表 effectiveMaxWeeks 一致；未传时从 course.schedule 计算
    var maxWeeks: Int { course.schedule?.effectiveMaxWeeks ?? 25 }

    @State private var newWeek: Int
    @State private var newDayOfWeek: Int
    @State private var newPeriodStart: Int

    private var existing: CourseReschedule? { course.reschedule(forWeek: sourceWeek) }

    /// 课时数固定为课程原跨节数
    private var periodSpan: Int { course.periodSpan }
    private var computedNewPeriodEnd: Int { newPeriodStart + periodSpan - 1 }

    private var sortedPeriods: [TimeSlotItem] {
        guard let p = preset else { return [] }
        return (p.slots ?? []).sorted { $0.periodIndex < $1.periodIndex }
    }

    private var startPeriodOptions: [TimeSlotItem] {
        let maxStart = (sortedPeriods.map(\.periodIndex).max() ?? 20) - periodSpan + 1
        return sortedPeriods.filter { $0.periodIndex <= max(1, maxStart) }
    }

    /// 可选目标周：1 到 maxWeeks（与课表一致）
    private var targetWeekOptions: [Int] {
        Array(1...maxWeeks)
    }

    init(course: Course, week: Int, preset: TimeSlotPreset?) {
        self.course = course
        self.sourceWeek = week
        self.preset = preset
        if let r = course.reschedule(forWeek: week) {
            _newWeek = State(initialValue: r.effectiveNewWeek)
            _newDayOfWeek = State(initialValue: r.newDayOfWeek)
            _newPeriodStart = State(initialValue: r.newPeriodStart)
        } else {
            _newWeek = State(initialValue: week)
            _newDayOfWeek = State(initialValue: course.dayOfWeek)
            _newPeriodStart = State(initialValue: course.periodIndex)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(String(localized: "reschedule.description", defaultValue: "Move “\(course.name)” from week \(sourceWeek) (\(course.dayOfWeekName), periods \(course.periodIndex)–\(course.effectivePeriodEnd)) to the time below, keeping the same number of periods."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section(String(localized: "reschedule.destination.title", defaultValue: "Move To")) {
                    Picker(String(localized: "course.field.week", defaultValue: "Week"), selection: $newWeek) {
                        ForEach(targetWeekOptions, id: \.self) { w in
                            Text(String(localized: "schedule.week.label", defaultValue: "Week \(w)")).tag(w)
                        }
                    }

                    Picker(String(localized: "course.field.weekday", defaultValue: "Weekday"), selection: $newDayOfWeek) {
                        ForEach(1...7, id: \.self) { d in
                            Text(dayName(d)).tag(d)
                        }
                    }

                    Picker(String(localized: "course.field.start_period", defaultValue: "Start Period"), selection: $newPeriodStart) {
                        ForEach(startPeriodOptions, id: \.periodIndex) { slot in
                            Text(String(localized: "course.period.time_label", defaultValue: "Period \(slot.periodIndex) (\(slot.timeRangeString))"))
                                .tag(slot.periodIndex)
                        }
                        if startPeriodOptions.isEmpty {
                            Text(String(localized: "course.period.setup_required", defaultValue: "Set up period times in Settings first.")).tag(1)
                        }
                    }
                    .disabled(sortedPeriods.isEmpty)

                    if periodSpan > 1 {
                        HStack {
                            Text(String(localized: "course.field.end_period", defaultValue: "End Period"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(localized: "reschedule.period_summary", defaultValue: "Period \(computedNewPeriodEnd) (total: \(periodSpan))"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            undoReschedule()
                        } label: {
                            Label(String(localized: "reschedule.undo_action", defaultValue: "Undo This Reschedule"), systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
            .schedyPageStyle()
            .navigationTitle(String(localized: "reschedule.title", defaultValue: "Reschedule"))
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
                    .disabled(sortedPeriods.isEmpty)
                }
            }
        }
    }

    private func save() {
        let end = computedNewPeriodEnd
        if let r = existing {
            r.newWeek = newWeek
            r.newDayOfWeek = newDayOfWeek
            r.newPeriodStart = newPeriodStart
            r.newPeriodEnd = end
        } else {
            let r = CourseReschedule(
                course: course,
                schedule: course.schedule,
                week: sourceWeek,
                originalDayOfWeek: course.dayOfWeek,
                originalPeriodStart: course.periodIndex,
                originalPeriodEnd: course.effectivePeriodEnd,
                newWeek: newWeek,
                newDayOfWeek: newDayOfWeek,
                newPeriodStart: newPeriodStart,
                newPeriodEnd: end
            )
            modelContext.insert(r)
        }
        try? modelContext.save()
        dismiss()
    }

    private func undoReschedule() {
        guard let r = existing else { return }
        modelContext.delete(r)
        try? modelContext.save()
        dismiss()
    }
}
