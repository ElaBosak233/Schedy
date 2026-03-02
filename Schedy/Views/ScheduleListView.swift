//
//  ScheduleListView.swift
//  schedy
//
//  课程表列表：切换当前课程表、添加、编辑（名称 / 学期第一天 / 绑定时间段）
//

import SwiftData
import SwiftUI

struct ScheduleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Schedule.name) private var schedules: [Schedule]
    @AppStorage("activeScheduleName") private var activeScheduleName: String = "我的课程表"

    @State private var showAddSchedule = false
    @State private var scheduleToEdit: Schedule?

    private var presetSheetBinding: Binding<Bool> {
        Binding(
            get: { scheduleToEdit != nil },
            set: { if !$0 { scheduleToEdit = nil } }
        )
    }

    var body: some View {
        List {
            Section {
                ForEach(schedules, id: \.name) { schedule in
                    scheduleRow(schedule)
                }
            } header: {
                Text("课程表")
            } footer: {
                Text("点击选择当前使用的课程表。每张课程表可单独设置名称与学期第一天；时间段在「时间段」中全局切换。")
            }
        }
        .navigationTitle("课程表")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSchedule = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showAddSchedule) {
            ScheduleEditSheet(schedule: nil)
        }
        .sheet(isPresented: presetSheetBinding) {
            if let s = scheduleToEdit {
                ScheduleEditSheet(schedule: s)
            }
        }
        .onAppear {
            seedDefaultScheduleIfNeeded(modelContext: modelContext)
            if activeScheduleName.isEmpty {
                activeScheduleName = schedules.first?.name ?? "我的课程表"
            }
            // 每次进入课程表列表都同步到小组件，保证名称与课程是最新的
            refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
            scheduleCourseReminders(modelContext: modelContext, activeScheduleName: activeScheduleName)
        }
        .onChange(of: activeScheduleName) { _, newName in
            refreshWidgetData(modelContext: modelContext, activeScheduleName: newName)
            scheduleCourseReminders(modelContext: modelContext, activeScheduleName: newName)
        }
    }

    private func scheduleRow(_ schedule: Schedule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.name)
                    .font(.headline)
                Text(semesterStartText(schedule.semesterStartDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if schedule.name == activeScheduleName {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            activeScheduleName = schedule.name
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if schedules.count > 1 {
                Button("删除", systemImage: "trash", role: .destructive) {
                    deleteSchedule(schedule)
                }
                .tint(.red)
            }
            Button("编辑", systemImage: "pencil") {
                scheduleToEdit = schedule
            }
        }
    }

    private func semesterStartText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        f.locale = Locale(identifier: "zh_CN")
        return "学期开始：\(f.string(from: date))"
    }

    private func deleteSchedule(_ schedule: Schedule) {
        if schedule.name == activeScheduleName {
            if let other = schedules.first(where: { $0.name != schedule.name }) {
                activeScheduleName = other.name
            }
        }
        modelContext.delete(schedule)
        try? modelContext.save()
    }
}

// MARK: - 新建/编辑课程表
struct ScheduleEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("activeScheduleName") private var activeScheduleName: String = "我的课程表"

    let schedule: Schedule?

    @State private var name: String = ""
    @State private var semesterStartDate: Date = Date()

    private var isEditing: Bool { schedule != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("课程表名称", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section("本学期第一天") {
                    DatePicker("学期第一天", selection: $semesterStartDate, displayedComponents: .date)
                }
            }
            .navigationTitle(isEditing ? "编辑课程表" : "新建课程表")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let s = schedule {
                    name = s.name
                    semesterStartDate = s.semesterStartDate
                } else {
                    name = ""
                    semesterStartDate = defaultSemesterStartForPicker()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func defaultSemesterStartForPicker() -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysUntilMonday = weekday == 1 ? 1 : (weekday == 2 ? 0 : (9 - weekday))
        return cal.date(byAdding: .day, value: daysUntilMonday, to: today) ?? today
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }

        let wasActiveSchedule = schedule?.name == activeScheduleName

        if let s = schedule {
            s.name = n
            s.semesterStartDate = semesterStartDate
        } else {
            let newSchedule = Schedule(name: n, semesterStartDate: semesterStartDate)
            modelContext.insert(newSchedule)
        }
        try? modelContext.save()

        // 若编辑的是当前选中的课程表，同步 AppStorage 并刷新小组件，否则小组件会继续用旧名称查不到数据
        if wasActiveSchedule {
            activeScheduleName = n
            refreshWidgetData(modelContext: modelContext, activeScheduleName: n)
            scheduleCourseReminders(modelContext: modelContext, activeScheduleName: n)
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ScheduleListView()
    }
    .modelContainer(for: [Schedule.self, Course.self, CourseReschedule.self, TimeSlotPreset.self, TimeSlotItem.self], inMemory: true)
}
