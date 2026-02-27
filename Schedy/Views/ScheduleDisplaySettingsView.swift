//
//  ScheduleDisplaySettingsView.swift
//  schedy
//
//  课表显示设置：网格线、周末、每周第一天
//

import SwiftUI

/// AppStorage 键：课表网格与显示
enum ScheduleDisplayKeys {
    static let showHorizontalLines = "scheduleGridShowHorizontalLines"
    static let showVerticalLines = "scheduleGridShowVerticalLines"
    static let showWeekends = "scheduleShowWeekends"
    static let firstWeekday = "scheduleFirstWeekday"
}

/// 每周第一天：1 = 周日，2 = 周一（与 Calendar.Weekday 一致）
enum FirstWeekdayOption: Int, CaseIterable {
    case sunday = 1
    case monday = 2

    var displayName: String {
        switch self {
        case .sunday: return "周日"
        case .monday: return "周一"
        }
    }
}

struct ScheduleDisplaySettingsView: View {
    @AppStorage(ScheduleDisplayKeys.showHorizontalLines) private var showHorizontalLines: Bool = true
    @AppStorage(ScheduleDisplayKeys.showVerticalLines) private var showVerticalLines: Bool = true
    @AppStorage(ScheduleDisplayKeys.showWeekends) private var showWeekends: Bool = true
    @AppStorage(ScheduleDisplayKeys.firstWeekday) private var firstWeekdayRaw: Int = 2

    private var firstWeekdayBinding: Binding<FirstWeekdayOption> {
        Binding(
            get: { FirstWeekdayOption(rawValue: firstWeekdayRaw) ?? .monday },
            set: { firstWeekdayRaw = $0.rawValue }
        )
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $showHorizontalLines) {
                    Label("显示横线", systemImage: "line.diagonal")
                }
                Toggle(isOn: $showVerticalLines) {
                    Label("显示竖线", systemImage: "rectangle.split.2x1")
                }
            } header: {
                Text("网格线")
            } footer: {
                Text("控制课表网格中横线与竖线的显示。")
            }

            Section {
                Toggle(isOn: $showWeekends) {
                    Label("显示周末", systemImage: "calendar")
                }
            } header: {
                Text("周末")
            } footer: {
                Text("关闭后课表仅显示周一至周五。")
            }

            Section {
                Picker(selection: firstWeekdayBinding) {
                    ForEach(FirstWeekdayOption.allCases, id: \.rawValue) { option in
                        Text(option.displayName).tag(option)
                    }
                } label: {
                    Label("每周第一天", systemImage: "calendar.badge.clock")
                }
                .pickerStyle(.menu)
            } header: {
                Text("每周第一天")
            } footer: {
                Text("选择周日或周一作为课表最左侧的列。")
            }
        }
        .navigationTitle("课表显示")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ScheduleDisplaySettingsView()
    }
}
