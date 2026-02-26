//
//  ScheduleListView.swift
//  schedy
//
//  课程表列表：切换当前课程表、添加、编辑（名称 / 学期第一天 / 绑定时间段预设）
//

import SwiftData
import SwiftUI

struct ScheduleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Schedule.name) private var schedules: [Schedule]
    @Query(sort: \TimeSlotPreset.name) private var presets: [TimeSlotPreset]
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
                Text("点击选择当前使用的课程表。每张课程表可单独设置学期第一天和绑定的时间段预设。")
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
            ScheduleEditSheet(schedule: nil, presets: presets)
        }
        .sheet(isPresented: presetSheetBinding) {
            if let s = scheduleToEdit {
                ScheduleEditSheet(schedule: s, presets: presets)
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
                if let p = schedule.timeSlotPreset {
                    Text("时间段：\(p.name)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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
            Button("编辑", systemImage: "pencil") {
                scheduleToEdit = schedule
            }
            if schedules.count > 1 {
                Button("删除", systemImage: "trash", role: .destructive) {
                    deleteSchedule(schedule)
                }
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
    let presets: [TimeSlotPreset]

    @State private var name: String = ""
    @State private var semesterStartDate: Date = Date()
    @State private var selectedPresetName: String = ""

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
                Section("时间段预设") {
                    Picker("绑定预设", selection: $selectedPresetName) {
                        Text("无").tag("")
                        ForEach(presets, id: \.name) { p in
                            Text(p.name).tag(p.name)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑课程表" : "新建课程表")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let s = schedule {
                    name = s.name
                    semesterStartDate = s.semesterStartDate
                    selectedPresetName = s.timeSlotPreset?.name ?? ""
                } else {
                    name = ""
                    semesterStartDate = defaultSemesterStartForPicker()
                    selectedPresetName = presets.first?.name ?? ""
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

        let preset = presets.first { $0.name == selectedPresetName }
        let wasActiveSchedule = schedule?.name == activeScheduleName

        if let s = schedule {
            s.name = n
            s.semesterStartDate = semesterStartDate
            s.timeSlotPreset = preset
        } else {
            let newSchedule = Schedule(name: n, semesterStartDate: semesterStartDate, timeSlotPreset: preset)
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
    .modelContainer(for: [Schedule.self, Course.self, TimeSlotPreset.self, TimeSlotItem.self], inMemory: true)
}
