//
//  TimeSlotsSettingsView.swift
//  Schedy
//
//  时间段设置：预设列表（冬令时/夏令时等）、当前使用的预设、每预设内各节起止时间的增删改。
//

import SwiftData
import SwiftUI

struct TimeSlotsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeSlotPreset.name) private var presets: [TimeSlotPreset]
    @AppStorage(ScheduleDisplayKeys.activeTimeSlotPresetName) private var activeTimeSlotPresetName: String = ""
    @State private var showAddPreset = false
    @State private var presetToEdit: TimeSlotPreset?
    @State private var slotToEdit: TimeSlotItem?
    @State private var newPresetName = ""

    private var presetSheetBinding: Binding<Bool> {
        Binding(
            get: { presetToEdit != nil },
            set: { if !$0 { presetToEdit = nil } }
        )
    }

    private var slotSheetBinding: Binding<Bool> {
        Binding(
            get: { slotToEdit != nil },
            set: { if !$0 { slotToEdit = nil } }
        )
    }

    /// 当前选中的时间段（用于下方时间段明细）
    private var activePreset: TimeSlotPreset? {
        presets.first { $0.name == activeTimeSlotPresetName }
    }

    var body: some View {
        listContent
            .schedyPageStyle(navigationBackground: .automatic)
            .navigationTitle(String(localized: "settings.presets.title", defaultValue: "Time Presets"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .alert(String(localized: "preset.create.title", defaultValue: "New Time Preset"), isPresented: $showAddPreset) { addPresetAlertContent } message: { addPresetAlertMessage }
            .sheet(isPresented: presetSheetBinding) { presetEditSheetContent }
            .sheet(isPresented: slotSheetBinding) { slotEditSheetContent }
            .onAppear {
                seedDefaultPresetsIfNeeded(modelContext: modelContext)
                if activeTimeSlotPresetName.isEmpty, let first = presets.first {
                    activeTimeSlotPresetName = first.name
                }
            }
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            Section {
                ForEach(presets, id: \.name) { preset in
                    presetRow(preset: preset)
                }
            } header: {
                Text(String(localized: "settings.presets.title", defaultValue: "Time Presets"))
            } footer: {
                Text(String(localized: "preset.default.description", defaultValue: "Choose the default time preset for timetables without their own preset. Assign a preset to each timetable in Timetables. Manage period start and end times below."))
            }
            slotsDetailSection
        }
    }

    private func presetRow(preset: TimeSlotPreset) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.headline)
                Text(String(localized: "preset.periods.count", defaultValue: "\((preset.slots ?? []).count) time slots"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if preset.name == activeTimeSlotPresetName {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            activeTimeSlotPresetName = preset.name
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if presets.count > 1 {
                Button(String(localized: "common.action.delete", defaultValue: "Delete"), systemImage: "trash", role: .destructive) {
                    deletePreset(preset)
                }
                .tint(.red)
            }
            Button(String(localized: "common.action.edit", defaultValue: "Edit"), systemImage: "pencil") {
                presetToEdit = preset
            }
        }
    }

    @ViewBuilder
    private var slotsDetailSection: some View {
        if let preset = activePreset {
            Section {
                ForEach((preset.slots ?? []).sorted(by: { $0.periodIndex < $1.periodIndex }), id: \.persistentModelID) { slot in
                    NavigationLink {
                        TimeSlotEditView(slot: slot)
                    } label: {
                        HStack {
                            Text(String(localized: "course.period.label", defaultValue: "Period \(slot.periodIndex)"))
                            Spacer()
                            Text(slot.timeRangeString)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(String(localized: "common.action.delete", defaultValue: "Delete"), systemImage: "trash", role: .destructive) {
                            deleteSlot(slot, from: preset)
                        }
                        .tint(.red)
                        Button(String(localized: "common.action.edit", defaultValue: "Edit"), systemImage: "pencil") {
                            slotToEdit = slot
                        }
                    }
                }
                Button {
                    addSlot(to: preset)
                } label: {
                    Label(String(localized: "preset.period.add_action", defaultValue: "Add Period"), systemImage: "plus.circle")
                }
            } header: {
                Text(String(localized: "preset.periods.title", defaultValue: "\(preset.name) Period Times"))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showAddPreset = true
            } label: {
                Image(systemName: "plus.circle.fill")
            }
        }
    }

    @ViewBuilder
    private var addPresetAlertContent: some View {
        TextField(String(localized: "preset.field.name", defaultValue: "Time Preset Name"), text: $newPresetName)
            .textInputAutocapitalization(.words)
        Button(String(localized: "common.action.cancel", defaultValue: "Cancel"), role: .cancel) {
            newPresetName = ""
        }
        Button(String(localized: "common.action.ok", defaultValue: "OK")) {
            createPreset()
        }
        .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var addPresetAlertMessage: some View {
        Text(String(localized: "preset.name.placeholder", defaultValue: "For example: Winter, Summer, Custom"))
    }

    @ViewBuilder
    private var presetEditSheetContent: some View {
        if let p = presetToEdit {
            PresetRenameSheet(preset: p)
        }
    }

    @ViewBuilder
    private var slotEditSheetContent: some View {
        if let s = slotToEdit {
            NavigationStack {
                TimeSlotEditView(slot: s)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "common.action.done", defaultValue: "Done")) { slotToEdit = nil }
                        }
                    }
            }
        }
    }

    private func createPreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard !presets.contains(where: { $0.name == name }) else {
            newPresetName = ""
            return
        }

        let newPreset = TimeSlotPreset(name: name, slots: [])
        modelContext.insert(newPreset)
        for item in TimeSlotPreset.Default.winter() {
            let slot = TimeSlotItem(
                periodIndex: item.period,
                startHour: item.start.h,
                startMinute: item.start.m,
                endHour: item.end.h,
                endMinute: item.end.m
            )
            slot.preset = newPreset
            newPreset.slots = (newPreset.slots ?? []) + [slot]
            modelContext.insert(slot)
        }
        try? modelContext.save()
        newPresetName = ""
        showAddPreset = false
    }

    private func deletePreset(_ preset: TimeSlotPreset) {
        if activeTimeSlotPresetName == preset.name,
           let other = presets.first(where: { $0.name != preset.name }) {
            activeTimeSlotPresetName = other.name
        }
        for slot in preset.slots ?? [] {
            modelContext.delete(slot)
        }
        modelContext.delete(preset)
        try? modelContext.save()
    }

    private func addSlot(to preset: TimeSlotPreset) {
        let existingSlots = preset.slots ?? []
        let nextPeriodIndex = (existingSlots.map(\.periodIndex).max() ?? 0) + 1

        let (startH, startM, endH, endM): (Int, Int, Int, Int)
        if let lastSlot = existingSlots.sorted(by: { $0.periodIndex < $1.periodIndex }).last {
            let startMinutes = min(lastSlot.endHour * 60 + lastSlot.endMinute + 10, 23 * 60)
            let endMinutes = min(startMinutes + 40, 23 * 60 + 59)
            (startH, startM, endH, endM) = (startMinutes / 60, startMinutes % 60, endMinutes / 60, endMinutes % 60)
        } else {
            (startH, startM, endH, endM) = (8, 0, 8, 40)
        }

        let slot = TimeSlotItem(
            periodIndex: nextPeriodIndex,
            startHour: startH,
            startMinute: startM,
            endHour: endH,
            endMinute: endM
        )
        slot.preset = preset
        preset.slots = existingSlots + [slot]
        modelContext.insert(slot)
        try? modelContext.save()
    }

    private func deleteSlot(_ slot: TimeSlotItem, from preset: TimeSlotPreset) {
        let deletedPeriod = slot.periodIndex
        preset.slots = (preset.slots ?? []).filter { $0.periodIndex != deletedPeriod }
        for s in preset.slots ?? [] where s.periodIndex > deletedPeriod {
            s.periodIndex -= 1
        }
        renumberCoursesAndReschedules(afterDeletedPeriod: deletedPeriod)
        modelContext.delete(slot)
        try? modelContext.save()
    }

    /// 删除某节后，将引用该节及之后节次的课程、调课记录的节次全部减 1
    private func renumberCoursesAndReschedules(afterDeletedPeriod deletedPeriod: Int) {
        let courseDescriptor = FetchDescriptor<Course>()
        guard let allCourses = try? modelContext.fetch(courseDescriptor) else { return }
        for c in allCourses {
            if c.periodIndex > deletedPeriod {
                c.periodIndex -= 1
            }
            if let end = c.periodEnd {
                if end > deletedPeriod {
                    c.periodEnd = end - 1
                } else if end == deletedPeriod {
                    c.periodEnd = max(c.periodIndex, deletedPeriod - 1)
                    if c.periodEnd == c.periodIndex { c.periodEnd = nil }
                }
            }
        }
        let rescheduleDescriptor = FetchDescriptor<CourseReschedule>()
        guard let allReschedules = try? modelContext.fetch(rescheduleDescriptor) else { return }
        for r in allReschedules {
            if r.originalPeriodStart > deletedPeriod { r.originalPeriodStart -= 1 }
            if r.originalPeriodEnd > deletedPeriod {
                r.originalPeriodEnd -= 1
            } else if r.originalPeriodEnd == deletedPeriod {
                r.originalPeriodEnd = max(r.originalPeriodStart, deletedPeriod - 1)
            }
            if r.newPeriodStart > deletedPeriod { r.newPeriodStart -= 1 }
            if r.newPeriodEnd > deletedPeriod {
                r.newPeriodEnd -= 1
            } else if r.newPeriodEnd == deletedPeriod {
                r.newPeriodEnd = max(r.newPeriodStart, deletedPeriod - 1)
            }
        }
    }
}

