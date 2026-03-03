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
                    Label("时间段", systemImage: "clock")
                }
                NavigationLink {
                    ICloudSettingsView()
                } label: {
                    Label("数据同步", systemImage: "arrow.triangle.2.circlepath.icloud")
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
