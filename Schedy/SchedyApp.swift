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
            TimeSlotPreset.self,
            TimeSlotItem.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
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
