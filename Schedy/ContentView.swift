//
//  ContentView.swift
//  Schedy
//
//  主界面：Tab（今天 / 课程表 / 设置）、全屏背景；onAppear/进入前台时刷新通知与小组件数据。
//

import SwiftData
import SwiftUI

/// 根视图：三 Tab（今天、课程表、设置），背景渐变；生命周期中触发课程提醒与小组件刷新
struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ScheduleDisplayKeys.activeScheduleName) private var activeScheduleName: String = "我的课程表"

    /// 全屏朦胧背景：柔和渐变，课程表会透明透出此背景
    private var appBackground: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.11, blue: 0.16),
                        Color(red: 0.10, green: 0.11, blue: 0.15),
                        Color(red: 0.11, green: 0.12, blue: 0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    RadialGradient(
                        colors: [Color.white.opacity(0.06), Color.clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 500
                    )
                }
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.94, blue: 0.98),
                        Color(red: 0.92, green: 0.94, blue: 0.99),
                        Color(red: 0.94, green: 0.96, blue: 0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    RadialGradient(
                        colors: [Color.white.opacity(0.4), Color.clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 500
                    )
                }
            }
        }
        .ignoresSafeArea()
    }

    var body: some View {
        ZStack {
            appBackground
            TabView {
                TodayView()
                    .tabItem {
                        Label("今天", systemImage: "list.bullet.rectangle")
                    }

                ScheduleGridView()
                    .tabItem {
                        Label("课程表", systemImage: "calendar")
                    }

                NavigationStack {
                    SettingsRootView()
                }
                .tabItem {
                    Label("设置", systemImage: "gearshape")
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
