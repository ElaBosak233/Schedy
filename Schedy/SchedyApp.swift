//
//  SchedyApp.swift
//  Schedy
//
//  App 入口：SwiftData 容器（含 iCloud 可选）、外观模式、启动时注册通知与小组件刷新。
//

import SwiftData
import SwiftUI

/// 外观模式：跟随系统 / 浅色 / 深色，对应 preferredColorScheme
enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 返回 SwiftData 默认 SQLite 文件的 URL（ApplicationSupport/<BundleID>/default.store）
private func defaultStoreURL() -> URL? {
    guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
          let bundleID = Bundle.main.bundleIdentifier else { return nil }
    return appSupport.appendingPathComponent(bundleID).appendingPathComponent("default.store")
}

/// 删除本地 SQLite 文件（.store / .store-shm / .store-wal），用于"云端覆盖本地"场景
private func deleteLocalStore() {
    guard let base = defaultStoreURL() else { return }
    let fm = FileManager.default
    for url in [base, URL(fileURLWithPath: base.path + "-shm"), URL(fileURLWithPath: base.path + "-wal")] {
        _ = try? fm.removeItem(at: url)
    }
}

func makeModelContainer(useICloud: Bool) -> ModelContainer {
    let schema = Schema([
        Schedule.self,
        Course.self,
        CourseReschedule.self,
        TimeSlotPreset.self,
        TimeSlotItem.self,
    ])
    let iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
    let config = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        cloudKitDatabase: (useICloud && iCloudAvailable) ? .automatic : .none
    )
    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        if useICloud && iCloudAvailable {
            UserDefaults.standard.set(false, forKey: kICloudSyncEnabledKey)
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            if let fallback = try? ModelContainer(for: schema, configurations: [fallbackConfig]) {
                return fallback
            }
        }
        fatalError("无法创建 ModelContainer: \(error)")
    }
}

@main
struct SchedyApp: App {
    @AppStorage(kAppearanceModeKey) private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage(kICloudSyncEnabledKey) private var iCloudSyncEnabled: Bool = false

    @State private var containerID: UUID = UUID()
    @State private var modelContainer: ModelContainer

    init() {
        // 首次启动：默认关闭 iCloud
        if UserDefaults.standard.object(forKey: kICloudSyncEnabledKey) == nil {
            UserDefaults.standard.set(false, forKey: kICloudSyncEnabledKey)
        }
        let useICloud = UserDefaults.standard.bool(forKey: kICloudSyncEnabledKey)
        // 云端覆盖本地：删除本地 SQLite 文件，让 CloudKit 重新同步云端数据
        if UserDefaults.standard.bool(forKey: kClearLocalDataOnNextLaunchKey) {
            UserDefaults.standard.removeObject(forKey: kClearLocalDataOnNextLaunchKey)
            deleteLocalStore()
        }
        _modelContainer = State(initialValue: makeModelContainer(useICloud: useICloud))
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(containerID)
                .modelContainer(modelContainer)
                .preferredColorScheme(appearanceMode.colorScheme)
                .onAppear {
                    requestCourseNotificationPermission()
                    registerNotificationRefreshTask()
                    scheduleNextNotificationRefresh()
                }
                .onChange(of: iCloudSyncEnabled) { _, newValue in
                    modelContainer = makeModelContainer(useICloud: newValue)
                }
        }
    }
}
