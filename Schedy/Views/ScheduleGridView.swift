//
//  ScheduleGridView.swift
//  schedy
//
//  主课程表网格：按周几 + 节次展示，左右滑动切换周次，表头显示当日日期
//

import SwiftData
import SwiftUI

private let maxWeeks = 25

/// 复用 DateFormatter，避免在滚动/翻页时重复创建造成卡顿
private enum ScheduleDateFormatters {
    static let shortMD: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
}

/// 当周课程网格预计算结果，避免每个格子重复 filter 课程列表，减轻翻页卡顿
private struct WeekCourseGrid {
    /// [dayIndex 0..<7][slotIndex]，该格是否有课程在此「开始」且本周有课
    let starting: [[Course?]]
    /// [dayIndex 0..<7][slotIndex]，该格是否有课程在此「开始」且仅其他周有课（非本周半透明）
    let notThisWeek: [[Course?]]
    /// [dayIndex 0..<7][slotIndex]，该格是否被任意本周课程占用
    let hasCourse: [[Bool]]

    init?(week: Int, schedule: Schedule?, sortedSlots: [TimeSlotItem], maxWeeks: Int) {
        guard let schedule = schedule else { return nil }
        let slotCount = sortedSlots.count
        var starting = [[Course?]](repeating: [Course?](repeating: nil, count: slotCount), count: 7)
        var notThisWeek = [[Course?]](repeating: [Course?](repeating: nil, count: slotCount), count: 7)
        var hasCourse = [[Bool]](repeating: [Bool](repeating: false, count: slotCount), count: 7)

        for c in schedule.courses {
            let applies = c.appliesToWeek(week)
            let hasFuture = week < maxWeeks && (week + 1...maxWeeks).contains(where: { c.appliesToWeek($0) })
            let dayIndex = c.dayOfWeek - 1
            guard dayIndex >= 0, dayIndex < 7 else { continue }
            let startPeriod = c.periodIndex
            let endPeriod = c.effectivePeriodEnd

            for (slotIndex, slot) in sortedSlots.enumerated() {
                let period = slot.periodIndex
                if period >= startPeriod && period <= endPeriod && applies {
                    hasCourse[dayIndex][slotIndex] = true
                }
                if period == startPeriod {
                    if applies {
                        starting[dayIndex][slotIndex] = c
                    } else if hasFuture {
                        notThisWeek[dayIndex][slotIndex] = c
                    }
                }
            }
        }
        self.starting = starting
        self.notThisWeek = notThisWeek
        self.hasCourse = hasCourse
    }
}

