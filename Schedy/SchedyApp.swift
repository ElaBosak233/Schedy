//
//  schedyApp.swift
//  schedy
//
//  Created by ela on 2026/2/25.
//

import SwiftData
import SwiftUI

/// 外观模式：跟随系统 / 浅色 / 深色
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

let kAppearanceModeKey = "appearanceMode"

@main
struct SchedyApp: App {
    @AppStorage(kAppearanceModeKey) private var appearanceModeRaw: String = AppearanceMode.system.rawValue

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Schedule.self,
            Course.self,
            CourseReschedule.self,
            TimeSlotPreset.self,
            TimeSlotItem.self,
        ])
        // 先尝试仅本地存储，避免与已有数据库 schema 冲突导致 loadIssueModelContainer
        // 若需启用 iCloud 同步，需在 Xcode 中临时移除 CloudKit capability 后删除 app 重装，
        // 再恢复 capability 后全新安装即可使用 CloudKit
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
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
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
