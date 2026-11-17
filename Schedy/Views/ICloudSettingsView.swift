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

    @State private var showClearConfirm = false
    @State private var needsRestart = false

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
                    Label(String(localized: "sync.icloud.title", defaultValue: "iCloud Sync"), systemImage: "icloud")
                }
                .disabled(!iCloudAvailable)
            } footer: {
                if iCloudAvailable {
                    Text(String(localized: "sync.icloud.account_hint", defaultValue: "Make sure your devices use the same Apple ID."))
                } else {
                    Text(String(localized: "sync.icloud.unavailable", defaultValue: "This device is not signed in to iCloud. Sign in with your Apple ID on a physical device to use sync."))
                }
            }

            if iCloudAvailable && iCloudSyncEnabled {
                Section(String(localized: "sync.status.title", defaultValue: "Sync Status")) {
                    if isSyncing {
                        HStack {
                            Label(String(localized: "sync.status.syncing", defaultValue: "Syncing…"), systemImage: "arrow.triangle.2.circlepath.icloud")
                            Spacer()
                            ProgressView()
                        }
                    } else if let err = syncError {
                        Label(err, systemImage: "exclamationmark.icloud")
                            .foregroundStyle(.red)
                    } else {
                        Label(String(localized: "sync.status.up_to_date", defaultValue: "Up to Date"), systemImage: "checkmark.icloud")
                            .foregroundStyle(.green)
                    }

                    if let date = lastSyncDate {
                        HStack {
                            Text(String(localized: "sync.status.last_synced", defaultValue: "Last Synced"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(date, format: .dateTime.year().month().day().hour().minute().second())
                        }
                        .font(.subheadline)
                    }
                }
            }

            if needsRestart {
                Section {
                    Text(String(localized: "sync.restart_required", defaultValue: "Restart the app to apply your changes."))
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }

            Section {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label(String(localized: "sync.reset.title", defaultValue: "Reset to Defaults"), systemImage: "arrow.counterclockwise")
                }
            } footer: {
                Text(String(localized: "sync.reset.description", defaultValue: "Delete all timetables and time presets on this device and create a default timetable. Your data in iCloud will be kept."))
            }
        }
        .schedyPageStyle(navigationBackground: .automatic)
        .navigationTitle(String(localized: "settings.sync.title", defaultValue: "Data Sync"))
        .navigationBarTitleDisplayMode(.large)
        // 关闭 iCloud 确认
        .alert(
            String(localized: "sync.disable.title", defaultValue: "Turn Off iCloud Sync"),
            isPresented: Binding(
                get: { pendingToggleValue == false },
                set: { if !$0 { pendingToggleValue = nil } }
            )
        ) {
            Button(String(localized: "common.action.close", defaultValue: "Close"), role: .destructive) {
                iCloudSyncEnabled = false
                needsRestart = true
                pendingToggleValue = nil
            }
            Button(String(localized: "common.action.cancel", defaultValue: "Cancel"), role: .cancel) { pendingToggleValue = nil }
        } message: {
            Text(String(localized: "sync.disable.description", defaultValue: "Only local data will be used. Your data in iCloud will be kept."))
        }
        // 开启 iCloud：本地有数据时询问优先级
        .alert(
            String(localized: "sync.enable.title", defaultValue: "Turn On iCloud Sync"),
            isPresented: Binding(
                get: { pendingToggleValue == true && localScheduleCount > 0 },
                set: { if !$0 { pendingToggleValue = nil } }
            )
        ) {
            Button(String(localized: "sync.action.merge", defaultValue: "Merge Local and iCloud Data")) {
                iCloudSyncEnabled = true
                needsRestart = true
                pendingToggleValue = nil
            }
            Button(String(localized: "sync.action.replace_local", defaultValue: "Replace Local Data"), role: .destructive) {
                UserDefaults.standard.set(true, forKey: kClearLocalDataOnNextLaunchKey)
                iCloudSyncEnabled = true
                needsRestart = true
                pendingToggleValue = nil
            }
            Button(String(localized: "common.action.cancel", defaultValue: "Cancel"), role: .cancel) { pendingToggleValue = nil }
        } message: {
            Text(String(localized: "sync.enable.merge_description", defaultValue: "You have \(localScheduleCount) local timetables.\n\nMerge: Keep local data and merge it with iCloud.\nReplace: Delete local data and use only the data from iCloud."))
        }
        // 开启 iCloud：本地无数据时直接确认
        .alert(
            String(localized: "sync.enable.title", defaultValue: "Turn On iCloud Sync"),
            isPresented: Binding(
                get: { pendingToggleValue == true && localScheduleCount == 0 },
                set: { if !$0 { pendingToggleValue = nil } }
            )
        ) {
            Button(String(localized: "common.action.enable", defaultValue: "Turn On")) {
                iCloudSyncEnabled = true
                needsRestart = true
                pendingToggleValue = nil
            }
            Button(String(localized: "common.action.cancel", defaultValue: "Cancel"), role: .cancel) { pendingToggleValue = nil }
        } message: {
            Text(String(localized: "sync.enable.description", defaultValue: "Your iCloud data will sync to this device automatically."))
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
                        // 首次 import 完成后无需额外处理
                    }
                }
            @unknown default:
                break
            }
        }
        // 还原默认数据确认
        .alert(String(localized: "sync.reset.title", defaultValue: "Reset to Defaults"), isPresented: $showClearConfirm) {
            Button(String(localized: "common.action.reset", defaultValue: "Reset"), role: .destructive) { resetToDefault() }
            Button(String(localized: "common.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "sync.reset.confirmation", defaultValue: "All timetables and time presets will be deleted and a default timetable will be created. This cannot be undone."))
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
        let defaultName = String(localized: "schedule.default.name", defaultValue: "My Timetable")
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