// MARK: - 时间段重命名（用于编辑时间段名称）
struct PresetRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allPresets: [TimeSlotPreset]
    let preset: TimeSlotPreset
    @State private var name: String = ""
    @State private var nameConflict = false

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "preset.field.name", defaultValue: "Time Preset Name"), text: $name)
            }
            .schedyPageStyle()
            .navigationTitle(String(localized: "preset.edit.title", defaultValue: "Edit Time Preset"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { name = preset.name }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.action.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.action.save", defaultValue: "Save")) {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        let conflict = allPresets.contains { $0.name == n && $0 !== preset }
                        guard !conflict else { nameConflict = true; return }
                        preset.name = n
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert(String(localized: "validation.name_conflict.title", defaultValue: "Name Already Exists"), isPresented: $nameConflict) {
                Button(String(localized: "common.action.ok_short", defaultValue: "OK")) {}
            } message: {
                Text(String(localized: "validation.preset.name_conflict", defaultValue: "A time preset with this name already exists. Choose another name."))
            }
        }
    }
}

// MARK: - 单节时间段编辑
struct TimeSlotEditView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(ScheduleDisplayKeys.activeScheduleName) private var activeScheduleName: String = String(localized: "schedule.default.name", defaultValue: "My Timetable")
    @Bindable var slot: TimeSlotItem

    private func dateFrom(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }

    private func startDateBinding() -> Binding<Date> {
        Binding(
            get: { dateFrom(hour: slot.startHour, minute: slot.startMinute) },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                slot.startHour = comps.hour ?? 0
                slot.startMinute = comps.minute ?? 0
            }
        )
    }

    private func endDateBinding() -> Binding<Date> {
        Binding(
            get: { dateFrom(hour: slot.endHour, minute: slot.endMinute) },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                slot.endHour = comps.hour ?? 0
                slot.endMinute = comps.minute ?? 0
            }
        )
    }

    var body: some View {
        Form {
            Section(String(localized: "course.period.label", defaultValue: "Period \(slot.periodIndex)")) {
                DatePicker(String(localized: "common.field.start", defaultValue: "Start"), selection: startDateBinding(), displayedComponents: .hourAndMinute)
                DatePicker(String(localized: "common.field.end", defaultValue: "End"), selection: endDateBinding(), displayedComponents: .hourAndMinute)
            }
        }
        .schedyPageStyle()
        .navigationTitle(String(localized: "preset.edit.title", defaultValue: "Edit Time Preset"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            try? modelContext.save()
            scheduleCourseReminders(modelContext: modelContext)
        }
    }
}

#Preview {
    TimeSlotsSettingsView()
        .modelContainer(for: [TimeSlotPreset.self, TimeSlotItem.self], inMemory: true)
}
