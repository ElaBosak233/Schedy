//
//  ImportFromAcademicAffairsView.swift
//  schedy
//
//  从教务（Academic Affairs）导入流程：选择覆盖/新建 → 选择学校 → 内嵌浏览器 → 导入当前页
//

import SwiftData
import SwiftUI

enum ImportAction {
    case overwrite
    case newSchedule
}

struct ImportFromAcademicAffairsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Schedule.name) private var schedules: [Schedule]
    @Query(sort: \TimeSlotPreset.name) private var presets: [TimeSlotPreset]
    @AppStorage("activeScheduleName") private var activeScheduleName: String = "我的课程表"

    @State private var step: Step = .chooseAction
    @State private var importAction: ImportAction = .overwrite
    @State private var selectedSchool: SchoolInfo?
    @State private var requestHTML = false
    @State private var importError: String?
    @State private var importSuccessCount: Int?
    @State private var isImporting = false
    @State private var urlBarText = ""
    @State private var pendingLoadURL: URL?

    private var activeSchedule: Schedule? {
        schedules.first { $0.name == activeScheduleName } ?? schedules.first
    }

    enum Step {
        case chooseAction
        case chooseSchool
        case browser
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .chooseAction:
                    chooseActionView
                case .chooseSchool:
                    chooseSchoolView
                case .browser:
                    browserView
                }
            }
            .navigationTitle("从教务导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .chooseSchool || step == .browser {
                        Button("上一步") {
                            if step == .browser { step = .chooseSchool }
                            else { step = .chooseAction }
                        }
                    } else {
                        Button("取消") { dismiss() }
                    }
                }
                if step == .browser {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            requestHTML = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .disabled(isImporting)
                    }
                }
            }
            .alert("导入失败", isPresented: .constant(importError != nil)) {
                Button("确定") { importError = nil }
            } message: {
                if let msg = importError { Text(msg) }
            }
            .alert("导入完成", isPresented: .constant(importSuccessCount != nil)) {
                Button("确定") {
                    importSuccessCount = nil
                    dismiss()
                }
            } message: {
                if let n = importSuccessCount {
                    Text("已导入 \(n) 门课程。")
                }
            }
        }
        .onAppear {
            step = .chooseAction
            selectedSchool = nil
        }
    }

    private var chooseActionView: some View {
        List {
            Section {
                Button {
                    importAction = .overwrite
                    step = .chooseSchool
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("覆盖当前课表")
                            Text("替换「\(activeSchedule?.name ?? "当前课表")」中的课程")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.on.doc.fill")
                    }
                }

                Button {
                    importAction = .newSchedule
                    step = .chooseSchool
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("新建课表")
                            Text("创建新课表并导入，保留现有课表不变")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "plus.rectangle.on.folder")
                    }
                }
            } header: {
                Text("导入方式")
            } footer: {
                Text("选择将课程导入到当前课表（覆盖）或新建一个课表。")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var chooseSchoolView: some View {
        List {
            Section {
                ForEach(SchoolInfo.all) { school in
                    Button {
                        selectedSchool = school
                        step = .browser
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(school.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(school.academicAffairsType.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                Text("选择学校")
            } footer: {
                Text("将使用该学校对应的教务系统解析规则。打开教务系统后，请进入「个人课表查询」页面，再点击右上角下载按钮导入。")
            }
        }
    }

    private var browserView: some View {
        Group {
            if let school = selectedSchool {
                VStack(spacing: 0) {
                    Text("请登录并进入「个人课表查询」页面后，点击右上角下载按钮导入。可修改上方网址跳转。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                    AcademicAffairsWebView(
                        initialURL: school.entryURL,
                        urlBarText: $urlBarText,
                        pendingLoadURL: $pendingLoadURL,
                        requestHTML: $requestHTML
                    ) { html in
                        performImport(html: html, school: school)
                    }
                }
            } else {
                ContentUnavailableView("未选择学校", systemImage: "building.2")
            }
        }
        .onChange(of: step) { _, newStep in
            if newStep == .browser, let school = selectedSchool {
                urlBarText = school.entryURL.absoluteString
            }
        }
        .onChange(of: requestHTML) { _, newVal in
            if newVal, selectedSchool != nil { isImporting = true }
        }
    }

    private func performImport(html: String, school: SchoolInfo) {
        defer { isImporting = false }
        let parsed: [ParsedCourseItem]
        switch school.academicAffairsType {
        case .zhengFang:
            parsed = ZhengFangHTMLParser.parse(html: html)
        }
        if parsed.isEmpty {
            importError = "未能从当前页面解析到课程，请确保已打开「个人课表查询」的课表页面。"
            return
        }
        seedDefaultPresetsIfNeeded(modelContext: modelContext)
        let presetsList = (try? modelContext.fetch(FetchDescriptor<TimeSlotPreset>())) ?? []
        let preset = presetsList.first

        let maxPeriodNeeded = parsed.map { $0.periodEnd }.max() ?? 0

        switch importAction {
        case .overwrite:
            guard let schedule = activeSchedule else {
                importError = "未找到当前课表。"
                return
            }
            let presetToUse = schedule.timeSlotPreset ?? preset
            extendPresetToCoverPeriodIfNeeded(preset: presetToUse, requiredPeriodCount: maxPeriodNeeded, modelContext: modelContext)
            for c in schedule.courses {
                modelContext.delete(c)
            }
            schedule.courses.removeAll()
            addParsedCourses(parsed, to: schedule, preset: preset)
            try? modelContext.save()
            refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
            scheduleCourseReminders(modelContext: modelContext, activeScheduleName: activeScheduleName)
            importSuccessCount = parsed.count
        case .newSchedule:
            extendPresetToCoverPeriodIfNeeded(preset: preset, requiredPeriodCount: maxPeriodNeeded, modelContext: modelContext)
            let semesterStart = defaultSemesterStartDate()
            let newName = newScheduleName()
            let newSchedule = Schedule(name: newName, semesterStartDate: semesterStart, timeSlotPreset: preset)
            modelContext.insert(newSchedule)
            addParsedCourses(parsed, to: newSchedule, preset: preset)
            try? modelContext.save()
            activeScheduleName = newName
            refreshWidgetData(modelContext: modelContext, activeScheduleName: newName)
            scheduleCourseReminders(modelContext: modelContext, activeScheduleName: newName)
            importSuccessCount = parsed.count
        }
    }

    private func addParsedCourses(_ items: [ParsedCourseItem], to schedule: Schedule, preset: TimeSlotPreset?) {
        for item in items {
            let course = Course(
                name: item.name,
                teacher: item.teacher.trimmingCharacters(in: .whitespaces).isEmpty ? nil : item.teacher,
                location: item.location.trimmingCharacters(in: .whitespaces).isEmpty ? nil : item.location,
                credits: item.credits,
                weekRangesString: item.weekRangesString,
                weekParity: item.weekParity,
                weekIndex: 1,
                dayOfWeek: item.dayOfWeek,
                periodIndex: item.periodIndex,
                periodEnd: item.periodEnd == item.periodIndex ? nil : item.periodEnd,
                schedule: schedule
            )
            modelContext.insert(course)
            schedule.courses.append(course)
        }
    }

    private func defaultSemesterStartDate() -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysUntilMonday = weekday == 1 ? 1 : (weekday == 2 ? 0 : (9 - weekday))
        return cal.date(byAdding: .day, value: daysUntilMonday, to: today) ?? today
    }

    private func newScheduleName() -> String {
        let base = "导入的课程表"
        var name = base
        var n = 1
        while schedules.contains(where: { $0.name == name }) {
            n += 1
            name = "\(base) \(n)"
        }
        return name
    }
}
