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
    @AppStorage(ScheduleDisplayKeys.activeScheduleName) private var activeScheduleName: String = String(localized: "schedule.default.name", defaultValue: "My Timetable")
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
    @State private var schoolSearchText = ""

    private var activeSchedule: Schedule? {
        schedules.first { $0.name == activeScheduleName } ?? schedules.first
    }

    private struct SchoolSearchEntry: Identifiable {
        let school: SchoolInfo
        let sectionKey: String
        let sortKey: String
        let searchKey: String

        var id: String { school.id }
    }

    private struct SchoolSection: Identifiable {
        let id: String
        let title: String
        let schools: [SchoolSearchEntry]
    }

    private static let allSchoolEntries: [SchoolSearchEntry] = SchoolInfo.all.map { school in
        let pinyin = latinString(from: school.name)
        let initials = pinyin
            .split(separator: " ")
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()
        let compactPinyin = pinyin.replacingOccurrences(of: " ", with: "")
        let section = pinyinSectionKey(for: school.name)
        let searchKey = [school.name.lowercased(), compactPinyin.lowercased(), initials.lowercased()]
            .joined(separator: " ")
        return SchoolSearchEntry(
            school: school,
            sectionKey: section,
            sortKey: "\(section)-\(compactPinyin)-\(school.name)",
            searchKey: searchKey
        )
    }

    private var filteredSchoolEntries: [SchoolSearchEntry] {
        let query = schoolSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else {
            return Self.allSchoolEntries
        }
        return Self.allSchoolEntries.filter { $0.searchKey.contains(query) }
    }

    private var schoolSections: [SchoolSection] {
        let grouped = Dictionary(grouping: filteredSchoolEntries, by: \.sectionKey)
        return grouped
            .map { key, value in
                SchoolSection(
                    id: key,
                    title: key,
                    schools: value.sorted { $0.sortKey < $1.sortKey }
                )
            }
            .sorted { lhs, rhs in
                if lhs.title == "#" { return false }
                if rhs.title == "#" { return true }
                return lhs.title < rhs.title
            }
    }

    private var schoolIndexTitles: [String] {
        schoolSections.map(\.title)
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

        var displayName: String {
            switch self {
            case .school: return String(localized: "import.school.list.title", defaultValue: "School")
            case .system: return String(localized: "import.school.system.title", defaultValue: "School System")
            }
        }
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
            .schedyPageStyle()
            .navigationTitle(String(localized: "import.title", defaultValue: "Import Timetable"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .chooseImportMethod || step == .chooseSource || step == .browser || step == .csvImport {
                        Button(String(localized: "common.action.back", defaultValue: "Back")) {
                            if step == .browser { step = .chooseSource }
                            else if step == .chooseSource { step = .chooseImportMethod }
                            else if step == .csvImport { step = .chooseImportMethod }
                            else { step = .chooseAction }
                        }
                    } else {
                        Button(String(localized: "common.action.cancel", defaultValue: "Cancel")) { dismiss() }
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
            .alert(String(localized: "import.error.title", defaultValue: "Import Failed"), isPresented: .constant(importError != nil)) {
                Button(String(localized: "common.action.ok", defaultValue: "OK")) { importError = nil }
            } message: {
                if let msg = importError { Text(msg) }
            }
            .alert(String(localized: "import.success.title", defaultValue: "Import Complete"), isPresented: .constant(importSuccessCount != nil)) {
                Button(String(localized: "common.action.ok", defaultValue: "OK")) {
                    importSuccessCount = nil
                    dismiss()
                }
            } message: {
                if let n = importSuccessCount {
                    Text(String(localized: "import.success.course_count", defaultValue: "Imported \(n) courses."))
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
                            Text(String(localized: "import.mode.overwrite_title", defaultValue: "Replace Current Timetable"))
                            Text(String(localized: "import.mode.overwrite_description", defaultValue: "Replace courses in “\(activeSchedule?.name ?? String(localized: "schedule.selection.current", defaultValue: "Current Timetable"))”."))
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
                            Text(String(localized: "import.mode.new_title", defaultValue: "New Timetable"))
                            Text(String(localized: "import.mode.new_description", defaultValue: "Import into a new timetable and keep your existing timetables."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "plus.rectangle.on.folder")
                    }
                }
            } header: {
                Text(String(localized: "import.mode.title", defaultValue: "Import Mode"))
            } footer: {
                Text(String(localized: "import.mode.description", defaultValue: "Replace courses in the current timetable or import into a new one."))
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
                            Text(String(localized: "import.school.action", defaultValue: "Import from School System"))
                            Text(String(localized: "import.school.action_description", defaultValue: "Import from your school's academic system website."))
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
                            Text(String(localized: "import.csv.action", defaultValue: "Import from CSV"))
                            Text(String(localized: "import.csv.description", defaultValue: "Use a CSV file or generate one with AI."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "tablecells")
                    }
                }
            } header: {
                Text(String(localized: "import.source.choose_title", defaultValue: "Import Source"))
            } footer: {
                Text(String(localized: "import.source.description", defaultValue: "Open your school's academic system, navigate to your timetable, then tap the download button in the top right to import. You can also import a CSV file or ask AI to generate one."))
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
                            Text(String(localized: "import.csv.template.copy_action", defaultValue: "Copy CSV Template"))
                            Text(String(localized: "import.csv.template.description", defaultValue: "Copy the template, then paste it into Excel or a text editor to fill it in."))
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
                            Text(String(localized: "import.csv.prompt.copy_action", defaultValue: "Copy AI Prompt"))
                            Text(String(localized: "import.csv.prompt.description", defaultValue: "Paste into ChatGPT, Claude, or another AI app to generate a CSV from your timetable."))
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
                            Text(String(localized: "import.csv.file.choose_action", defaultValue: "Choose CSV File"))
                            Text(String(localized: "import.csv.file.description", defaultValue: "Choose a CSV file from your device."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
                .disabled(isImporting)
            } header: {
                Text(String(localized: "import.csv.title", defaultValue: "CSV Import"))
            } footer: {
                Text(String(localized: "import.csv.format.description", defaultValue: "The CSV must include these headers: 课程名,教师,地点,学分,周次,单双周,星期,起始节,结束节. Course name (课程名), weekday (星期), and start period (起始节) are required. Keep the Chinese headers exactly as shown."))
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
        .alert(String(localized: "import.csv.template.copied_title", defaultValue: "Template Copied"), isPresented: $showTemplateCopied) {
            Button(String(localized: "common.action.ok", defaultValue: "OK")) { showTemplateCopied = false }
        } message: {
            Text(String(localized: "import.csv.template.copied_message", defaultValue: "CSV template copied. Paste it into Excel or Notes to fill it in."))
        }
        .alert(String(localized: "import.csv.prompt.copied_title", defaultValue: "Prompt Copied"), isPresented: $showPromptCopied) {
            Button(String(localized: "common.action.ok", defaultValue: "OK")) { showPromptCopied = false }
        } message: {
            Text(String(localized: "import.csv.prompt.copied_message", defaultValue: "Prompt copied. Paste it into ChatGPT, Claude, or another AI app, then add your timetable details at the bottom to generate an importable CSV."))
        }
    }

    private func handleCSVFileResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importError = String(localized: "import.csv.error.file_access", defaultValue: "Unable to access the selected file.")
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
                importError = String(localized: "import.csv.error.file_read", defaultValue: "Unable to read the file: \(error.localizedDescription)")
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
        applyParsedCourses(parsed, presetsList: presetsList)
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

    private func applyParsedCourses(_ parsed: [ParsedCourseItem], presetsList: [TimeSlotPreset]) {
        let preset = presetForImport(presetsList: presetsList)
        let maxPeriodNeeded = parsed.map { $0.periodEnd }.max() ?? 0
        extendPresetToCoverPeriodIfNeeded(preset: preset, requiredPeriodCount: maxPeriodNeeded, modelContext: modelContext)

        let targetSchedule: Schedule
        switch importAction {
        case .overwrite:
            guard let schedule = activeSchedule else {
                importError = String(localized: "import.error.schedule_missing", defaultValue: "The current timetable could not be found.")
                return
            }
            for c in schedule.courses ?? [] { modelContext.delete(c) }
            schedule.courses = []
            targetSchedule = schedule
        case .newSchedule:
            let newName = newScheduleName()
            let newSchedule = Schedule(name: newName, semesterStartDate: defaultSemesterStartDate())
            newSchedule.timeSlotPreset = preset
            modelContext.insert(newSchedule)
            activeScheduleName = newName
            targetSchedule = newSchedule
        }

        addParsedCourses(parsed, to: targetSchedule, preset: preset)
        try? modelContext.save()
        refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
        scheduleCourseReminders(modelContext: modelContext)
        importSuccessCount = parsed.count
    }

    // MARK: - Step 3: 院校 / 教务系统（Tab）

    private var chooseSourceView: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "import.source.title", defaultValue: "Source"), selection: $sourceTab) {
                ForEach(SourceTab.allCases, id: \.self) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if sourceTab == .school {
                // 院校 Tab：预配置的学校列表
                ScrollViewReader { proxy in
                    ZStack(alignment: .trailing) {
                        List {
                            Section {
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.secondary)
                                    TextField(String(localized: "import.school.search_placeholder", defaultValue: "Search by school name or pinyin initials"), text: $schoolSearchText)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                    if !schoolSearchText.isEmpty {
                                        Button {
                                            schoolSearchText = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.tertiary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 6)
                            }

                            ForEach(schoolSections) { section in
                                Section(section.title) {
                                    ForEach(section.schools) { entry in
                                        let school = entry.school
                                        Button {
                                            guard school.isEnabled,
                                                  let academicAffairsType = school.academicAffairsType,
                                                  let entryURL = school.entryURL else {
                                                return
                                            }
                                            selectedSchool = school
                                            importConfig = ImportConfig(academicAffairsType: academicAffairsType, entryURL: entryURL)
                                            step = .browser
                                        } label: {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(school.name)
                                                        .font(.headline)
                                                        .foregroundStyle(.primary)
                                                    Text(school.typeDisplayName)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                if school.isEnabled {
                                                    Image(systemName: "chevron.right")
                                                        .foregroundStyle(.tertiary)
                                                } else {
                                                    Text(String(localized: "import.school.status.unsupported", defaultValue: "Not Supported Yet"))
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        .disabled(!school.isEnabled)
                                    }
                                }
                                .id(section.id)
                            }
                            Section {
                                EmptyView()
                            } footer: {
                                Text(String(localized: "import.school.description", defaultValue: "Import uses the selected school's parsing rules. Search by school name or pinyin initials. Sign in, open the personal timetable page (“个人课表查询”), then tap the download button in the top right."))
                            }
                        }
                        .listStyle(.insetGrouped)

                        if schoolIndexTitles.count > 1 {
                            VStack(spacing: 2) {
                                ForEach(schoolIndexTitles, id: \.self) { title in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            proxy.scrollTo(title, anchor: .top)
                                        }
                                    } label: {
                                        Text(title)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 16)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.trailing, 4)
                        }
                    }
                }
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
                        Text(String(localized: "import.school.system.choose_title", defaultValue: "Choose School System"))
                    } footer: {
                        Text(String(localized: "import.school.system.description", defaultValue: "If your school isn't listed, select its academic system. Enter your school's URL in the browser, sign in, and open your timetable to import."))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private static func latinString(from text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return (mutable as String)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private static func pinyinSectionKey(for name: String) -> String {
        let latin = latinString(from: name)
        if let first = latin.first, first.isLetter {
            return String(first)
        }
        return "#"
    }

    // MARK: - Step 4: 内嵌浏览器

    private var browserView: some View {
        Group {
            if let config = importConfig {
                VStack(spacing: 0) {
                    Text(String(localized: "import.school.browser_instructions", defaultValue: "Sign in and open your timetable, then tap the download button in the top right to import."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(SchedyAppearance.background)
                    AcademicAffairsWebView(
                        initialURL: config.entryURL,
                        academicAffairsType: config.academicAffairsType,
                        urlBarText: $urlBarText,
                        pendingLoadURL: $pendingLoadURL,
                        requestHTML: $requestHTML
                    ) { _, result in
                        handleInjectedCourseData(result, config: config)
                    }
                }
            } else {
                ContentUnavailableView(String(localized: "import.source.empty", defaultValue: "No Source Selected"), systemImage: "building.2")
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

    private func handleInjectedCourseData(_ result: Result<String, Error>, config: ImportConfig) {
        switch result {
        case .success(let payload):
            let type = config.academicAffairsType
            DispatchQueue.global(qos: .userInitiated).async {
                let parsed = Self.parseAcademicAffairsPayload(payload, type: type)
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.finishImport(parsed: parsed, config: config)
                }
            }
        case .failure(let error):
            isImporting = false
            importError = error.localizedDescription
        }
    }

    private static func parseAcademicAffairsPayload(_ payload: String, type: AcademicAffairsType) -> [ParsedCourseItem] {
        if payload.hasPrefix("HTML_PAGE|") {
            let html = String(payload.dropFirst("HTML_PAGE|".count))
            switch type {
            case .qiangZhi:
                return QiangZhiHTMLParser.parse(html: html)
            case .chaoXing:
                return ChaoXingHTMLParser.parse(html: html)
            default:
                return AcademicAffairsInjectedCourseParser.parseCompact("HTML|" + html, type: type)
            }
        }
        return AcademicAffairsInjectedCourseParser.parseCompact(payload, type: type)
    }

    private func finishImport(parsed: [ParsedCourseItem], config: ImportConfig) {
        if parsed.isEmpty {
            let pageName: String
            switch config.academicAffairsType {
            case .qiangZhi: pageName = "学期理论课表"
            case .chaoXing: pageName = "课程表"
            case .kingo, .urp, .south, .wisedu: pageName = "课表页面"
            default: pageName = "个人课表查询"
            }
            importError = String(localized: "import.school.error.wrong_page", defaultValue: "No courses could be read from this page. Open the “\(pageName)” timetable page and try again.")
            return
        }
        seedDefaultPresetsIfNeeded(modelContext: modelContext)
        let presetsList = (try? modelContext.fetch(FetchDescriptor<TimeSlotPreset>())) ?? []
        applyParsedCourses(parsed, presetsList: presetsList)
    }

    private func addParsedCourses(_ items: [ParsedCourseItem], to schedule: Schedule, preset: TimeSlotPreset?) {
        for item in items {
            let course = Course(
                name: item.name,
                teacher: item.teacher.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
                location: item.location.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
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
        }
    }

    private func newScheduleName() -> String {
        let base = String(localized: "schedule.default.imported_name", defaultValue: "Imported Timetable")
        var name = base
        var n = 1
        while schedules.contains(where: { $0.name == name }) {
            n += 1
            name = "\(base) \(n)"
        }
        return name
    }
}
