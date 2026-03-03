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
    @AppStorage("activeScheduleName") private var activeScheduleName: String = "我的课程表"

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
                                Text("导出为 CSV")
                                Text("导出与导入格式一致的 CSV，便于备份或二次编辑")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "tablecells")
                        }
                    }
                    .disabled(!hasCourses)
                } header: {
                    Text("导出格式")
                } footer: {
                    Text("CSV 包含课程名、教师、地点、周次、星期、节次等信息，可用 Excel 打开编辑。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("导出课表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}
