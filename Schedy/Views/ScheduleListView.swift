//
//  ScheduleListView.swift
//  Schedy
//
//  设置下的课程表列表：选择当前课表、新建、编辑名称/学期第一天/绑定时间段、复制、删除。
//

import SwiftData
import SwiftUI

struct ScheduleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Schedule.name) private var schedules: [Schedule]
    @AppStorage(ScheduleDisplayKeys.activeScheduleName) private var activeScheduleName: String = "我的课程表"

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
                Text("点击选择当前使用的课程表。每张课程表可单独设置名称、学期第一天与绑定的时间段；小组件选哪张课表即使用该课表的时间段。")
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
            refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
            scheduleCourseReminders(modelContext: modelContext)
        }
        .onChange(of: activeScheduleName) { _, newName in
            refreshWidgetData(modelContext: modelContext, activeScheduleName: newName)
            scheduleCourseReminders(modelContext: modelContext)
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
    @AppStorage(ScheduleDisplayKeys.activeScheduleName) private var activeScheduleName: String = "我的课程表"
    @AppStorage(ScheduleDisplayKeys.activeTimeSlotPresetName) private var activeTimeSlotPresetName: String = ""
    @Query(sort: \TimeSlotPreset.name) private var presets: [TimeSlotPreset]
    @Query private var allSchedules: [Schedule]

    let schedule: Schedule?

    @State private var name: String = ""
    @State private var semesterStartDate: Date = Date()
    /// 新建课表时选择的时间预设名称（编辑时直接读写 schedule.timeSlotPreset）
    @State private var selectedPresetName: String = ""
    @State private var nameConflict = false

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
                Section {
                    Picker("时间段", selection: presetPickerBinding) {
                        Text("使用默认").tag("")
                        ForEach(presets, id: \.name) { p in
                            Text(p.name).tag(p.name)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("时间段")
                } footer: {
                    Text("该课表在网格与小组件中显示时使用此时间段。未设置则使用 App 默认。")
                }
                if isEditing, let s = schedule {
                    Section {
                        Toggle("课程提醒", isOn: Binding(
                            get: { s.notificationsEnabled },
                            set: { s.notificationsEnabled = $0 }
                        ))
                    } footer: {
                        Text("开启后，该课表中有课的时间会提前 15 分钟收到提醒。多张课表可同时开启，适合带多个班的老师。")
                    }
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
                    semesterStartDate = defaultSemesterStartDate()
                    selectedPresetName = activeTimeSlotPresetName.isEmpty ? (presets.first?.name ?? "") : activeTimeSlotPresetName
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
            .alert("名称已存在", isPresented: $nameConflict) {
                Button("好") {}
            } message: {
                Text("已有同名课程表，请使用其他名称。")
            }
        }
    }

    /// 时间段 Picker 的绑定：编辑时读写 schedule.timeSlotPreset，新建时读写 selectedPresetName
    private var presetPickerBinding: Binding<String> {
        if let s = schedule {
            return Binding(
                get: { s.timeSlotPreset?.name ?? "" },
                set: { name in
                    s.timeSlotPreset = name.isEmpty ? nil : presets.first { $0.name == name }
                }
            )
        }
        return $selectedPresetName
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }

        // 重名检查：排除自身（编辑时）
        let conflict = allSchedules.contains { $0.name == n && $0 !== schedule }
        guard !conflict else { nameConflict = true; return }

        let wasActiveSchedule = schedule?.name == activeScheduleName

        if let s = schedule {
            s.name = n
            s.semesterStartDate = semesterStartDate
        } else {
            let newSchedule = Schedule(name: n, semesterStartDate: semesterStartDate)
            newSchedule.timeSlotPreset = selectedPresetName.isEmpty ? nil : (presets.first { $0.name == selectedPresetName })
            modelContext.insert(newSchedule)
        }
        try? modelContext.save()

        if wasActiveSchedule {
            activeScheduleName = n
        }
        refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
        scheduleCourseReminders(modelContext: modelContext)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ScheduleListView()
    }
    .modelContainer(for: [Schedule.self, Course.self, CourseReschedule.self, TimeSlotPreset.self, TimeSlotItem.self], inMemory: true)
}
