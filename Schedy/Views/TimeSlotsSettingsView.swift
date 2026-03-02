//
//  TimeSlotsSettingsView.swift
//  schedy
//
//  时间段设置：切换冬令时/夏令时、自定义每节课的起止时间
//

import SwiftData
import SwiftUI

struct TimeSlotsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeSlotPreset.name) private var presets: [TimeSlotPreset]
    @AppStorage(ScheduleDisplayKeys.activeTimeSlotPresetName) private var activeTimeSlotPresetName: String = ""
    @State private var showAddPreset = false
    @State private var presetToEdit: TimeSlotPreset?
    @State private var newPresetName = ""

    private var presetSheetBinding: Binding<Bool> {
        Binding(
            get: { presetToEdit != nil },
            set: { if !$0 { presetToEdit = nil } }
        )
    }

    /// 当前选中的时间段（用于下方时间段明细）
    private var activePreset: TimeSlotPreset? {
        presets.first { $0.name == activeTimeSlotPresetName }
    }

    var body: some View {
        listContent
            .navigationTitle("时间段")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .alert("新建时间段", isPresented: $showAddPreset) { addPresetAlertContent } message: { addPresetAlertMessage }
            .sheet(isPresented: presetSheetBinding) { presetEditSheetContent }
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
                Text("时间段")
            } footer: {
                Text("点击选择当前使用的时间段。所有课程表将统一使用该时间段显示上课时间。下方可管理各节的起止时间。")
            }
            slotsDetailSection
        }
    }

    private func presetRow(preset: TimeSlotPreset) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.headline)
                Text("\(preset.slots.count) 个时间段")
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
            Button("编辑", systemImage: "pencil") {
                presetToEdit = preset
            }
            if presets.count > 1 {
                Button("删除", systemImage: "trash", role: .destructive) {
                    deletePreset(preset)
                }
            }
        }
    }

    @ViewBuilder
    private var slotsDetailSection: some View {
        if let preset = activePreset, !preset.slots.isEmpty {
            Section("\(preset.name) 时间段明细") {
                ForEach(preset.slots.sorted(by: { $0.periodIndex < $1.periodIndex }), id: \.periodIndex) { slot in
                    NavigationLink {
                        TimeSlotEditView(slot: slot)
                    } label: {
                        HStack {
                            Text("第 \(slot.periodIndex) 节")
                            Spacer()
                            Text(slot.timeRangeString)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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
        TextField("时间段名称", text: $newPresetName)
            .textInputAutocapitalization(.words)
        Button("取消", role: .cancel) {
            newPresetName = ""
        }
        Button("确定") {
            createPreset()
        }
        .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var addPresetAlertMessage: some View {
        Text("例如：冬令时、夏令时、自定义")
    }

    @ViewBuilder
    private var presetEditSheetContent: some View {
        if let p = presetToEdit {
            PresetRenameSheet(preset: p)
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
        let defaultData = DefaultTimeSlots.winter()
        for item in defaultData {
            let slot = TimeSlotItem(
                periodIndex: item.period,
                startHour: item.start.h,
                startMinute: item.start.m,
                endHour: item.end.h,
                endMinute: item.end.m
            )
            slot.preset = newPreset
            newPreset.slots.append(slot)
            modelContext.insert(slot)
        }
        modelContext.insert(newPreset)
        try? modelContext.save()
        newPresetName = ""
        showAddPreset = false
    }

    private func deletePreset(_ preset: TimeSlotPreset) {
        if activeTimeSlotPresetName == preset.name,
           let other = presets.first(where: { $0.name != preset.name }) {
            activeTimeSlotPresetName = other.name
        }
        for slot in preset.slots {
            modelContext.delete(slot)
        }
        modelContext.delete(preset)
        try? modelContext.save()
    }
}

// MARK: - 时间段重命名（用于编辑时间段名称）
struct PresetRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let preset: TimeSlotPreset
    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("时间段名称", text: $name)
            }
            .navigationTitle("编辑时间段")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { name = preset.name }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        preset.name = name.trimmingCharacters(in: .whitespaces)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - 单节时间段编辑
struct TimeSlotEditView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("activeScheduleName") private var activeScheduleName: String = "我的课程表"
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
            Section("第 \(slot.periodIndex) 节") {
                DatePicker("开始", selection: startDateBinding(), displayedComponents: .hourAndMinute)
                DatePicker("结束", selection: endDateBinding(), displayedComponents: .hourAndMinute)
            }
        }
        .navigationTitle("编辑时间段")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            try? modelContext.save()
            if !activeScheduleName.isEmpty {
                scheduleCourseReminders(modelContext: modelContext, activeScheduleName: activeScheduleName)
            }
        }
    }
}

#Preview {
    TimeSlotsSettingsView()
        .modelContainer(for: [TimeSlotPreset.self, TimeSlotItem.self], inMemory: true)
}
