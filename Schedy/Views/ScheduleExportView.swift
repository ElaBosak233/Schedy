//
//  ScheduleExportView.swift
//  Schedy
//
//  导出流程：选择当前课表后点击「导出为 CSV」，由调用方生成文件并弹出系统分享面板。
//

import SwiftData
import SwiftUI

struct ScheduleExportView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Schedule.name) private var schedules: [Schedule]
    @AppStorage(ScheduleDisplayKeys.activeScheduleName) private var activeScheduleName: String = String(localized: "schedule.default.name", defaultValue: "My Timetable")

    /// 用户选择「导出为 CSV」时由外部生成文件并设置 shareExportURL，然后关闭本界面
    var onExportCSV: () -> Void

    private var activeSchedule: Schedule? {
        schedules.first { $0.name == activeScheduleName } ?? schedules.first
    }

    private var hasCourses: Bool {
        guard let schedule = activeSchedule else { return false }
        return !(schedule.courses?.isEmpty ?? true)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onExportCSV()
                        dismiss()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "export.csv.action", defaultValue: "Export as CSV"))
                                Text(String(localized: "export.csv.action_description", defaultValue: "Export an importable CSV for backup or editing."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "tablecells")
                        }
                    }
                    .disabled(!hasCourses)
                } header: {
                    Text(String(localized: "export.format.title", defaultValue: "Export Format"))
                } footer: {
                    Text(String(localized: "export.csv.description", defaultValue: "The CSV includes course names, teachers, locations, weeks, weekdays, and periods. You can edit it in Excel."))
                }
            }
            .listStyle(.insetGrouped)
            .schedyPageStyle()
            .navigationTitle(String(localized: "export.title", defaultValue: "Export Timetable"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.action.cancel", defaultValue: "Cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
