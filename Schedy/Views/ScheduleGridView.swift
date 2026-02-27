//
//  ScheduleGridView.swift
//  schedy
//
//  主课程表网格：按周几 + 节次展示，左右滑动切换周次，表头显示当日日期
//

import SwiftData
import SwiftUI

private let maxWeeks = 25

/// 课程预览的上下文：课程 + 来源周 + 是否非本周（半透明），用于 sheet(item:) 保证周次一致
private struct CoursePreviewContext: Identifiable {
    let course: Course
    let sourceWeek: Int
    let isNotThisWeek: Bool
    let id = UUID()
}

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
    /// 调课时显示跨节数，0 表示使用 course.periodSpan
    let startingPeriodSpanOverride: [[Int]]
    /// 该格课程若因调课显示，则为该条调课记录（用于点击时用 r.week 作为来源周，避免误成「当前表周」）
    let startingReschedule: [[CourseReschedule?]]
    /// [dayIndex 0..<7][slotIndex]，该格是否有课程在此「开始」且仅其他周有课（非本周半透明）
    let notThisWeek: [[Course?]]
    /// [dayIndex 0..<7][slotIndex]，该格是否被任意本周课程占用
    let hasCourse: [[Bool]]

    init?(week: Int, schedule: Schedule?, sortedSlots: [TimeSlotItem], maxWeeks: Int) {
        guard let schedule = schedule else { return nil }
        let slotCount = sortedSlots.count
        var starting = [[Course?]](repeating: [Course?](repeating: nil, count: slotCount), count: 7)
        var startingPeriodSpanOverride = [[Int]](repeating: [Int](repeating: 0, count: slotCount), count: 7)
        var startingReschedule = [[CourseReschedule?]](repeating: [CourseReschedule?](repeating: nil, count: slotCount), count: 7)
        var notThisWeek = [[Course?]](repeating: [Course?](repeating: nil, count: slotCount), count: 7)
        var hasCourse = [[Bool]](repeating: [Bool](repeating: false, count: slotCount), count: 7)

        func slotIndex(forPeriod period: Int) -> Int? {
            sortedSlots.firstIndex(where: { $0.periodIndex == period })
        }

        // 1. 正常排课：本周有课且未调课的课程放在原位置
        for c in schedule.courses {
            let applies = c.appliesToWeek(week)
            let hasFuture = week < maxWeeks && (week + 1...maxWeeks).contains(where: { c.appliesToWeek($0) })
            let dayIndex = c.dayOfWeek - 1
            guard dayIndex >= 0, dayIndex < 7 else { continue }
            let startPeriod = c.periodIndex
            let endPeriod = c.effectivePeriodEnd
            let resched = c.reschedule(forWeek: week)

            for (slotIndex, slot) in sortedSlots.enumerated() {
                let period = slot.periodIndex
                if period == startPeriod {
                    if applies {
                        if resched == nil {
                            starting[dayIndex][slotIndex] = c
                        }
                    } else if hasFuture {
                        notThisWeek[dayIndex][slotIndex] = c
                    }
                }
                if applies && resched == nil && period >= startPeriod && period <= endPeriod {
                    hasCourse[dayIndex][slotIndex] = true
                }
            }
        }

        // 2. 调课目标：凡「调至本周」的课程，在本周新时间格显示，并记录是哪条调课（点击时用其来源周）
        for c in schedule.courses {
            for r in c.reschedules where r.effectiveNewWeek == week {
                let newDayIndex = r.newDayOfWeek - 1
                guard newDayIndex >= 0, newDayIndex < 7,
                      let startSlot = slotIndex(forPeriod: r.newPeriodStart) else { continue }
                starting[newDayIndex][startSlot] = c
                startingPeriodSpanOverride[newDayIndex][startSlot] = r.periodSpan
                startingReschedule[newDayIndex][startSlot] = r
                let endSlot = slotIndex(forPeriod: r.newPeriodEnd) ?? startSlot
                for idx in startSlot...min(endSlot, slotCount - 1) {
                    hasCourse[newDayIndex][idx] = true
                }
            }
        }

        self.starting = starting
        self.startingPeriodSpanOverride = startingPeriodSpanOverride
        self.startingReschedule = startingReschedule
        self.notThisWeek = notThisWeek
        self.hasCourse = hasCourse
    }
}

