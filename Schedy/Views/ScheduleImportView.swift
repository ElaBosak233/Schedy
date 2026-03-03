//
//  ScheduleImportView.swift
//  Schedy
//
//  导入课表流程：选择覆盖/新建 → 选择从教务导入/从 CSV 导入 → 选择院校/教务系统（Tab）或 CSV 文件 → 内嵌浏览器 / CSV 解析 → 导入
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum ImportAction {
    case overwrite
    case newSchedule
}

/// 导入方式：从教务导入 / 从 CSV 导入
enum ImportMethod {
    case fromAcademicAffairs
    case fromCSV
}

/// 导入配置：教务类型 + 入口 URL（用于浏览器和解析）
private struct ImportConfig {
    let academicAffairsType: AcademicAffairsType
    let entryURL: URL
}

struct ScheduleImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Schedule.name) private var schedules: [Schedule]
    @Query(sort: \TimeSlotPreset.name) private var presets: [TimeSlotPreset]
    @AppStorage("activeScheduleName") private var activeScheduleName: String = "我的课程表"
    @AppStorage(ScheduleDisplayKeys.activeTimeSlotPresetName) private var activeTimeSlotPresetName: String = ""

    @State private var step: Step = .chooseAction
    @State private var importAction: ImportAction = .overwrite
    @State private var importMethod: ImportMethod = .fromAcademicAffairs
    @State private var sourceTab: SourceTab = .school
    @State private var selectedSchool: SchoolInfo?
    @State private var selectedSystemType: AcademicAffairsType?
    @State private var importConfig: ImportConfig?
    @State private var requestHTML = false
    @State private var importError: String?
    @State private var importSuccessCount: Int?
    @State private var isImporting = false
    @State private var urlBarText = ""
    @State private var pendingLoadURL: URL?
    @State private var showCSVFileImporter = false
    @State private var showTemplateCopied = false
    @State private var showPromptCopied = false

    private var activeSchedule: Schedule? {
        schedules.first { $0.name == activeScheduleName } ?? schedules.first
    }

    enum Step {
        case chooseAction       // 1. 覆盖 or 新建
        case chooseImportMethod // 2. 从教务导入 or 从 CSV 导入
        case chooseSource       // 3. 院校 / 教务系统（Tab）
        case browser            // 4. 内嵌浏览器
        case csvImport          // 从 CSV 导入
    }

    enum SourceTab: String, CaseIterable {
        case school = "院校"
        case system = "教务系统"
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .chooseAction:
                    chooseActionView
                case .chooseImportMethod:
                    chooseImportMethodView
                case .chooseSource:
                    chooseSourceView
                case .browser:
                    browserView
                case .csvImport:
                    csvImportView
                }
            }
            .navigationTitle("导入课表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .chooseImportMethod || step == .chooseSource || step == .browser || step == .csvImport {
                        Button("上一步") {
                            if step == .browser { step = .chooseSource }
                            else if step == .chooseSource { step = .chooseImportMethod }
                            else if step == .csvImport { step = .chooseImportMethod }
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
            selectedSystemType = nil
            importConfig = nil
        }
    }

    // MARK: - Step 1: 覆盖 or 新建

    private var chooseActionView: some View {
        List {
            Section {
                Button {
                    importAction = .overwrite
                    step = .chooseImportMethod
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
                    step = .chooseImportMethod
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

    // MARK: - Step 2: 从教务导入 or 其他方法

    private var chooseImportMethodView: some View {
        List {
            Section {
                Button {
                    importMethod = .fromAcademicAffairs
                    step = .chooseSource
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("从教务导入")
                            Text("通过学校教务系统网页导入课表")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "globe")
                    }
                }

                Button {
                    importMethod = .fromCSV
                    step = .csvImport
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("从 CSV 导入")
                            Text("使用 CSV 文件或通过 AI 生成课表")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "tablecells")
                    }
                }
            } header: {
                Text("选择导入来源")
            } footer: {
                Text("从教务导入会打开学校教务系统网页，进入课表页面后点击右上角下载按钮即可导入。也可使用 CSV 文件导入或让 AI 生成 CSV。")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 从 CSV 导入

    private var csvImportView: some View {
        List {
            Section {
                Button {
                    UIPasteboard.general.string = CSVImportConstants.templateContent
                    showTemplateCopied = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("复制 CSV 模板")
                            Text("将模板复制到剪贴板，可粘贴到 Excel 或文本编辑器填写")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.on.clipboard")
                    }
                }

                Button {
                    UIPasteboard.general.string = CSVImportConstants.llmPrompt
                    showPromptCopied = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("复制 Prompt")
                            Text("复制后粘贴到 ChatGPT、Claude 等，让 AI 根据课表生成 CSV")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                    }
                }

                Button {
                    showCSVFileImporter = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("选择 CSV 文件")
                            Text("从本机选择已准备好的 CSV 文件导入")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
                .disabled(isImporting)
            } header: {
                Text("CSV 导入")
            } footer: {
                Text("CSV 需包含表头：课程名,教师,地点,学分,周次,单双周,星期,起始节,结束节。课程名、星期、起始节为必填。")
            }
        }
        .listStyle(.insetGrouped)
        .fileImporter(
            isPresented: $showCSVFileImporter,
            allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
            allowsMultipleSelection: false
        ) { result in
            handleCSVFileResult(result)
        }
        .alert("已复制模板", isPresented: $showTemplateCopied) {
            Button("确定") { showTemplateCopied = false }
        } message: {
            Text("CSV 模板已复制到剪贴板，可粘贴到 Excel 或备忘录中填写。")
        }
        .alert("已复制 Prompt", isPresented: $showPromptCopied) {
            Button("确定") { showPromptCopied = false }
        } message: {
            Text("Prompt 已复制到剪贴板。在 ChatGPT、Claude 等 App 中粘贴，在底部填入你的课表信息，AI 会生成可导入的 CSV。")
        }
    }

    private func handleCSVFileResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importError = "无法访问所选文件"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                let string = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16)
                    ?? String(data: data, encoding: .ascii)
                    ?? ""
                performCSVImport(csvString: string)
            } catch {
                importError = "读取文件失败：\(error.localizedDescription)"
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func performCSVImport(csvString: String) {
        isImporting = true
        defer { isImporting = false }

        switch CSVParser.parse(csvString: csvString) {
        case .success(let parsed):
            importFromParsedCourses(parsed)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func importFromParsedCourses(_ parsed: [ParsedCourseItem]) {
        seedDefaultPresetsIfNeeded(modelContext: modelContext)
        let presetsList = (try? modelContext.fetch(FetchDescriptor<TimeSlotPreset>())) ?? []
        let preset = presetForImport(presetsList: presetsList)
        let maxPeriodNeeded = parsed.map { $0.periodEnd }.max() ?? 0

        switch importAction {
        case .overwrite:
            guard let schedule = activeSchedule else {
                importError = "未找到当前课表。"
                return
            }
            extendPresetToCoverPeriodIfNeeded(preset: preset, requiredPeriodCount: maxPeriodNeeded, modelContext: modelContext)
            for c in schedule.courses ?? [] {
                modelContext.delete(c)
            }
            schedule.courses = []
            addParsedCourses(parsed, to: schedule, preset: preset)
            try? modelContext.save()
            refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
            scheduleCourseReminders(modelContext: modelContext)
            importSuccessCount = parsed.count
        case .newSchedule:
            extendPresetToCoverPeriodIfNeeded(preset: preset, requiredPeriodCount: maxPeriodNeeded, modelContext: modelContext)
            let semesterStart = defaultSemesterStartDate()
            let newName = newScheduleName()
            let newSchedule = Schedule(name: newName, semesterStartDate: semesterStart)
            newSchedule.timeSlotPreset = preset
            modelContext.insert(newSchedule)
            addParsedCourses(parsed, to: newSchedule, preset: preset)
            try? modelContext.save()
            activeScheduleName = newName
            refreshWidgetData(modelContext: modelContext, activeScheduleName: newName)
            scheduleCourseReminders(modelContext: modelContext)
            importSuccessCount = parsed.count
        }
    }

    /// 导入时使用的时间预设：覆盖当前课表时用该课表绑定的预设，新建时用全局默认
    private func presetForImport(presetsList: [TimeSlotPreset]) -> TimeSlotPreset? {
        switch importAction {
        case .overwrite:
            return activeSchedule?.timeSlotPreset ?? presetsList.first { $0.name == activeTimeSlotPresetName } ?? presetsList.first
        case .newSchedule:
            return presetsList.first { $0.name == activeTimeSlotPresetName } ?? presetsList.first
        }
    }

    // MARK: - Step 3: 院校 / 教务系统（Tab）

    private var chooseSourceView: some View {
        VStack(spacing: 0) {
            Picker("来源", selection: $sourceTab) {
                ForEach(SourceTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if sourceTab == .school {
                // 院校 Tab：预配置的学校列表
                List {
                    Section {
                        ForEach(SchoolInfo.all) { school in
                            Button {
                                selectedSchool = school
                                importConfig = ImportConfig(academicAffairsType: school.academicAffairsType, entryURL: school.entryURL)
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
                        Text("选择院校")
                    } footer: {
                        Text("将使用该学校对应的教务系统解析规则。打开教务系统后，请进入「个人课表查询」页面，再点击右上角下载按钮导入。")
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                // 教务系统 Tab：按系统类型选择，需用户自行输入教务网址
                List {
                    Section {
                        ForEach(AcademicAffairsType.allCases, id: \.self) { type in
                            Button {
                                selectedSystemType = type
                                // 使用 about:blank，用户可在浏览器地址栏输入本校教务网址
                                let blankURL = URL(string: "about:blank")!
                                importConfig = ImportConfig(academicAffairsType: type, entryURL: blankURL)
                                step = .browser
                            } label: {
                                HStack {
                                    Text(type.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    } header: {
                        Text("选择教务系统")
                    } footer: {
                        Text("若您的学校不在院校列表中，可选择对应的教务系统类型。打开浏览器后，请在地址栏输入您学校的教务系统网址，登录并进入课表页面后导入。")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Step 4: 内嵌浏览器

    private var browserView: some View {
        Group {
            if let config = importConfig {
                VStack(spacing: 0) {
                    Text("请登录并进入「个人课表查询」页面后，点击右上角下载按钮导入。可修改上方网址跳转。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                    AcademicAffairsWebView(
                        initialURL: config.entryURL,
                        urlBarText: $urlBarText,
                        pendingLoadURL: $pendingLoadURL,
                        requestHTML: $requestHTML
                    ) { _, html in
                        performImport(html: html, config: config)
                    }
                }
            } else {
                ContentUnavailableView("未选择来源", systemImage: "building.2")
            }
        }
        .onChange(of: step) { _, newStep in
            if newStep == .browser, let config = importConfig {
                // about:blank 时留空，让用户输入本校教务网址
                urlBarText = config.entryURL.scheme == "about" ? "" : config.entryURL.absoluteString
            }
        }
        .onChange(of: requestHTML) { _, newVal in
            if newVal, importConfig != nil { isImporting = true }
        }
    }

    private func performImport(html: String, config: ImportConfig) {
        defer { isImporting = false }
        let parsed: [ParsedCourseItem]
        switch config.academicAffairsType {
        case .zhengFang:
            parsed = ZhengFangHTMLParser.parse(html: html)
        }
        if parsed.isEmpty {
            importError = "未能从当前页面解析到课程，请确保已打开「个人课表查询」的课表页面。"
            return
        }
        seedDefaultPresetsIfNeeded(modelContext: modelContext)
        let presetsList = (try? modelContext.fetch(FetchDescriptor<TimeSlotPreset>())) ?? []
        let preset = presetForImport(presetsList: presetsList)
        let maxPeriodNeeded = parsed.map { $0.periodEnd }.max() ?? 0

        switch importAction {
        case .overwrite:
            guard let schedule = activeSchedule else {
                importError = "未找到当前课表。"
                return
            }
            extendPresetToCoverPeriodIfNeeded(preset: preset, requiredPeriodCount: maxPeriodNeeded, modelContext: modelContext)
            for c in schedule.courses ?? [] {
                modelContext.delete(c)
            }
            schedule.courses = []
            addParsedCourses(parsed, to: schedule, preset: preset)
            try? modelContext.save()
            refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
            scheduleCourseReminders(modelContext: modelContext)
            importSuccessCount = parsed.count
        case .newSchedule:
            extendPresetToCoverPeriodIfNeeded(preset: preset, requiredPeriodCount: maxPeriodNeeded, modelContext: modelContext)
            let semesterStart = defaultSemesterStartDate()
            let newName = newScheduleName()
            let newSchedule = Schedule(name: newName, semesterStartDate: semesterStart)
            newSchedule.timeSlotPreset = preset
            modelContext.insert(newSchedule)
            addParsedCourses(parsed, to: newSchedule, preset: preset)
            try? modelContext.save()
            activeScheduleName = newName
            refreshWidgetData(modelContext: modelContext, activeScheduleName: newName)
            scheduleCourseReminders(modelContext: modelContext)
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
            schedule.courses = (schedule.courses ?? []) + [course]
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
