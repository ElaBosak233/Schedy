//
//  CourseNotificationService.swift
//  schedy
//
//  在课程开始前 15 分钟发送本地通知。支持多张课表同时提醒（按「是否通知」），且考虑调课后的有效课次。
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

/// 为所有「允许通知」的课程表安排「开课前 15 分钟」的本地通知（考虑调课后的有效课次）；会先清除已有 schedy 提醒再重新排期。
@MainActor
func scheduleCourseReminders(modelContext: ModelContext) {
    requestCourseNotificationPermission()
    clearScheduledCourseReminders {
        Task { @MainActor in
            scheduleCourseRemindersAfterClear(modelContext: modelContext)
        }
    }
}

@MainActor
private func scheduleCourseRemindersAfterClear(modelContext: ModelContext) {
    let cal = Calendar.current
    let now = Date()

    do {
        let activePresetName = UserDefaults.standard.string(forKey: ScheduleDisplayKeys.activeTimeSlotPresetName) ?? ""
        var scheduleDescriptor = FetchDescriptor<Schedule>()
        scheduleDescriptor.predicate = #Predicate<Schedule> { $0.notificationsEnabled == true }
        scheduleDescriptor.relationshipKeyPathsForPrefetching = [\Schedule.courses, \Schedule.timeSlotPreset]
        let enabledSchedules = try modelContext.fetch(scheduleDescriptor)
        guard !enabledSchedules.isEmpty else { return }

        var courseDescriptor = FetchDescriptor<Course>()
        courseDescriptor.relationshipKeyPathsForPrefetching = [\Course.reschedules]
        let allCourses = try modelContext.fetch(courseDescriptor)
        let allPresets = try modelContext.fetch(FetchDescriptor<TimeSlotPreset>())
        let defaultPreset = allPresets.first { $0.name == activePresetName } ?? allPresets.first
        let allSlots = try modelContext.fetch(FetchDescriptor<TimeSlotItem>())

        func slots(for preset: TimeSlotPreset?) -> [TimeSlotItem] {
            guard let preset = preset else { return [] }
            let pid = preset.persistentModelID
            return allSlots
                .filter { $0.preset?.persistentModelID == pid }
                .sorted { $0.periodIndex < $1.periodIndex }
        }
        func startTime(slots: [TimeSlotItem], forPeriod period: Int) -> (hour: Int, minute: Int)? {
            slots.first(where: { $0.periodIndex == period }).map { ($0.startHour, $0.startMinute) }
        }

        let maxTotal = 64
        var scheduledCount = 0

        for schedule in enabledSchedules {
            guard scheduledCount < maxTotal else { break }
            let scheduleID = schedule.persistentModelID
            let scheduleName = schedule.name.isEmpty ? "课程表" : schedule.name
            let courses = allCourses.filter { $0.schedule?.persistentModelID == scheduleID }
            guard !courses.isEmpty else { continue }

            let preset = schedule.timeSlotPreset ?? defaultPreset
            let scheduleSlots = slots(for: preset)

            let semesterStart = cal.startOfDay(for: schedule.semesterStartDate)
            let currentW = currentWeek(semesterStart: schedule.semesterStartDate, calendar: cal)

            for week in currentW ..< (currentW + kMaxWeeksAhead) {
                guard scheduledCount < maxTotal else { break }
                for dayOfWeek in 1 ... 7 {
                    guard scheduledCount < maxTotal else { break }
                    let occurrences = EffectiveCourseService.effectiveCourseOccurrences(
                        courses: courses,
                        week: week,
                        dayOfWeek: dayOfWeek
                    )
                    guard let dayDate = cal.date(byAdding: .day, value: (week - 1) * 7 + (dayOfWeek - 1), to: semesterStart) else { continue }
                    for occ in occurrences {
                        guard let start = startTime(slots: scheduleSlots, forPeriod: occ.periodStart) else { continue }
                        let comps = DateComponents(
                            calendar: cal,
                            year: cal.component(.year, from: dayDate),
                            month: cal.component(.month, from: dayDate),
                            day: cal.component(.day, from: dayDate),
                            hour: start.hour,
                            minute: start.minute
                        )
                        guard let courseStart = cal.date(from: comps) else { continue }
                        let reminderDate = cal.date(byAdding: .minute, value: -kReminderMinutes, to: courseStart)!
                        if reminderDate <= now { continue }
                        let id = "\(kNotificationPrefix)\(occ.course.persistentModelID.hashValue)-\(scheduleID.hashValue)-\(week)-\(dayOfWeek)-\(occ.periodStart)"
                        let content = UNMutableNotificationContent()
                        content.title = "课程提醒"
                        content.body = "「\(scheduleName)」\(occ.course.name) 快要开始啦"
                        content.sound = .default
                        let triggerComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
                        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
                        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                        UNUserNotificationCenter.current().add(request)
                        scheduledCount += 1
                        if scheduledCount >= maxTotal { break }
                    }
                }
            }
        }
    } catch {
        // 忽略排期失败，不影响主流程
    }
}
