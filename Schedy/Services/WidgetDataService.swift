//
//  WidgetDataService.swift
//  schedy
//
//  将「当前课程表 + 今日接下来两节课」写入 App Group，供小组件读取。
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

/// 刷新小组件所需数据并写入 App Group UserDefaults
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

    var scheduleName = activeScheduleName
    var status = "noClass"
    var course1Name = ""
    var course1Time = ""
    var course1Location = ""
    var course2Name = ""
    var course2Time = ""
    var course2Location = ""

    do {
        var descriptor = FetchDescriptor<Schedule>()
        descriptor.fetchLimit = 1
        descriptor.predicate = #Predicate<Schedule> { $0.name == activeScheduleName }
        descriptor.relationshipKeyPathsForPrefetching = [\Schedule.courses, \Schedule.timeSlotPreset]
        let schedules = try modelContext.fetch(descriptor)
        guard let schedule = schedules.first else {
            writeWidgetSuite(suite: suite, scheduleName: scheduleName, dateString: dateString, weekdayString: weekdayString, status: status, c1Name: course1Name, c1Time: course1Time, c1Location: course1Location, c2Name: course2Name, c2Time: course2Time, c2Location: course2Location)
            return
        }

        // 小组件显示名称用调用方传入的「当前选中的名称」，保证改名后立即同步，不依赖 fetch 结果
        scheduleName = activeScheduleName
        let week = currentWeek(semesterStart: schedule.semesterStartDate, calendar: cal)
        let scheduleID = schedule.persistentModelID

        // 显式 fetch Course，避免 SwiftData 懒加载在非 @Query 上下文中返回空数组
        let allCourses = try modelContext.fetch(FetchDescriptor<Course>())
        let todayCourses = allCourses
            .filter {
                $0.schedule?.persistentModelID == scheduleID
                    && $0.appliesToWeek(week)
                    && $0.dayOfWeek == dayOfWeek
            }
            .sorted { $0.periodIndex < $1.periodIndex }

        // 显式 fetch TimeSlotItem，避免同样的懒加载问题
        let presetID = schedule.timeSlotPreset?.persistentModelID
        let allSlots = try modelContext.fetch(FetchDescriptor<TimeSlotItem>())
        let slots = allSlots
            .filter { presetID != nil && $0.preset?.persistentModelID == presetID }
            .sorted { $0.periodIndex < $1.periodIndex }

        func startTime(for course: Course) -> (hour: Int, minute: Int)? {
            slots.first(where: { $0.periodIndex == course.periodIndex }).map { ($0.startHour, $0.startMinute) }
        }
        func endTime(for course: Course) -> (hour: Int, minute: Int)? {
            slots.first(where: { $0.periodIndex == course.effectivePeriodEnd }).map { ($0.endHour, $0.endMinute) }
        }

        let now = today
        let nowComponents = cal.dateComponents([.hour, .minute], from: now)

        // 尚未结束的课：结束时间 > 当前时间（含正在上、未开始的）
        let notEnded = todayCourses.filter { course in
            guard let end = endTime(for: course) else { return true }
            let endMinutes = end.hour * 60 + end.minute
            let nowMinutes = (nowComponents.hour ?? 0) * 60 + (nowComponents.minute ?? 0)
            return endMinutes > nowMinutes
        }

        if !notEnded.isEmpty {
            status = "next"
            let display = Array(notEnded.prefix(2))
            if let c = display.first {
                course1Name = c.name
                course1Time = startTime(for: c).map { String(format: "%02d:%02d", $0.hour, $0.minute) } ?? ""
                course1Location = c.location
            }
            if display.count > 1 {
                let c = display[1]
                course2Name = c.name
                course2Time = startTime(for: c).map { String(format: "%02d:%02d", $0.hour, $0.minute) } ?? ""
                course2Location = c.location
            }
        } else {
            status = todayCourses.isEmpty ? "noClass" : "allDone"
            // 已上完时也写入最后两节课，小组件可显示「今日已上完：xxx、xxx」
            if !todayCourses.isEmpty {
                let lastTwo = Array(todayCourses.suffix(2))
                if let c = lastTwo.first {
                    course1Name = c.name
                    course1Time = startTime(for: c).map { String(format: "%02d:%02d", $0.hour, $0.minute) } ?? ""
                    course1Location = c.location
                }
                if lastTwo.count > 1 {
                    let c = lastTwo[1]
                    course2Name = c.name
                    course2Time = startTime(for: c).map { String(format: "%02d:%02d", $0.hour, $0.minute) } ?? ""
                    course2Location = c.location
                }
            }
        }

        writeWidgetSuite(suite: suite, scheduleName: scheduleName, dateString: dateString, weekdayString: weekdayString, status: status, c1Name: course1Name, c1Time: course1Time, c1Location: course1Location, c2Name: course2Name, c2Time: course2Time, c2Location: course2Location)
    } catch {
        writeWidgetSuite(suite: suite, scheduleName: scheduleName, dateString: dateString, weekdayString: weekdayString, status: status, c1Name: course1Name, c1Time: course1Time, c1Location: course1Location, c2Name: course2Name, c2Time: course2Time, c2Location: course2Location)
    }
}

private func writeWidgetSuite(suite: UserDefaults, scheduleName: String, dateString: String, weekdayString: String, status: String, c1Name: String, c1Time: String, c1Location: String, c2Name: String, c2Time: String, c2Location: String) {
    suite.set(scheduleName, forKey: WidgetDataKeys.scheduleName)
    suite.set(dateString, forKey: WidgetDataKeys.date)
    suite.set(weekdayString, forKey: WidgetDataKeys.weekday)
    suite.set(status, forKey: WidgetDataKeys.status)
    suite.set(c1Name, forKey: WidgetDataKeys.course1Name)
    suite.set(c1Time, forKey: WidgetDataKeys.course1Time)
    suite.set(c1Location, forKey: WidgetDataKeys.course1Location)
    suite.set(c2Name, forKey: WidgetDataKeys.course2Name)
    suite.set(c2Time, forKey: WidgetDataKeys.course2Time)
    suite.set(c2Location, forKey: WidgetDataKeys.course2Location)
    suite.synchronize()
    // 通知小组件立即重载时间线，使主屏小组件显示最新数据
    WidgetCenter.shared.reloadTimelines(ofKind: "SchedyWidget")
}