struct ScheduleGridView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Schedule.name) private var schedules: [Schedule]
    @AppStorage("activeScheduleName") private var activeScheduleName: String = "我的课程表"

    /// 当前查看的周次（1-based），左右滑动切换
    @State private var viewingWeek: Int = 1
    @State private var showAddCourse = false
    @State private var showAcademicAffairsImport = false
    @State private var showHeaderMenu = false
    @State private var courseToPreview: Course?
    @State private var courseToEdit: Course?

    private let dayLabels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    private let dayIndices = Array(1...7)

    private var activeSchedule: Schedule? {
        schedules.first { $0.name == activeScheduleName } ?? schedules.first
    }

    private var activePreset: TimeSlotPreset? {
        activeSchedule?.timeSlotPreset
    }

    private var sortedSlots: [TimeSlotItem] {
        guard let p = activePreset else { return [] }
        return p.slots.sorted { $0.periodIndex < $1.periodIndex }
    }

    private let rowHeight: CGFloat = 52

    /// 根据学期第一天计算「第 week 周、周 day」对应的日期（周一=1）
    private func date(forWeek week: Int, day: Int) -> Date? {
        guard let schedule = activeSchedule else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: schedule.semesterStartDate)
        let days = (week - 1) * 7 + (day - 1)
        return cal.date(byAdding: .day, value: days, to: start)
    }

    private func dateString(forWeek week: Int, day: Int) -> String {
        guard let d = date(forWeek: week, day: day) else { return "" }
        return ScheduleDateFormatters.shortMD.string(from: d)
    }

    /// 今日日期文案，如 "2月26日"
    private var todayDateString: String {
        ScheduleDateFormatters.monthDay.string(from: Date())
    }

    /// 根据当前日期与学期第一天计算：第X周 / 未开学 / 学期已结束
    private var semesterWeekStatusString: String {
        guard let schedule = activeSchedule else { return "—" }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.startOfDay(for: schedule.semesterStartDate)
        if today < start { return "未开学" }
        let days = cal.dateComponents([.day], from: start, to: today).day ?? 0
        let week = days / 7 + 1
        if week > maxWeeks { return "学期已结束" }
        return "第 \(week) 周"
    }

    /// 打开 app 时默认显示的周次：当前周；未开学或学期已结束则为第 1 周
    private var defaultViewingWeek: Int {
        guard let schedule = activeSchedule else { return 1 }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.startOfDay(for: schedule.semesterStartDate)
        if today < start { return 1 }
        let days = cal.dateComponents([.day], from: start, to: today).day ?? 0
        let week = days / 7 + 1
        if week > maxWeeks { return 1 }
        return min(max(1, week), maxWeeks)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $viewingWeek) {
                ForEach(1...maxWeeks, id: \.self) { week in
                    scheduleTable(week: week)
                        .tag(week)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.2), value: viewingWeek)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                floatingHeader
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationBarHidden(true)
            .sheet(isPresented: $showAcademicAffairsImport) {
                ImportFromAcademicAffairsView()
            }
            .sheet(isPresented: $showAddCourse) {
                CourseEditSheet(
                    course: nil,
                    schedule: activeSchedule,
                    preset: activePreset,
                    defaultWeek: viewingWeek,
                    defaultDay: nil,
                    defaultPeriod: nil
                )
            }
            .sheet(item: $courseToPreview) { c in
                CoursePreviewSheet(course: c) {
                    courseToPreview = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        courseToEdit = c
                    }
                }
            }
            .sheet(item: $courseToEdit) { c in
                CourseEditSheet(course: c, schedule: activeSchedule, preset: activePreset)
            }
            .sheet(isPresented: $showHeaderMenu) {
                HeaderMenuSheet(
                    schedules: schedules,
                    activeScheduleName: activeScheduleName,
                    onSelectSchedule: { activeScheduleName = $0; showHeaderMenu = false },
                    onAddCourse: { showHeaderMenu = false; showAddCourse = true },
                    onImport: { showHeaderMenu = false; showAcademicAffairsImport = true },
                    onDismiss: { showHeaderMenu = false }
                )
            }
            .onAppear {
                seedDefaultScheduleIfNeeded(modelContext: modelContext)
                if activeScheduleName.isEmpty {
                    activeScheduleName = schedules.first?.name ?? "我的课程表"
                }
                viewingWeek = defaultViewingWeek
                refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
                scheduleCourseReminders(modelContext: modelContext, activeScheduleName: activeScheduleName)
                // 延迟再刷一次，确保 @Query 已就绪、数据已写入 App Group，小组件能读到
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
                }
            }
            .onChange(of: activeScheduleName) { _, _ in
                viewingWeek = defaultViewingWeek
                refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
                scheduleCourseReminders(modelContext: modelContext, activeScheduleName: activeScheduleName)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshWidgetData(modelContext: modelContext, activeScheduleName: activeScheduleName)
                    scheduleCourseReminders(modelContext: modelContext, activeScheduleName: activeScheduleName)
                }
            }
        }
    }

    /// 悬浮于内容之上的顶部栏：标题 + 菜单、今日/周次、左右滑动提示（毛玻璃，提高信息密度）
    private var floatingHeader: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(activeSchedule?.name ?? "课程表")
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        showHeaderMenu = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            weekIndicator
        }
        .background(.ultraThinMaterial)
    }

    /// 当前周次指示 + 左右滑动提示
    private var weekIndicator: some View {
        HStack {
            Text("第 \(viewingWeek) 周")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            Text(todayDateString)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            Text(semesterWeekStatusString)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func scheduleTable(week: Int) -> some View {
        let grid = WeekCourseGrid(week: week, schedule: activeSchedule, sortedSlots: sortedSlots, maxWeeks: maxWeeks)
        return VStack(spacing: 0) {
            // 固定表头：不随滚动
            HStack(alignment: .top, spacing: 0) {
                timeColumnHeader
                ForEach(dayIndices, id: \.self) { day in
                    dayHeader(day: day, week: week)
                }
            }
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        ForEach(Array(sortedSlots.enumerated()), id: \.element.periodIndex) { slotIndex, slot in
                            scheduleRow(periodSlot: slot, grid: grid, slotIndex: slotIndex)
                        }
                    }
                    .overlay(alignment: .top) {
                        courseBlocksOverlay(grid: grid)
                    }
                }
                .padding(.bottom, 24)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 与表格行同结构的 overlay，只画课程块；每行固定 52pt，课程块用 overlay 向下溢出（使用预计算 grid 减轻翻页卡顿）
    private func courseBlocksOverlay(grid: WeekCourseGrid?) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(sortedSlots.enumerated()), id: \.element.periodIndex) { slotIndex, _ in
                HStack(alignment: .top, spacing: 0) {
                    Color.clear.frame(width: 56).frame(height: rowHeight)
                    ForEach(dayIndices, id: \.self) { day in
                        let dayIndex = day - 1
                        let c = grid?.starting[dayIndex][slotIndex]
                        let cNotThisWeek = grid?.notThisWeek[dayIndex][slotIndex]
                        Group {
                            if let c = c {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: rowHeight)
                                    .overlay(alignment: .top) {
                                        CourseCellView(course: c, rowHeight: rowHeight) {
                                            courseToPreview = c
                                        }
                                        .frame(height: rowHeight * CGFloat(c.periodSpan) - 2)
                                        .padding(1)
                                    }
                            } else if let c = cNotThisWeek {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: rowHeight)
                                    .overlay(alignment: .top) {
                                        CourseCellView(course: c, rowHeight: rowHeight, isNotThisWeek: true) {
                                            courseToPreview = c
                                        }
                                        .frame(height: rowHeight * CGFloat(c.periodSpan) - 2)
                                        .padding(1)
                                    }
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: rowHeight)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .frame(height: rowHeight)
            }
        }
        .drawingGroup(opaque: false, colorMode: .nonLinear)
    }

    private var timeColumnHeader: some View {
        VStack(spacing: 2) {
            Text("节次")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(width: 48, height: 56)
    }

    private func dayHeader(day: Int, week: Int) -> some View {
        VStack(spacing: 2) {
            Text(dayLabels[day - 1])
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(dateString(forWeek: week, day: day))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
    }

    /// 表格行：只画时间列 + 空位/占位，课程块由 courseBlocksOverlay 统一画在上层（使用预计算 grid）
    private func scheduleRow(periodSlot: TimeSlotItem, grid: WeekCourseGrid?, slotIndex: Int) -> some View {
        let period = periodSlot.periodIndex
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .center, spacing: 2) {
                Text("\(period)")
                    .font(.caption)
                    .fontWeight(.medium)
                Text(periodSlot.startTimeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(periodSlot.endTimeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 48, alignment: .center)
            .frame(height: rowHeight)
            .padding(.vertical, 6)

            ForEach(dayIndices, id: \.self) { day in
                let hasCourse = grid?.hasCourse[day - 1][slotIndex] ?? false
                if hasCourse {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                }
            }
        }
        .frame(height: rowHeight)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - 课程块色板（插画风，由课程名稳定哈希决定颜色；前景白字）
private enum MacaronPalette {
    /// 插画风色系：草莓红、南瓜橙、蜂蜜黄、牛油果绿、青柠绿、天空蓝、湖水蓝、葡萄紫、蓝莓紫、覆盆子粉、可可棕
    static let colors: [Color] = [
        Color(red: 214/255.0, green: 69/255.0, blue: 80/255.0),   // 草莓红 #D64550
        Color(red: 230/255.0, green: 126/255.0, blue: 34/255.0),   // 南瓜橙 #E67E22
        Color(red: 197/255.0, green: 157/255.0, blue: 15/255.0),  // 蜂蜜黄 #C59D0F
        Color(red: 46/255.0, green: 139/255.0, blue: 87/255.0),   // 牛油果绿 #2E8B57
        Color(red: 31/255.0, green: 175/255.0, blue: 139/255.0),  // 青柠绿 #1FAF8B
        Color(red: 47/255.0, green: 128/255.0, blue: 237/255.0),  // 天空蓝 #2F80ED
        Color(red: 27/255.0, green: 108/255.0, blue: 168/255.0), // 湖水蓝 #1B6CA8
        Color(red: 123/255.0, green: 97/255.0, blue: 255/255.0),  // 葡萄紫 #7B61FF
        Color(red: 91/255.0, green: 79/255.0, blue: 207/255.0),   // 蓝莓紫 #5B4FCF
        Color(red: 214/255.0, green: 51/255.0, blue: 132/255.0), // 覆盆子粉 #D63384
        Color(red: 141/255.0, green: 85/255.0, blue: 36/255.0),   // 可可棕 #8D5524
    ]

    /// 由课程名字符串计算稳定哈希值（同一课程名在任何时候都得到相同颜色）
    private static func stableHash(for string: String) -> Int {
        var hash = 5381
        for codeUnit in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(codeUnit)
        }
        return hash
    }

    static func color(forCourseName name: String) -> Color {
        let index = abs(stableHash(for: name)) % colors.count
        return colors[index]
    }
}

// MARK: - 课程预览卡片（点击课程后先展示，右上角可进入编辑）
private struct CoursePreviewSheet: View {
    let course: Course
    var onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var cardAccent: Color { MacaronPalette.color(forCourseName: course.name) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // 顶部色条
                    RoundedRectangle(cornerRadius: 0)
                        .fill(cardAccent.gradient)
                        .frame(height: 6)

                    VStack(alignment: .leading, spacing: 20) {
                        Text(course.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        VStack(alignment: .leading, spacing: 12) {
                            row(icon: "person.fill", text: course.teacher)
                            row(icon: "mappin.circle.fill", text: course.location)
                            row(icon: "calendar", text: course.weekRangesDisplayString)
                            row(icon: "clock.fill", text: "\(course.dayOfWeekName) · 第 \(course.periodIndex)–\(course.effectivePeriodEnd) 节")
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onEdit()
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                }
            }
        }
    }

    private func row(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(cardAccent)
                .frame(width: 22, alignment: .center)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 顶部栏菜单 Sheet（替代 Menu，避免 safeAreaInset 内 Menu 触发的 _UIReparentingView 警告）
private struct HeaderMenuSheet: View {
    let schedules: [Schedule]
    let activeScheduleName: String
    let onSelectSchedule: (String) -> Void
    let onAddCourse: () -> Void
    let onImport: () -> Void
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onAddCourse()
                        dismiss()
                    } label: {
                        Label("添加课程", systemImage: "plus.circle.fill")
                    }
                    Button {
                        onImport()
                        dismiss()
                    } label: {
                        Label("从教务导入", systemImage: "square.and.arrow.down")
                    }
                }
                if schedules.count > 1 {
                    Section {
                        ForEach(schedules, id: \Schedule.name) { (s: Schedule) in
                            Button {
                                onSelectSchedule(s.name)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(s.name)
                                    if s.name == activeScheduleName {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("切换课程表")
                    }
                }
            }
            .navigationTitle("操作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 课程格子（支持跨多节高度；可选「非本周」半透明样式）
private struct CourseCellView: View {
    let course: Course
    var rowHeight: CGFloat = 52
    /// 为 true 时：半透明显示并标注 [非本周]（该时间段在其他周有课、本周无课）
    var isNotThisWeek: Bool = false
    let onTap: () -> Void

    private var cellHeight: CGFloat { rowHeight * CGFloat(course.periodSpan) }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.name)
                    .font(.caption)
                    .fontWeight(.heavy)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.white)
                Text(course.location)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity)
            .padding(6)
            .background(courseCellColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
//            .overlay(
//                RoundedRectangle(cornerRadius: 12)
//                    .stroke(Color.white, lineWidth: 1)
//            )
            .opacity(isNotThisWeek ? 0.55 : 0.9)
        }
        .buttonStyle(.plain)
    }

    private var courseCellColor: Color {
        MacaronPalette.color(forCourseName: course.name).opacity(isNotThisWeek ? 0.7 : 0.92)
    }
}

#Preview {
    ScheduleGridView()
        .modelContainer(for: [Schedule.self, Course.self, TimeSlotPreset.self, TimeSlotItem.self], inMemory: true)
}
