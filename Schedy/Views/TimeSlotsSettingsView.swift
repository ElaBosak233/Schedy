//
//  TimeSlotsSettingsView.swift
//  schedy
//
//  时间段预设设置：切换冬令时/夏令时、自定义每节课的起止时间
//

import SwiftData
import SwiftUI

struct TimeSlotsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeSlotPreset.name) private var presets: [TimeSlotPreset]
    @State private var showAddPreset = false
    @State private var presetToEdit: TimeSlotPreset?
    @State private var newPresetName = ""
    @State private var selectedPresetForSlots: TimeSlotPreset?

    private var presetSheetBinding: Binding<Bool> {
        Binding(
            get: { presetToEdit != nil },
            set: { if !$0 { presetToEdit = nil } }
        )
    }

    var body: some View {
        listContent
            .navigationTitle("时间段预设")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .alert("新建预设", isPresented: $showAddPreset) { addPresetAlertContent } message: { addPresetAlertMessage }
            .sheet(isPresented: presetSheetBinding) { presetEditSheetContent }
            .onAppear {
                seedDefaultPresetsIfNeeded(modelContext: modelContext)
                if selectedPresetForSlots == nil, let first = presets.first {
                    selectedPresetForSlots = first
                }
            }
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            presetListSection
            slotsDetailSection
        }
    }

    @ViewBuilder
    private var presetListSection: some View {
        Section {
            ForEach(presets, id: \.name) { preset in
                presetRow(preset: preset)
            }
        } header: {
            Text("预设列表")
        } footer: {
            Text("每张课程表可在「课程表」设置中绑定一个预设。此处仅管理预设的起止时间。")
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
            if selectedPresetForSlots?.name == preset.name {
                Image(systemName: "chevron.right.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPresetForSlots = preset
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
        if let preset = selectedPresetForSlots, !preset.slots.isEmpty {
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
        TextField("预设名称", text: $newPresetName)
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
        if selectedPresetForSlots?.name == preset.name {
            selectedPresetForSlots = presets.first(where: { $0.name != preset.name })
        }
        for slot in preset.slots {
            modelContext.delete(slot)
        }
        modelContext.delete(preset)
        try? modelContext.save()
    }
}

// MARK: - 预设重命名（用于编辑预设名称）
struct PresetRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let preset: TimeSlotPreset
    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("预设名称", text: $name)
            }
            .navigationTitle("编辑预设")
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

    var body: some View {
        Form {
            Section("第 \(slot.periodIndex) 节") {
                TimePickerRow(label: "开始", hour: $slot.startHour, minute: $slot.startMinute)
                TimePickerRow(label: "结束", hour: $slot.endHour, minute: $slot.endMinute)
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

// MARK: - 时间选择器（滚轮样式，类似 iPhone 计时器）
struct TimePickerRow: View {
    var label: String
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                Picker("时", selection: $hour) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(String(format: "%02d", h)).tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Text(":")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Picker("分", selection: $minute) {
                    ForEach(0..<60, id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 120)
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    }
}

#Preview {
    TimeSlotsSettingsView()
        .modelContainer(for: [TimeSlotPreset.self, TimeSlotItem.self], inMemory: true)
}
