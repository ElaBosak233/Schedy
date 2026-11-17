//
//  ScheduleDisplaySettingsView.swift
//  Schedy
//
//  课表显示设置：网格线、周末、每周第一天。AppStorage 键见 AppStorageKeys.swift。
//

import SwiftUI

/// 每周第一天：1 = 周日，2 = 周一（与 Calendar.Weekday 一致）
enum FirstWeekdayOption: Int, CaseIterable {
    case sunday = 1
    case monday = 2

    var displayName: String {
        switch self {
        case .sunday: return String(localized: "calendar.weekday.sunday.short", defaultValue: "Sun")
        case .monday: return String(localized: "calendar.weekday.monday.short", defaultValue: "Mon")
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
                    Label(String(localized: "settings.grid_lines.horizontal", defaultValue: "Show Horizontal Lines"), systemImage: "line.diagonal")
                }
                Toggle(isOn: $showVerticalLines) {
                    Label(String(localized: "settings.grid_lines.vertical", defaultValue: "Show Vertical Lines"), systemImage: "rectangle.split.2x1")
                }
            } header: {
                Text(String(localized: "settings.grid_lines.title", defaultValue: "Grid Lines"))
            } footer: {
                Text(String(localized: "settings.grid_lines.description", defaultValue: "Choose which grid lines appear in the timetable."))
            }

            Section {
                Toggle(isOn: $showWeekends) {
                    Label(String(localized: "settings.weekends.show", defaultValue: "Show Weekends"), systemImage: "calendar")
                }
            } header: {
                Text(String(localized: "settings.weekends.title", defaultValue: "Weekends"))
            } footer: {
                Text(String(localized: "settings.weekends.description", defaultValue: "When turned off, the timetable shows Monday through Friday only."))
            }

            Section {
                Picker(selection: firstWeekdayBinding) {
                    ForEach(FirstWeekdayOption.allCases, id: \.rawValue) { option in
                        Text(option.displayName).tag(option)
                    }
                } label: {
                    Label(String(localized: "settings.first_weekday.title", defaultValue: "First Day of Week"), systemImage: "calendar.badge.clock")
                }
                .pickerStyle(.menu)
            } header: {
                Text(String(localized: "settings.first_weekday.title", defaultValue: "First Day of Week"))
            } footer: {
                Text(String(localized: "settings.first_weekday.description", defaultValue: "Choose Sunday or Monday as the leftmost timetable column."))
            }
        }
        .schedyPageStyle()
        .navigationTitle(String(localized: "settings.timetable_display.title", defaultValue: "Timetable Display"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ScheduleDisplaySettingsView()
    }
}
