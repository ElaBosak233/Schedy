//
//  CourseNotificationService.swift
//  schedy
//
//  在课程开始前 15 分钟发送本地通知提醒用户。
//

import Foundation
import SwiftData
import UserNotifications

private let kNotificationPrefix = "schedy-"
private let kReminderMinutes: Int = 15
/// 最多预排的周数（iOS 本地通知总数上限 64）
private let kMaxWeeksAhead = 6

/// 根据学期第一天和当前日期计算当前周（1-based）
private func currentWeek(semesterStart: Date, calendar: Calendar) -> Int {
    let today = calendar.startOfDay(for: Date())
    let start = calendar.startOfDay(for: semesterStart)
    guard today >= start else { return 1 }
    let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
    return min(max(1, days / 7 + 1), 25)
}

/// 请求通知权限（可在任意处调用）
func requestCourseNotificationPermission() {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
}

/// 清除所有由本应用创建的课程提醒（前缀 schedy-），完成后调用 completion（可能在任何队列）
func clearScheduledCourseReminders(completion: @escaping () -> Void) {
    let center = UNUserNotificationCenter.current()
    center.getPendingNotificationRequests { requests in
        let ids = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(kNotificationPrefix) }
        if ids.isEmpty {
            completion()
            return
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        completion()
    }
}

/// 为当前选中的课程表安排「开课前 15 分钟」的本地通知；会先清除已有 schedy 提醒再重新排期。
@MainActor
func scheduleCourseReminders(modelContext: ModelContext, activeScheduleName: String) {
    requestCourseNotificationPermission()
    clearScheduledCourseReminders {
        Task { @MainActor in
            scheduleCourseRemindersAfterClear(modelContext: modelContext, activeScheduleName: activeScheduleName)
        }
    }
}

@MainActor
private func scheduleCourseRemindersAfterClear(modelContext: ModelContext, activeScheduleName: String) {
    let cal = Calendar.current
    let now = Date()

    do {
        var scheduleDescriptor = FetchDescriptor<Schedule>()
        scheduleDescriptor.predicate = #Predicate<Schedule> { $0.name == activeScheduleName }
        scheduleDescriptor.fetchLimit = 1
        scheduleDescriptor.relationshipKeyPathsForPrefetching = [\Schedule.courses, \Schedule.timeSlotPreset]
        let schedules = try modelContext.fetch(scheduleDescriptor)
        guard let schedule = schedules.first else { return }

        let scheduleID = schedule.persistentModelID
        let allCourses = try modelContext.fetch(FetchDescriptor<Course>())
        let courses = allCourses.filter { $0.schedule?.persistentModelID == scheduleID }
        guard !courses.isEmpty else { return }

        let presetID = schedule.timeSlotPreset?.persistentModelID
        let allSlots = try modelContext.fetch(FetchDescriptor<TimeSlotItem>())
        let slots = allSlots
            .filter { presetID != nil && $0.preset?.persistentModelID == presetID }
            .sorted { $0.periodIndex < $1.periodIndex }

        func startTime(for course: Course) -> (hour: Int, minute: Int)? {
            slots.first(where: { $0.periodIndex == course.periodIndex }).map { ($0.startHour, $0.startMinute) }
        }

        let semesterStart = cal.startOfDay(for: schedule.semesterStartDate)
        let currentW = currentWeek(semesterStart: schedule.semesterStartDate, calendar: cal)
        var scheduledCount = 0
        let maxTotal = 64

        for week in currentW ..< (currentW + kMaxWeeksAhead) {
            guard scheduledCount < maxTotal else { break }
            for dayOfWeek in 1 ... 7 {
                guard scheduledCount < maxTotal else { break }
                guard let dayDate = cal.date(byAdding: .day, value: (week - 1) * 7 + (dayOfWeek - 1), to: semesterStart) else { continue }
                for course in courses where course.appliesToWeek(week) && course.dayOfWeek == dayOfWeek {
                    guard let start = startTime(for: course) else { continue }
                    var comps = DateComponents(calendar: cal, year: cal.component(.year, from: dayDate), month: cal.component(.month, from: dayDate), day: cal.component(.day, from: dayDate), hour: start.hour, minute: start.minute)
                    guard let courseStart = cal.date(from: comps) else { continue }
                    let reminderDate = cal.date(byAdding: .minute, value: -kReminderMinutes, to: courseStart)!
                    if reminderDate <= now { continue }
                    let id = "\(kNotificationPrefix)\(course.persistentModelID.hashValue)-\(week)-\(dayOfWeek)"
                    let content = UNMutableNotificationContent()
                    content.title = "课程提醒"
                    content.body = "「\(course.name)」将在 \(kReminderMinutes) 分钟后开始"
                    content.sound = .default
                    let triggerComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
                    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                    UNUserNotificationCenter.current().add(request)
                    scheduledCount += 1
                }
            }
        }
    } catch {
        // 忽略排期失败，不影响主流程
    }
}
