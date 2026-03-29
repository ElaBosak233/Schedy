//
//  WidgetDataService.swift
//  Schedy
//
//  将「每张课程表的今日数据」写入 App Group，供小组件读取；支持小组件选择显示哪张课表。
//
//  注意：App Group 标识（kWidgetAppGroupSuiteName）与 WidgetDataKeys 的键名必须与
//  SchedyWidget 扩展中的 WidgetDataKeys.swift 完全一致，否则小组件无法正确读取数据。
//  修改任一 key 或 suite 时需同时更新主 App 与 Widget 两处。
//

import Foundation
import SwiftData
import WidgetKit

/// 预计算未来 N 天的小组件时间线，减少必须打开 App 才能跨天更新的问题
private let kWidgetTimelineDaysAhead = 7

/// App Group 标识，需与主 App 和 Widget 的 entitlements 一致
let kWidgetAppGroupSuiteName = "group.dev.e23.schedy"

/// 写入 App Group 时使用的键名，须与 SchedyWidget/WidgetDataKeys.swift 中定义保持一致
enum WidgetDataKeys {
    static let scheduleName = "widgetScheduleName"
    static let date = "widgetDate"
    static let weekday = "widgetWeekday"
    static let status = "widgetStatus"  // "noClass" | "allDone" | "next"
    static let course1Name = "widgetCourse1Name"
    static let course1Time = "widgetCourse1Time"
    static let course1Location = "widgetCourse1Location"
    static let course2Name = "widgetCourse2Name"
    static let course2Time = "widgetCourse2Time"
    static let course2Location = "widgetCourse2Location"

    /// 小组件可选课表名称列表（供设置卡片使用）
    static let scheduleNamesList = "widgetScheduleNamesList"
    /// App 当前选中的课表名称（小组件默认显示此项；课表被删除时回退用）
    static let defaultScheduleName = "widgetDefaultScheduleName"
    /// 小组件可选时间段名称列表
    static let presetNamesList = "widgetPresetNamesList"
    /// App 当前选中的时间段名称（小组件默认使用此项）
    static let defaultPresetName = "widgetDefaultPresetName"
    /// 单张课表+时间段数据在 suite 里的 key：entryPrefix + "_" + scheduleName + "__SEP__" + presetName（每张课表仅写其绑定预设的一条）
    static let entryPrefix = "widgetEntry"
    static let entrySeparator = "__SEP__"
    /// 课表名 → 绑定预设名，供小组件根据选中的课表解析预设：schedulePreset_ + 课表名
    static let schedulePresetPrefix = "schedulePreset_"
    /// 今日时间线（JSON 数组），key：timelinePrefix + "_" + scheduleName + "__SEP__" + presetName
    static let timelinePrefix = "widgetTimeline"
    /// 时间线中每个 entry 的触发时间戳 key
    static let timelineTrigger = "trigger"
}

/// 系统 Calendar 的 weekday：1=周日, 2=周一, … 7=周六 → 模型 dayOfWeek：1=周一, …, 7=周日
private func toDayOfWeek(_ calendarWeekday: Int) -> Int {
    return calendarWeekday == 1 ? 7 : (calendarWeekday - 1)
}

