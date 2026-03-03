//
//  ICloudSettingsView.swift
//  Schedy
//
//  iCloud 同步设置子页面
//

import CoreData
import SwiftData
import SwiftUI

struct ICloudSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(kICloudSyncEnabledKey) private var iCloudSyncEnabled: Bool = true

    @State private var lastSyncDate: Date? = nil
    @State private var syncError: String? = nil
    @State private var isSyncing: Bool = false
    @State private var pendingToggleValue: Bool? = nil

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
                    Text("修改后需重启 app 生效。请确保已登录同一 Apple ID。")
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
        }
        .navigationTitle("iCloud")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog(
            pendingToggleValue == true ? "开启 iCloud 同步" : "关闭 iCloud 同步",
            isPresented: Binding(get: { pendingToggleValue != nil }, set: { if !$0 { pendingToggleValue = nil } }),
            titleVisibility: .visible
        ) {
            if pendingToggleValue == true {
                // 开启 iCloud：如果本地有数据，提供选择
                if localScheduleCount > 0 {
                    Button("保留本地数据并合并云端") {
                        iCloudSyncEnabled = true
                        pendingToggleValue = nil
                    }
                    Button("清除本地数据，使用云端数据", role: .destructive) {
                        clearLocalData()
                        iCloudSyncEnabled = true
                        pendingToggleValue = nil
                    }
                } else {
                    Button("开启") {
                        iCloudSyncEnabled = true
                        pendingToggleValue = nil
                    }
                }
            } else {
                Button("关闭 iCloud 同步") {
                    iCloudSyncEnabled = false
                    pendingToggleValue = nil
                }
            }
            Button("取消", role: .cancel) { pendingToggleValue = nil }
        } message: {
            if pendingToggleValue == true {
                if localScheduleCount > 0 {
                    Text("本地有 \(localScheduleCount) 张课程表。开启后重启 app，本地数据将与 iCloud 数据合并。若只想使用云端数据，可选择清除本地数据。")
                } else {
                    Text("开启后重启 app，iCloud 数据将自动同步到本设备。")
                }
            } else {
                Text("关闭后重启 app，将仅使用本地数据，iCloud 中的数据不受影响。")
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSPersistentCloudKitContainer.eventChangedNotification
            )
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
                    }
                }
            @unknown default:
                break
            }
        }
    }

    @MainActor
    private func clearLocalData() {
        let schedules = (try? modelContext.fetch(FetchDescriptor<Schedule>())) ?? []
        let presets = (try? modelContext.fetch(FetchDescriptor<TimeSlotPreset>())) ?? []
        schedules.forEach { modelContext.delete($0) }
        presets.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }
}
