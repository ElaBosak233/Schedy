//
//  WidgetDataService.swift
//  schedy
//
//  将「每张课程表的今日数据」写入 App Group，供小组件读取；支持小组件选择显示哪张课表。
//

import Foundation
import SwiftData
import WidgetKit

/// App Group 标识，需与主 App 和 Widget 的 entitlements 一致
let kWidgetAppGroupSuiteName = "group.dev.e23.schedy"

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
    /// 单张课表数据存在 suite 里的 key 前缀，完整 key 为 "\(entryPrefix)_\(scheduleName)"
    static let entryPrefix = "widgetEntry"
}

/// 根据学期第一天和当前日期计算当前周（1-based）
private func currentWeek(semesterStart: Date, calendar: Calendar) -> Int {
    let today = calendar.startOfDay(for: Date())
    let start = calendar.startOfDay(for: semesterStart)
    guard today >= start else { return 1 }
    let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
    return min(max(1, days / 7 + 1), 25)
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
    let weekdayNames = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    let today = Date()
    let dateString = dateFormatter.string(from: today)
    let calendarWeekday = cal.component(.weekday, from: today)
    let dayOfWeek = toDayOfWeek(calendarWeekday)
    let weekdayString = dayOfWeek >= 1 && dayOfWeek <= 7 ? weekdayNames[dayOfWeek] : ""

    var scheduleDescriptor = FetchDescriptor<Schedule>()
    scheduleDescriptor.relationshipKeyPathsForPrefetching = [\Schedule.courses, \Schedule.timeSlotPreset]
    let allSchedules = (try? modelContext.fetch(scheduleDescriptor)) ?? []
    let scheduleNames = allSchedules.map(\.name)

    suite.set(scheduleNames, forKey: WidgetDataKeys.scheduleNamesList)
    suite.set(activeScheduleName, forKey: WidgetDataKeys.defaultScheduleName)

    var courseDescriptor = FetchDescriptor<Course>()
    courseDescriptor.relationshipKeyPathsForPrefetching = [\Course.reschedules]
    let allCourses = (try? modelContext.fetch(courseDescriptor)) ?? []
    let allSlots = (try? modelContext.fetch(FetchDescriptor<TimeSlotItem>())) ?? []

    for schedule in allSchedules {
        let scheduleName = schedule.name
        let scheduleID = schedule.persistentModelID
        let week = currentWeek(semesterStart: schedule.semesterStartDate, calendar: cal)
        let presetID = schedule.timeSlotPreset?.persistentModelID
        let slots = allSlots
            .filter { $0.preset?.persistentModelID == presetID }
            .sorted { $0.periodIndex < $1.periodIndex }

        func startTime(period: Int) -> (hour: Int, minute: Int)? {
            slots.first(where: { $0.periodIndex == period }).map { ($0.startHour, $0.startMinute) }
        }
        func endTime(period: Int) -> (hour: Int, minute: Int)? {
            slots.first(where: { $0.periodIndex == period }).map { ($0.endHour, $0.endMinute) }
        }

        let scheduleCourses = allCourses.filter { $0.schedule?.persistentModelID == scheduleID }
        let occurrences = EffectiveCourseService.effectiveCourseOccurrences(
            courses: scheduleCourses,
            week: week,
            dayOfWeek: dayOfWeek
        )
        let courseItems: [(name: String, location: String, periodStart: Int, periodEnd: Int)] = occurrences.map { (name: $0.course.name, location: $0.course.location ?? "", periodStart: $0.periodStart, periodEnd: $0.periodEnd) }

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

        let entryKey = "\(WidgetDataKeys.entryPrefix)_\(scheduleName)"
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
    }

    // 删除已不存在的课表在 suite 里的旧 key（避免删除课表后残留）
    let existingKeys = suite.dictionaryRepresentation().keys
    for key in existingKeys where key.hasPrefix(WidgetDataKeys.entryPrefix + "_") {
        let name = String(key.dropFirst(WidgetDataKeys.entryPrefix.count + 1))
        if !scheduleNames.contains(name) {
            suite.removeObject(forKey: key)
        }
    }

    suite.synchronize()
    WidgetCenter.shared.reloadTimelines(ofKind: "SchedyWidget")
}