/// 刷新小组件所需数据：为每张课表写入今日数据到 App Group，并写入课表列表与默认选中项
@MainActor
func refreshWidgetData(modelContext: ModelContext, activeScheduleName: String) {
    guard let suite = UserDefaults(suiteName: kWidgetAppGroupSuiteName) else { return }

    let cal = Calendar.current
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "M月d日"
    dateFormatter.locale = Locale(identifier: "zh_CN")

    func dateText(for date: Date) -> String {
        dateFormatter.string(from: date)
    }

    func weekdayText(for date: Date) -> String {
        let calendarWeekday = cal.component(.weekday, from: date)
        let dayOfWeek = toDayOfWeek(calendarWeekday)
        return WeekdayLabels.name(forDayOfWeek: dayOfWeek)
    }

    // 按指定日期计算学期周次（1-based），与 Calendar.currentWeek 的规则保持一致
    func weekIndex(for semesterStart: Date, on date: Date) -> Int {
        let targetDay = cal.startOfDay(for: date)
        let start = cal.startOfDay(for: semesterStart)
        let weekday = cal.component(.weekday, from: start)
        let daysToMonday = weekday == 1 ? -6 : -(weekday - 2)
        let weekOneMonday = cal.date(byAdding: .day, value: daysToMonday, to: start) ?? start
        guard targetDay >= weekOneMonday else { return 1 }
        let days = cal.dateComponents([.day], from: weekOneMonday, to: targetDay).day ?? 0
        return min(max(1, days / 7 + 1), 25)
    }

    let today = Date()
    let dateString = dateText(for: today)
    let dayOfWeek = toDayOfWeek(cal.component(.weekday, from: today))
    let weekdayString = weekdayText(for: today)

    var scheduleDescriptor = FetchDescriptor<Schedule>()
    scheduleDescriptor.relationshipKeyPathsForPrefetching = [\Schedule.courses, \Schedule.timeSlotPreset]
    let allSchedules = (try? modelContext.fetch(scheduleDescriptor)) ?? []
    let scheduleNames = allSchedules.map(\.name)

    suite.set(scheduleNames, forKey: WidgetDataKeys.scheduleNamesList)
    suite.set(activeScheduleName, forKey: WidgetDataKeys.defaultScheduleName)

    let activePresetName = UserDefaults.standard.string(forKey: ScheduleDisplayKeys.activeTimeSlotPresetName) ?? ""
    let allPresets = (try? modelContext.fetch(FetchDescriptor<TimeSlotPreset>())) ?? []
    let defaultPreset = allPresets.first { $0.name == activePresetName } ?? allPresets.first
    suite.set(defaultPreset?.name ?? "", forKey: WidgetDataKeys.defaultPresetName)

    var courseDescriptor = FetchDescriptor<Course>()
    courseDescriptor.relationshipKeyPathsForPrefetching = [\Course.reschedules]
    let allCourses = (try? modelContext.fetch(courseDescriptor)) ?? []
    let allSlots = (try? modelContext.fetch(FetchDescriptor<TimeSlotItem>())) ?? []

    for schedule in allSchedules {
        let scheduleName = schedule.name
        let scheduleID = schedule.persistentModelID
        let week = weekIndex(for: schedule.semesterStartDate, on: today)
        let preset = schedule.timeSlotPreset ?? defaultPreset
        let presetName = preset?.name ?? ""
        suite.set(presetName, forKey: WidgetDataKeys.schedulePresetPrefix + scheduleName)

        let scheduleCourses = allCourses.filter { $0.schedule?.persistentModelID == scheduleID }
        let occurrences = EffectiveCourseService.effectiveCourseOccurrences(
            courses: scheduleCourses,
            week: week,
            dayOfWeek: dayOfWeek
        )
        let courseItems: [(name: String, location: String, periodStart: Int, periodEnd: Int)] = occurrences.map { (name: $0.course.name, location: $0.course.location ?? "", periodStart: $0.periodStart, periodEnd: $0.periodEnd) }

        guard let preset = preset else { continue }
        let presetID = preset.persistentModelID
        let slots = allSlots
            .filter { $0.preset?.persistentModelID == presetID }
            .sorted { $0.periodIndex < $1.periodIndex }

        func startTime(period: Int) -> (hour: Int, minute: Int)? {
            slots.first(where: { $0.periodIndex == period }).map { ($0.startHour, $0.startMinute) }
        }
        func endTime(period: Int) -> (hour: Int, minute: Int)? {
            slots.first(where: { $0.periodIndex == period }).map { ($0.endHour, $0.endMinute) }
        }

        var status = "noClass"
        var c1Name = ""
        var c1Time = ""
        var c1Location = ""
        var c2Name = ""
        var c2Time = ""
        var c2Location = ""

        let nowComponents = cal.dateComponents([.hour, .minute], from: today)
        let nowMinutes = (nowComponents.hour ?? 0) * 60 + (nowComponents.minute ?? 0)

        let notEnded = courseItems.filter { item in
            guard let end = endTime(period: item.periodEnd) else { return true }
            let endMinutes = end.hour * 60 + end.minute
            return endMinutes > nowMinutes
        }

        if !notEnded.isEmpty {
            status = "next"
            let display = Array(notEnded.prefix(2))
            if let first = display.first {
                c1Name = first.name
                c1Time = startTime(period: first.periodStart).map { String(format: "%02d:%02d", $0.hour, $0.minute) } ?? ""
                c1Location = first.location
            }
            if display.count > 1 {
                let second = display[1]
                c2Name = second.name
                c2Time = startTime(period: second.periodStart).map { String(format: "%02d:%02d", $0.hour, $0.minute) } ?? ""
                c2Location = second.location
            }
        } else {
            status = courseItems.isEmpty ? "noClass" : "allDone"
            if !courseItems.isEmpty {
                let lastTwo = Array(courseItems.suffix(2))
                if let first = lastTwo.first {
                    c1Name = first.name
                    c1Time = startTime(period: first.periodStart).map { String(format: "%02d:%02d", $0.hour, $0.minute) } ?? ""
                    c1Location = first.location
                }
                if lastTwo.count > 1 {
                    let second = lastTwo[1]
                    c2Name = second.name
                    c2Time = startTime(period: second.periodStart).map { String(format: "%02d:%02d", $0.hour, $0.minute) } ?? ""
                    c2Location = second.location
                }
            }
        }

        let entryKey = "\(WidgetDataKeys.entryPrefix)_\(scheduleName)\(WidgetDataKeys.entrySeparator)\(presetName)"
        let dict: [String: String] = [
            WidgetDataKeys.scheduleName: scheduleName,
            WidgetDataKeys.date: dateString,
            WidgetDataKeys.weekday: weekdayString,
            WidgetDataKeys.status: status,
            WidgetDataKeys.course1Name: c1Name,
            WidgetDataKeys.course1Time: c1Time,
            WidgetDataKeys.course1Location: c1Location,
            WidgetDataKeys.course2Name: c2Name,
            WidgetDataKeys.course2Time: c2Time,
            WidgetDataKeys.course2Location: c2Location,
        ]
        suite.set(dict, forKey: entryKey)

        // 写入多日时间线：今天用“当前状态”，未来天从 00:00 开始并在每节课结束后切换
        var timelineEntries: [[String: String]] = []

        func makeEntry(
            trigger: Date,
            dayDate: Date,
            dayItems: [(name: String, location: String, periodStart: Int, periodEnd: Int)],
            notEndedItems: [(name: String, location: String, periodStart: Int, periodEnd: Int)]
        ) -> [String: String] {
            var e: [String: String] = [
                WidgetDataKeys.scheduleName: scheduleName,
                WidgetDataKeys.date: dateText(for: dayDate),
                WidgetDataKeys.weekday: weekdayText(for: dayDate),
                WidgetDataKeys.timelineTrigger: String(trigger.timeIntervalSince1970),
            ]
            if notEndedItems.isEmpty {
                e[WidgetDataKeys.status] = dayItems.isEmpty ? "noClass" : "allDone"
                if !dayItems.isEmpty {
                    let lastTwo = Array(dayItems.suffix(2))
                    e[WidgetDataKeys.course1Name] = lastTwo.first?.name ?? ""
                    e[WidgetDataKeys.course1Time] = lastTwo.first.flatMap { startTime(period: $0.periodStart) }.map { String(format: "%02d:%02d", $0.hour, $0.minute) } ?? ""
                    e[WidgetDataKeys.course1Location] = lastTwo.first?.location ?? ""
                    if lastTwo.count > 1 {
                        e[WidgetDataKeys.course2Name] = lastTwo[1].name
                        e[WidgetDataKeys.course2Time] = startTime(period: lastTwo[1].periodStart).map { String(format: "%02d:%02d", $0.hour, $0.minute) } ?? ""
                        e[WidgetDataKeys.course2Location] = lastTwo[1].location
                    }
                }
            } else {
                e[WidgetDataKeys.status] = "next"
                let display = Array(notEndedItems.prefix(2))
                e[WidgetDataKeys.course1Name] = display.first?.name ?? ""
                e[WidgetDataKeys.course1Time] = display.first.flatMap { startTime(period: $0.periodStart) }.map { String(format: "%02d:%02d", $0.hour, $0.minute) } ?? ""
                e[WidgetDataKeys.course1Location] = display.first?.location ?? ""
                if display.count > 1 {
                    e[WidgetDataKeys.course2Name] = display[1].name
                    e[WidgetDataKeys.course2Time] = startTime(period: display[1].periodStart).map { String(format: "%02d:%02d", $0.hour, $0.minute) } ?? ""
                    e[WidgetDataKeys.course2Location] = display[1].location
                }
            }
            return e
        }

        let todayStart = cal.startOfDay(for: today)
        for dayOffset in 0 ..< kWidgetTimelineDaysAhead {
            guard let dayDate = cal.date(byAdding: .day, value: dayOffset, to: todayStart) else { continue }
            let dayWeek = weekIndex(for: schedule.semesterStartDate, on: dayDate)
            let dayOfWeek = toDayOfWeek(cal.component(.weekday, from: dayDate))
            let dayOccurrences = EffectiveCourseService.effectiveCourseOccurrences(
                courses: scheduleCourses,
                week: dayWeek,
                dayOfWeek: dayOfWeek
            )
            let dayItems: [(name: String, location: String, periodStart: Int, periodEnd: Int)] = dayOccurrences.map {
                (name: $0.course.name, location: $0.course.location ?? "", periodStart: $0.periodStart, periodEnd: $0.periodEnd)
            }

            if dayOffset == 0 {
                let currentNotEnded = dayItems.filter { item in
                    guard let end = endTime(period: item.periodEnd) else { return true }
                    let endMinutes = end.hour * 60 + end.minute
                    return endMinutes > nowMinutes
                }
                timelineEntries.append(makeEntry(trigger: today, dayDate: dayDate, dayItems: dayItems, notEndedItems: currentNotEnded))
            } else {
                let trigger = cal.startOfDay(for: dayDate)
                timelineEntries.append(makeEntry(trigger: trigger, dayDate: dayDate, dayItems: dayItems, notEndedItems: dayItems))
            }

            for item in dayItems {
                guard let end = endTime(period: item.periodEnd) else { continue }
                var comps = cal.dateComponents([.year, .month, .day], from: dayDate)
                comps.hour = end.hour
                comps.minute = end.minute
                comps.second = 0
                guard let triggerDate = cal.date(from: comps) else { continue }
                if dayOffset == 0 && triggerDate <= today { continue }
                let cutoff = end.hour * 60 + end.minute
                let remaining = dayItems.filter { i in
                    guard let e2 = endTime(period: i.periodEnd) else { return true }
                    return e2.hour * 60 + e2.minute > cutoff
                }
                timelineEntries.append(makeEntry(trigger: triggerDate, dayDate: dayDate, dayItems: dayItems, notEndedItems: remaining))
            }
        }

        timelineEntries.sort {
            (Double($0[WidgetDataKeys.timelineTrigger] ?? "0") ?? 0) < (Double($1[WidgetDataKeys.timelineTrigger] ?? "0") ?? 0)
        }

        if let data = try? JSONSerialization.data(withJSONObject: timelineEntries),
           let json = String(data: data, encoding: .utf8) {
            let timelineKey = "\(WidgetDataKeys.timelinePrefix)_\(scheduleName)\(WidgetDataKeys.entrySeparator)\(presetName)"
            suite.set(json, forKey: timelineKey)
        }
    }

    let presetNames = allPresets.map(\.name)
    let validEntryPrefix = WidgetDataKeys.entryPrefix + "_"
    let sep = WidgetDataKeys.entrySeparator
    var validSchedulePresets: [String: String] = [:]
    for s in allSchedules {
        let p = s.timeSlotPreset?.name ?? defaultPreset?.name ?? ""
        validSchedulePresets[s.name] = p
    }
    let existingKeys = suite.dictionaryRepresentation().keys
    for key in existingKeys where key.hasPrefix(validEntryPrefix) || key.hasPrefix(WidgetDataKeys.timelinePrefix + "_") {
        let isTimeline = key.hasPrefix(WidgetDataKeys.timelinePrefix + "_")
        let prefixLen = isTimeline ? (WidgetDataKeys.timelinePrefix + "_").count : validEntryPrefix.count
        let rest = String(key.dropFirst(prefixLen))
        guard let sepRange = rest.range(of: sep) else {
            suite.removeObject(forKey: key)
            continue
        }
        let namePart = String(rest[..<sepRange.lowerBound])
        let presetPart = String(rest[sepRange.upperBound...])
        if !scheduleNames.contains(namePart) || validSchedulePresets[namePart] != presetPart {
            suite.removeObject(forKey: key)
        }
    }
    for key in existingKeys where key.hasPrefix(WidgetDataKeys.schedulePresetPrefix) {
        let namePart = String(key.dropFirst(WidgetDataKeys.schedulePresetPrefix.count))
        if !scheduleNames.contains(namePart) {
            suite.removeObject(forKey: key)
        }
    }

    suite.synchronize()
    WidgetCenter.shared.reloadTimelines(ofKind: "SchedyWidget")
}
