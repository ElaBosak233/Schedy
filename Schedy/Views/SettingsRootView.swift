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
    @AppStorage(kICloudSyncEnabledKey) private var iCloudSyncEnabled: Bool = true

    private var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var iCloudSyncBinding: Binding<Bool> {
        Binding(
            get: { iCloudAvailable ? iCloudSyncEnabled : false },
            set: { if iCloudAvailable { iCloudSyncEnabled = $0 } }
        )
    }

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
                Toggle(isOn: iCloudSyncBinding) {
                    Label("iCloud 同步", systemImage: "icloud")
                }
                .disabled(!iCloudAvailable)
            } header: {
                Text("课程表")
            } footer: {
                if iCloudAvailable {
                    Text("课程表、调课、时间段等数据通过 iCloud 自动在多设备间同步。请确保已登录同一 Apple ID。修改后需重启 app 生效。")
                } else {
                    Text("当前设备未登录 iCloud（如模拟器），无法使用同步功能。请在真机登录 Apple ID 后使用。")
                }
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