struct ScheduleGridView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Schedule.name) private var schedules: [Schedule]
    @AppStorage("activeScheduleName") private var activeScheduleName: String = "我的课程表"
    @AppStorage(ScheduleDisplayKeys.showHorizontalLines) private var showHorizontalLines: Bool = true
    @AppStorage(ScheduleDisplayKeys.showVerticalLines) private var showVerticalLines: Bool = true
    @AppStorage(ScheduleDisplayKeys.showWeekends) private var showWeekends: Bool = true
    @AppStorage(ScheduleDisplayKeys.firstWeekday) private var firstWeekdayRaw: Int = 2

    /// 当前查看的周次（1-based），左右滑动切换
    @State private var viewingWeek: Int = 1
    /// 用于翻页触觉反馈：仅在实际切换周时触发，避免首次进入时震动
    @State private var lastHapticWeek: Int? = nil
    @State private var showAddCourse = false
    @State private var showAcademicAffairsImport = false
    @State private var showHeaderMenu = false
    /// 点击课程块时带来源周与是否「非本周」，保证调课周次与点击一致；半透明课程仅展示卡片
    @State private var coursePreviewContext: CoursePreviewContext?
    @State private var courseToEdit: Course?

    private let dayLabels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    /// 根据「每周第一天」和「是否显示周末」得到要显示的星期列顺序（1=周一 … 7=周日）
    private var displayDayIndices: [Int] {
        let order: [Int] = firstWeekdayRaw == 1 ? [7, 1, 2, 3, 4, 5, 6] : [1, 2, 3, 4, 5, 6, 7]
        if showWeekends { return order }
        return order.filter { $0 >= 1 && $0 <= 5 }
    }

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
    /// 时间列宽度，表头/表格行/课程块 overlay 共用，保证对齐
    private let timeColumnWidth: CGFloat = 48

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
                    scheduleTable(week: week, viewingWeek: viewingWeek)
                        .tag(week)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.15), value: viewingWeek)
            .onChange(of: viewingWeek) { _, newWeek in
                if lastHapticWeek != nil {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                lastHapticWeek = newWeek
            }
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
            .sheet(item: $coursePreviewContext) { ctx in
                CoursePreviewSheet(
                    course: ctx.course,
                    sourceWeek: ctx.sourceWeek,
                    isNotThisWeek: ctx.isNotThisWeek,
                    preset: activePreset,
                    onEdit: {
                        coursePreviewContext = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            courseToEdit = ctx.course
                        }
                    }
                )
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

    private func scheduleTable(week: Int, viewingWeek: Int) -> some View {
        let grid = WeekCourseGrid(week: week, schedule: activeSchedule, sortedSlots: sortedSlots, maxWeeks: maxWeeks)
        return VStack(spacing: 0) {
            // 固定表头：不随滚动
            HStack(alignment: .top, spacing: 0) {
                timeColumnHeader
                ForEach(displayDayIndices, id: \.self) { day in
                    dayHeader(day: day, week: week)
                }
            }
            .background(.ultraThinMaterial)

            if showHorizontalLines {
                Divider().opacity(0.6)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .top) {
                        LazyVStack(spacing: 0) {
                            Color.clear.frame(height: 0).id("top")
                            ForEach(Array(sortedSlots.enumerated()), id: \.element.periodIndex) { slotIndex, slot in
                                scheduleRow(periodSlot: slot, grid: grid, slotIndex: slotIndex)
                            }
                        }
                        .overlay(alignment: .top) {
                            courseBlocksOverlay(grid: grid, week: week)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .frame(maxHeight: .infinity)
                .onAppear {
                    if viewingWeek == week {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 与表格行同结构的 overlay，只画课程块；每行固定 52pt，课程块用 overlay 向下溢出（使用预计算 grid 减轻翻页卡顿）
    private func courseBlocksOverlay(grid: WeekCourseGrid?, week: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(sortedSlots.enumerated()), id: \.element.periodIndex) { slotIndex, _ in
                HStack(alignment: .top, spacing: 0) {
                    Color.clear.frame(width: timeColumnWidth).frame(height: rowHeight)
                    ForEach(displayDayIndices, id: \.self) { day in
                        courseBlockCell(grid: grid, tableWeek: week, slotIndex: slotIndex, dayIndex: day - 1)
                            .overlay(alignment: .leading) {
                                if showVerticalLines { verticalDivider }
                            }
                    }
                }
                .frame(height: rowHeight)
            }
        }
        .drawingGroup(opaque: false, colorMode: .nonLinear)
    }

    private func courseBlockCell(grid: WeekCourseGrid?, tableWeek: Int, slotIndex: Int, dayIndex: Int) -> some View {
        let c = grid?.starting[dayIndex][slotIndex]
        let cNotThisWeek = grid?.notThisWeek[dayIndex][slotIndex]
        let spanOverrideRaw = grid?.startingPeriodSpanOverride[dayIndex][slotIndex] ?? 0
        let spanOverride = spanOverrideRaw > 0 ? spanOverrideRaw : nil
        let reschedule = grid?.startingReschedule[dayIndex][slotIndex]
        /// 若该格是「调课目标」显示，用调课记录的来源周；否则用表格所在周
        let sourceWeek = reschedule?.week ?? tableWeek
        return cellContent(c: c, cNotThisWeek: cNotThisWeek, spanOverride: spanOverride, sourceWeek: sourceWeek)
    }

    @ViewBuilder
    private func cellContent(c: Course?, cNotThisWeek: Course?, spanOverride: Int?, sourceWeek: Int) -> some View {
        if let c = c {
            let span = spanOverride ?? c.periodSpan
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: rowHeight)
                .overlay(alignment: .top) {
                    CourseCellView(course: c, rowHeight: rowHeight, periodSpanOverride: spanOverride) {
                        coursePreviewContext = CoursePreviewContext(course: c, sourceWeek: sourceWeek, isNotThisWeek: false)
                    }
                    .frame(height: rowHeight * CGFloat(span) - 2)
                    .padding(1)
                }
        } else if let c = cNotThisWeek {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: rowHeight)
                .overlay(alignment: .top) {
                    CourseCellView(course: c, rowHeight: rowHeight, isNotThisWeek: true) {
                        coursePreviewContext = CoursePreviewContext(course: c, sourceWeek: sourceWeek, isNotThisWeek: true)
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

    /// 竖线（用于网格竖线开关，仅画在星期列左侧，避免与节次列重叠；60% 透明度）
    private var verticalDivider: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.6))
            .frame(width: 1)
    }

    private var timeColumnHeader: some View {
        VStack(spacing: 2) {
            Text("节次")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(width: timeColumnWidth, height: 56)
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
        .overlay(alignment: .leading) {
            if showVerticalLines { verticalDivider }
        }
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
            .frame(width: timeColumnWidth, alignment: .center)
            .frame(height: rowHeight)
            .padding(.vertical, 6)

            ForEach(displayDayIndices, id: \.self) { day in
                let hasCourse = grid?.hasCourse[day - 1][slotIndex] ?? false
                Group {
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
                .overlay(alignment: .leading) {
                    if showVerticalLines { verticalDivider }
                }
            }
        }
        .frame(height: rowHeight)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            if showHorizontalLines {
                Divider().opacity(0.6)
            }
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

// MARK: - 课程预览卡片（点击课程后先展示；本周课程可编辑/调课，半透明「非本周」仅展示卡片）
private struct CoursePreviewSheet: View {
    let course: Course
    let sourceWeek: Int
    /// 半透明课程（非本周）：仅展示卡片，不显示调课与编辑
    let isNotThisWeek: Bool
    let preset: TimeSlotPreset?
    var onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showRescheduleSheet = false

    private var cardAccent: Color { MacaronPalette.color(forCourseName: course.name) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 0) {
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
                    }
                    .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                }
                if !isNotThisWeek {
                    Section {
                        Button {
                            showRescheduleSheet = true
                        } label: {
                            Label("调课", systemImage: "calendar.badge.clock")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if !isNotThisWeek {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            onEdit()
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                    }
                }
            }
            .sheet(isPresented: $showRescheduleSheet) {
                RescheduleSheet(course: course, week: sourceWeek, preset: preset)
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

// MARK: - 课程格子（支持跨多节高度；可选「非本周」半透明样式；调课时用 periodSpanOverride 显示跨节）
private struct CourseCellView: View {
    let course: Course
    var rowHeight: CGFloat = 52
    /// 为 true 时：半透明显示并标注 [非本周]（该时间段在其他周有课、本周无课）
    var isNotThisWeek: Bool = false
    /// 调课后的显示跨节数，nil 表示使用 course.periodSpan
    var periodSpanOverride: Int? = nil
    let onTap: () -> Void

    private var effectiveSpan: Int { periodSpanOverride ?? course.periodSpan }
    private var cellHeight: CGFloat { rowHeight * CGFloat(effectiveSpan) }

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
        .modelContainer(for: [Schedule.self, Course.self, CourseReschedule.self, TimeSlotPreset.self, TimeSlotItem.self], inMemory: true)
}
