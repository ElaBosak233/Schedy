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
    @AppStorage(ScheduleDisplayKeys.activeScheduleName) private var activeScheduleName: String = String(localized: "schedule.default.name", defaultValue: "My Timetable")

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
                Text(String(localized: "navigation.timetable.title", defaultValue: "Timetable"))
            } footer: {
                Text(String(localized: "schedule.list.description", defaultValue: "Tap a timetable to select it. Each timetable has its own name, semester start date, and time preset. Widgets use the selected timetable's preset."))
            }
        }
        .schedyPageStyle(navigationBackground: .automatic)
        .navigationTitle(String(localized: "navigation.timetable.title", defaultValue: "Timetable"))
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
                activeScheduleName = schedules.first?.name ?? String(localized: "schedule.default.name", defaultValue: "My Timetable")
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
                Button(String(localized: "common.action.delete", defaultValue: "Delete"), systemImage: "trash", role: .destructive) {
                    deleteSchedule(schedule)
                }
                .tint(.red)
            }
            Button(String(localized: "common.action.edit", defaultValue: "Edit"), systemImage: "pencil") {
                scheduleToEdit = schedule
            }
        }
    }

    private func semesterStartText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        return String(localized: "schedule.semester.start_summary", defaultValue: "Semester starts: \(f.string(from: date))")
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
    @AppStorage(ScheduleDisplayKeys.activeScheduleName) private var activeScheduleName: String = String(localized: "schedule.default.name", defaultValue: "My Timetable")
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
                Section(String(localized: "common.field.name", defaultValue: "Name")) {
                    TextField(String(localized: "schedule.field.name", defaultValue: "Timetable Name"), text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section(String(localized: "schedule.semester.section_title", defaultValue: "Semester Start")) {
                    DatePicker(String(localized: "schedule.semester.start_date", defaultValue: "Semester Start Date"), selection: $semesterStartDate, displayedComponents: .date)
                }
                Section {
                    Picker(String(localized: "settings.presets.title", defaultValue: "Time Presets"), selection: presetPickerBinding) {
                        Text(String(localized: "preset.selection.default", defaultValue: "Use Default")).tag("")
                        ForEach(presets, id: \.name) { p in
                            Text(p.name).tag(p.name)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text(String(localized: "settings.presets.title", defaultValue: "Time Presets"))
                } footer: {
                    Text(String(localized: "schedule.preset.description", defaultValue: "This preset is used in the timetable grid and widgets. Leave unset to use the app default."))
                }
                if isEditing, let s = schedule {
                    Section {
                        Toggle(String(localized: "notification.course.title", defaultValue: "Class Reminders"), isOn: Binding(
                            get: { s.notificationsEnabled },
                            set: { s.notificationsEnabled = $0 }
                        ))
                    } footer: {
                        Text(String(localized: "schedule.reminders.description", defaultValue: "Get a reminder 15 minutes before each class. Enable reminders for multiple timetables if you teach or attend several groups."))
                    }
                }
            }
            .schedyPageStyle()
            .navigationTitle(isEditing ? String(localized: "schedule.edit.title", defaultValue: "Edit Timetable") : String(localized: "schedule.create.title", defaultValue: "New Timetable"))
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
                    Button(String(localized: "common.action.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.action.save", defaultValue: "Save")) {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert(String(localized: "validation.name_conflict.title", defaultValue: "Name Already Exists"), isPresented: $nameConflict) {
                Button(String(localized: "common.action.ok_short", defaultValue: "OK")) {}
            } message: {
                Text(String(localized: "validation.schedule.name_conflict", defaultValue: "A timetable with this name already exists. Choose another name."))
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
