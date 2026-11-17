//
//  ContentView.swift
//  Schedy
//
//  主界面：Tab（今天 / 课程表 / 设置）、全屏背景；onAppear/进入前台时刷新通知与小组件数据。
//

import SwiftData
import SwiftUI

/// 根视图：三 Tab（今天、课程表、设置），统一底色；生命周期中触发课程提醒与小组件刷新
struct ContentView: View {
    @SceneStorage("selectedTab") private var selectedTab = 0
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ScheduleDisplayKeys.activeScheduleName) private var activeScheduleName: String = String(localized: "schedule.default.name", defaultValue: "My Timetable")

    var body: some View {
        ZStack {
            SchedyAppearance.background.ignoresSafeArea()
            TabView(selection: $selectedTab) {
                TodayView()
                    .tag(0)
                    .tabItem {
                        Label(String(localized: "navigation.today.title", defaultValue: "Today"), systemImage: "list.bullet.rectangle")
                    }

                ScheduleGridView()
                    .tag(1)
                    .tabItem {
                        Label(String(localized: "navigation.timetable.title", defaultValue: "Timetable"), systemImage: "calendar")
                    }

                NavigationStack {
                    SettingsRootView()
                }
                .tag(2)
                .tabItem {
                    Label(String(localized: "navigation.settings.title", defaultValue: "Settings"), systemImage: "gearshape")
                }
            }
            .tint(.accentColor)
            .onAppear {
                scheduleCourseReminders(modelContext: modelContext)
                refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    scheduleCourseReminders(modelContext: modelContext)
                    refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
