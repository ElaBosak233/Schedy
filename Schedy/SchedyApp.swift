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

@main
struct SchedyApp: App {
    @AppStorage(kAppearanceModeKey) private var appearanceModeRaw: String = AppearanceMode.system.rawValue

    /// SwiftData 容器：本地或 iCloud 同步；首次启动根据 iCloud 可用性设置默认同步开关
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Schedule.self,
            Course.self,
            CourseReschedule.self,
            TimeSlotPreset.self,
            TimeSlotItem.self,
        ])

        // iCloud 可用性：模拟器或未登录 Apple ID 时不可用
        let iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil

        // 首次启动：根据 iCloud 是否可用设置默认；iCloud 不可用时默认关闭
        if UserDefaults.standard.object(forKey: kICloudSyncEnabledKey) == nil {
            UserDefaults.standard.set(iCloudAvailable, forKey: kICloudSyncEnabledKey)
        }

        let useICloud = UserDefaults.standard.bool(forKey: kICloudSyncEnabledKey) && iCloudAvailable

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: useICloud ? .automatic : .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // CloudKit 初始化失败时回退到仅本地存储
            if useICloud {
                UserDefaults.standard.set(false, forKey: kICloudSyncEnabledKey)
                let fallbackConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .none
                )
                if let fallback = try? ModelContainer(for: schema, configurations: [fallbackConfig]) {
                    return fallback
                }
            }
            fatalError("无法创建 ModelContainer: \(error)")
        }
    }()

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearanceMode.colorScheme)
                .onAppear {
                    requestCourseNotificationPermission()
                    registerNotificationRefreshTask()
                    scheduleNextNotificationRefresh()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
