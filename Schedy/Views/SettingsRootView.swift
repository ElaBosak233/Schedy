//
//  SettingsRootView.swift
//  Schedy
//
//  设置页根视图：外观、课表显示、课程表列表、时间段、iCloud 同步、权限、关于。
//

import SwiftUI

/// 设置 Tab 下的主列表：外观 / 课表显示 / 课程表与时间段 / 权限 / 关于
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
                    Label(String(localized: "settings.appearance.title", defaultValue: "Appearance"), systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
                NavigationLink {
                    ScheduleDisplaySettingsView()
                } label: {
                    Label(String(localized: "settings.timetable_display.title", defaultValue: "Timetable Display"), systemImage: "tablecells")
                }
            } header: {
                Text(String(localized: "settings.appearance.title", defaultValue: "Appearance"))
            }

            Section {
                NavigationLink {
                    ScheduleListView()
                } label: {
                    Label(String(localized: "navigation.timetable.title", defaultValue: "Timetable"), systemImage: "rectangle.grid.2x2")
                }
                NavigationLink {
                    TimeSlotsSettingsView()
                } label: {
                    Label(String(localized: "settings.presets.title", defaultValue: "Time Presets"), systemImage: "clock")
                }
                NavigationLink {
                    ICloudSettingsView()
                } label: {
                    Label(String(localized: "settings.sync.title", defaultValue: "Data Sync"), systemImage: "arrow.triangle.2.circlepath.icloud")
                }
            } header: {
                Text(String(localized: "navigation.timetable.title", defaultValue: "Timetable"))
            }

            Section {
                NavigationLink {
                    PermissionsView()
                } label: {
                    Label(String(localized: "navigation.permissions.title", defaultValue: "Permissions"), systemImage: "hand.raised")
                }
            } header: {
                Text(String(localized: "navigation.permissions.title", defaultValue: "Permissions"))
            }

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    Label(String(localized: "navigation.about.title", defaultValue: "About"), systemImage: "info.circle")
                }
            } header: {
                Text(String(localized: "navigation.about.title", defaultValue: "About"))
            }
        }
        .schedyPageStyle(navigationBackground: .automatic)
        .navigationTitle(String(localized: "navigation.settings.title", defaultValue: "Settings"))
        .navigationBarTitleDisplayMode(.large)
    }
}
