//
//  ContentView.swift
//  schedy
//
//  主界面：课程表 + 设置（课程表列表、时间段预设）
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("activeScheduleName") private var activeScheduleName: String = "我的课程表"

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
                if !activeScheduleName.isEmpty {
                    scheduleCourseReminders(modelContext: modelContext, activeScheduleName: activeScheduleName)
                }
                refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    if !activeScheduleName.isEmpty {
                        scheduleCourseReminders(modelContext: modelContext, activeScheduleName: activeScheduleName)
                    }
                    refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
                }
            }
        }
    }
}

// MARK: - 设置根视图：外观 / 课程表 / 时间段预设 / 权限 / 关于
struct SettingsRootView: View {
    @AppStorage(kAppearanceModeKey) private var appearanceModeRaw: String = AppearanceMode.system.rawValue

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        List {
            Section {
                Picker(selection: appearanceBinding) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    Label("外观", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
                NavigationLink {
                    ScheduleDisplaySettingsView()
                } label: {
                    Label("课表显示", systemImage: "tablecells")
                }
            } header: {
                Text("外观")
            }

            Section {
                NavigationLink {
                    ScheduleListView()
                } label: {
                    Label("课程表", systemImage: "rectangle.grid.2x2")
                }
                NavigationLink {
                    TimeSlotsSettingsView()
                } label: {
                    Label("时间段预设", systemImage: "clock")
                }
            } header: {
                Text("课程表")
            }

            Section {
                NavigationLink {
                    PermissionsView()
                } label: {
                    Label("权限", systemImage: "hand.raised")
                }
            } header: {
                Text("权限")
            }

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("关于", systemImage: "info.circle")
                }
            } header: {
                Text("关于")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    ContentView()
}
