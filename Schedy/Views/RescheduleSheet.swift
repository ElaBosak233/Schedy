//
//  RescheduleSheet.swift
//  Schedy
//
//  单次调课：将「来源周」的这一次课调至「目标周」的某天某节（如第1周周一 → 第2周周四第x节）。
//

import SwiftData
import SwiftUI

private func dayName(_ day: Int) -> String {
    let names = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    guard day >= 1, day <= 7 else { return "?" }
    return names[day]
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
        return p.slots.sorted { $0.periodIndex < $1.periodIndex }
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
                    Text("将 第 \(sourceWeek) 周 的「\(course.name)」（\(course.dayOfWeekName) 第 \(course.periodIndex)–\(course.effectivePeriodEnd) 节）调至下方选择的时间，课时数保持不变。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("调至") {
                    Picker("周次", selection: $newWeek) {
                        ForEach(targetWeekOptions, id: \.self) { w in
                            Text("第 \(w) 周").tag(w)
                        }
                    }

                    Picker("星期", selection: $newDayOfWeek) {
                        ForEach(1...7, id: \.self) { d in
                            Text(dayName(d)).tag(d)
                        }
                    }

                    Picker("起始节", selection: $newPeriodStart) {
                        ForEach(startPeriodOptions, id: \.periodIndex) { slot in
                            Text("第 \(slot.periodIndex) 节 (\(slot.timeRangeString))")
                                .tag(slot.periodIndex)
                        }
                        if startPeriodOptions.isEmpty {
                            Text("请先在设置中配置时间段").tag(1)
                        }
                    }
                    .disabled(sortedPeriods.isEmpty)

                    if periodSpan > 1 {
                        HStack {
                            Text("结束节")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("第 \(computedNewPeriodEnd) 节（共 \(periodSpan) 节）")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            undoReschedule()
                        } label: {
                            Label("撤销该次调课", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
            .navigationTitle("调课")
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
