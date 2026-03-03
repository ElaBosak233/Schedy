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
                    containerID = UUID()
                }
        }
    }
}
