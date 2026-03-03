//
//  ICloudSettingsView.swift
//  Schedy
//
//  iCloud 同步设置子页面
//

// CoreData 用于监听 NSPersistentCloudKitContainer.eventChangedNotification 同步事件
import Combine
import CoreData
import SwiftData
import SwiftUI

struct ICloudSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(kICloudSyncEnabledKey) private var iCloudSyncEnabled: Bool = false

    @State private var lastSyncDate: Date? = nil
    @State private var syncError: String? = nil
    @State private var isSyncing: Bool = false
    @State private var pendingToggleValue: Bool? = nil
    /// 选择"上传本地数据"时，记录本地已有的 Schedule persistentModelID，首次 import 后删除云端带来的多余数据
    @State private var localOnlyScheduleIDs: Set<PersistentIdentifier>? = nil

    @State private var showClearConfirm = false

    private var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var localScheduleCount: Int {
        (try? modelContext.fetch(FetchDescriptor<Schedule>()))?.count ?? 0
    }

    private var iCloudSyncBinding: Binding<Bool> {
        Binding(
            get: { iCloudAvailable ? iCloudSyncEnabled : false },
            set: { newValue in
                guard iCloudAvailable else { return }
                pendingToggleValue = newValue
            }
        )
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: iCloudSyncBinding) {
                    Label("iCloud 同步", systemImage: "icloud")
                }
                .disabled(!iCloudAvailable)
            } footer: {
                if iCloudAvailable {
                    Text("请确保已登录同一 Apple ID。")
                } else {
                    Text("当前设备未登录 iCloud（如模拟器），无法使用同步功能。请在真机登录 Apple ID 后使用。")
                }
            }

            if iCloudAvailable && iCloudSyncEnabled {
                Section("同步状态") {
                    if isSyncing {
                        HStack {
                            Label("正在同步…", systemImage: "arrow.triangle.2.circlepath.icloud")
                            Spacer()
                            ProgressView()
                        }
                    } else if let err = syncError {
                        Label(err, systemImage: "exclamationmark.icloud")
                            .foregroundStyle(.red)
                    } else {
                        Label("同步正常", systemImage: "checkmark.icloud")
                            .foregroundStyle(.green)
                    }

                    if let date = lastSyncDate {
                        HStack {
                            Text("上次同步")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(date, style: .relative) + Text("前")
                        }
                        .font(.subheadline)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("还原默认数据", systemImage: "arrow.counterclockwise")
                }
            } footer: {
                Text("清除本设备上的所有课程表与时间段数据，并重新创建默认课程表。iCloud 中的数据不受影响。")
            }
        }
        .navigationTitle("数据同步")
        .navigationBarTitleDisplayMode(.large)
        // 关闭 iCloud 确认
        .alert(
            "关闭 iCloud 同步",
            isPresented: Binding(
                get: { pendingToggleValue == false },
                set: { if !$0 { pendingToggleValue = nil } }
            )
        ) {
            Button("关闭", role: .destructive) {
                iCloudSyncEnabled = false
                pendingToggleValue = nil
            }
            Button("取消", role: .cancel) { pendingToggleValue = nil }
        } message: {
            Text("关闭后将仅使用本地数据，iCloud 中的数据不受影响。")
        }
        // 开启 iCloud：本地有数据时询问优先级
        .alert(
            "开启 iCloud 同步",
            isPresented: Binding(
                get: { pendingToggleValue == true && localScheduleCount > 0 },
                set: { if !$0 { pendingToggleValue = nil } }
            )
        ) {
            Button("上传本地数据") {
                let ids = Set((try? modelContext.fetch(FetchDescriptor<Schedule>()))?.map(\.persistentModelID) ?? [])
                localOnlyScheduleIDs = ids
                iCloudSyncEnabled = true
                pendingToggleValue = nil
            }
            Button("使用云端数据", role: .destructive) {
                let schedules = (try? modelContext.fetch(FetchDescriptor<Schedule>())) ?? []
                let presets = (try? modelContext.fetch(FetchDescriptor<TimeSlotPreset>())) ?? []
                schedules.forEach { modelContext.delete($0) }
                presets.forEach { modelContext.delete($0) }
                try? modelContext.save()
                iCloudSyncEnabled = true
                pendingToggleValue = nil
            }
            Button("取消", role: .cancel) { pendingToggleValue = nil }
        } message: {
            Text("本地有 \(localScheduleCount) 张课程表。开启后将与 iCloud 同步，请选择数据来源：")
        }
        // 开启 iCloud：本地无数据时直接确认
        .alert(
            "开启 iCloud 同步",
            isPresented: Binding(
                get: { pendingToggleValue == true && localScheduleCount == 0 },
                set: { if !$0 { pendingToggleValue = nil } }
            )
        ) {
            Button("开启") {
                iCloudSyncEnabled = true
                pendingToggleValue = nil
            }
            Button("取消", role: .cancel) { pendingToggleValue = nil }
        } message: {
            Text("开启后，iCloud 数据将自动同步到本设备。")
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSPersistentCloudKitContainer.eventChangedNotification
            ).receive(on: RunLoop.main)
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            switch event.type {
            case .setup, .import, .export:
                if event.endDate == nil {
                    isSyncing = true
                    syncError = nil
                } else {
                    isSyncing = false
                    if let err = event.error {
                        syncError = err.localizedDescription
                    } else {
                        syncError = nil
                        lastSyncDate = event.endDate
                        // 首次 import 完成后，删除云端带来的多余 Schedule（不在本地原有集合里的）
                        if event.type == .import, let keepIDs = localOnlyScheduleIDs {
                            localOnlyScheduleIDs = nil
                            let all = (try? modelContext.fetch(FetchDescriptor<Schedule>())) ?? []
                            all.filter { !keepIDs.contains($0.persistentModelID) }.forEach { modelContext.delete($0) }
                            try? modelContext.save()
                        }
                    }
                }
            @unknown default:
                break
            }
        }
        // 还原默认数据确认
        .alert("还原默认数据", isPresented: $showClearConfirm) {
            Button("还原", role: .destructive) { resetToDefault() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除所有课程表与时间段数据，并重新创建默认课程表，此操作不可撤销。")
        }
    }

    @MainActor
    private func resetToDefault() {
        let schedules = (try? modelContext.fetch(FetchDescriptor<Schedule>())) ?? []
        let presets = (try? modelContext.fetch(FetchDescriptor<TimeSlotPreset>())) ?? []
        schedules.forEach { modelContext.delete($0) }
        presets.forEach { modelContext.delete($0) }
        try? modelContext.save()
        seedDefaultPresetsIfNeeded(modelContext: modelContext)
        let allPresets = (try? modelContext.fetch(FetchDescriptor<TimeSlotPreset>())) ?? []
        let defaultName = "我的课程表"
        let schedule = Schedule(name: defaultName, semesterStartDate: defaultSemesterStartDate())
        schedule.timeSlotPreset = allPresets.first
        modelContext.insert(schedule)
        try? modelContext.save()
        UserDefaults.standard.set(defaultName, forKey: ScheduleDisplayKeys.activeScheduleName)
        if let firstPresetName = allPresets.first?.name {
            UserDefaults.standard.set(firstPresetName, forKey: ScheduleDisplayKeys.activeTimeSlotPresetName)
        }
    }
}
