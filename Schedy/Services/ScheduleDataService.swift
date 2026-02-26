//
//  ScheduleDataService.swift
//  schedy
//
//  初始化默认时间段预设、默认课程表及迁移
//

import Foundation
import SwiftData

@MainActor
func seedDefaultPresetsIfNeeded(modelContext: ModelContext) {
    let descriptor = FetchDescriptor<TimeSlotPreset>()
    let existing = (try? modelContext.fetch(descriptor)) ?? []
    guard existing.isEmpty else { return }

    func makeSlots(
        _ data: [(period: Int, start: (h: Int, m: Int), end: (h: Int, m: Int))]
    ) -> [TimeSlotItem] {
        data.map { item in
            TimeSlotItem(
                periodIndex: item.period,
                startHour: item.start.h,
                startMinute: item.start.m,
                endHour: item.end.h,
                endMinute: item.end.m
            )
        }
    }

    let winter = TimeSlotPreset(name: "冬令时", slots: [])
    for slot in makeSlots(DefaultTimeSlots.winter()) {
        slot.preset = winter
        winter.slots.append(slot)
        modelContext.insert(slot)
    }
    modelContext.insert(winter)

    let summer = TimeSlotPreset(name: "夏令时", slots: [])
    for slot in makeSlots(DefaultTimeSlots.summer()) {
        slot.preset = summer
        summer.slots.append(slot)
        modelContext.insert(slot)
    }
    modelContext.insert(summer)

    try? modelContext.save()
}

/// 本学期第一天：取下一个周一，若今天已是周一则取今天
private func defaultSemesterStartDate() -> Date {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let weekday = cal.component(.weekday, from: today) // 1 = Sun, 2 = Mon, ...
    let daysUntilMonday = weekday == 1 ? 1 : (weekday == 2 ? 0 : (9 - weekday))
    return cal.date(byAdding: .day, value: daysUntilMonday, to: today) ?? today
}

@MainActor
func seedDefaultScheduleIfNeeded(modelContext: ModelContext) {
    let scheduleDescriptor = FetchDescriptor<Schedule>()
    let schedules = (try? modelContext.fetch(scheduleDescriptor)) ?? []
    if schedules.isEmpty {
        seedDefaultPresetsIfNeeded(modelContext: modelContext)
        let presets = (try? modelContext.fetch(FetchDescriptor<TimeSlotPreset>())) ?? []
        let firstPreset = presets.first
        let start = defaultSemesterStartDate()
        let defaultName = "我的课程表"
        let schedule = Schedule(name: defaultName, semesterStartDate: start, timeSlotPreset: firstPreset)
        modelContext.insert(schedule)
        try? modelContext.save()
        // 确保默认课程表被选中，否则小组件用 activeScheduleName 查不到课表
        UserDefaults.standard.set(defaultName, forKey: "activeScheduleName")
    }

    // 迁移：把没有归属的课程挂到第一张课程表
    let courseDescriptor = FetchDescriptor<Course>()
    let allCourses = (try? modelContext.fetch(courseDescriptor)) ?? []
    let firstSchedule = (try? modelContext.fetch(FetchDescriptor<Schedule>()))?.first
    if let s = firstSchedule {
        for c in allCourses where c.schedule == nil {
            c.schedule = s
        }
        try? modelContext.save()
    }
}
