//
//  ScheduleDataService.swift
//  Schedy
//
//  数据初始化与迁移：首次启动时写入冬令时/夏令时预设、创建默认课程表；迁移无归属课程到第一张课表。
//

import Foundation
import SwiftData

/// 若尚无任何时间段预设，则创建「冬令时」「夏令时」并保存
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
    for slot in makeSlots(TimeSlotPreset.Default.winter()) {
        slot.preset = winter
        winter.slots = (winter.slots ?? []) + [slot]
        modelContext.insert(slot)
    }
    modelContext.insert(winter)

    let summer = TimeSlotPreset(name: "夏令时", slots: [])
    for slot in makeSlots(TimeSlotPreset.Default.summer()) {
        slot.preset = summer
        summer.slots = (summer.slots ?? []) + [slot]
        modelContext.insert(slot)
    }
    modelContext.insert(summer)

    try? modelContext.save()
}

/// 若时间段的节次不足，则按「上一节结束 + 10 分钟」为下一节开始、每节 40 分钟，补齐到 requiredPeriodCount 节
@MainActor
func extendPresetToCoverPeriodIfNeeded(preset: TimeSlotPreset?, requiredPeriodCount: Int, modelContext: ModelContext) {
    guard let preset = preset, requiredPeriodCount > 0 else { return }
    let sortedSlots = (preset.slots ?? []).sorted { $0.periodIndex < $1.periodIndex }
    let maxPeriod = sortedSlots.map(\.periodIndex).max() ?? 0
    guard maxPeriod < requiredPeriodCount else { return }

    let cal = Calendar.current
    var ref: Date
    if let last = sortedSlots.last {
        ref = cal.date(bySettingHour: last.endHour, minute: last.endMinute, second: 0, of: Date())!
    } else {
        ref = cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
    }

    for period in (maxPeriod + 1) ... requiredPeriodCount {
        let gapMinutes = (period == maxPeriod + 1 && sortedSlots.isEmpty) ? 0 : 10
        let nextStart = cal.date(byAdding: .minute, value: gapMinutes, to: ref)!
        let nextEnd = cal.date(byAdding: .minute, value: 40, to: nextStart)!
        let startH = cal.component(.hour, from: nextStart)
        let startM = cal.component(.minute, from: nextStart)
        let endH = cal.component(.hour, from: nextEnd)
        let endM = cal.component(.minute, from: nextEnd)
        let slot = TimeSlotItem(periodIndex: period, startHour: startH, startMinute: startM, endHour: endH, endMinute: endM)
        slot.preset = preset
        preset.slots = (preset.slots ?? []) + [slot]
        modelContext.insert(slot)
        ref = nextEnd
    }
    try? modelContext.save()
}

/// 默认学期第一天：取「下一个周一」或「今天若已是周一」
private func defaultSemesterStartDate() -> Date {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let weekday = cal.component(.weekday, from: today) // 1 = Sun, 2 = Mon, ...
    let daysUntilMonday = weekday == 1 ? 1 : (weekday == 2 ? 0 : (9 - weekday))
    return cal.date(byAdding: .day, value: daysUntilMonday, to: today) ?? today
}

/// 若尚无任何课程表，则先创建预设再创建默认课程表并写入 activeScheduleName；并迁移无 schedule 的课程到第一张课表
@MainActor
func seedDefaultScheduleIfNeeded(modelContext: ModelContext) {
    let scheduleDescriptor = FetchDescriptor<Schedule>()
    let schedules = (try? modelContext.fetch(scheduleDescriptor)) ?? []
    if schedules.isEmpty {
        seedDefaultPresetsIfNeeded(modelContext: modelContext)
        let presets = (try? modelContext.fetch(FetchDescriptor<TimeSlotPreset>())) ?? []
        let start = defaultSemesterStartDate()
        let defaultName = "我的课程表"
        let schedule = Schedule(name: defaultName, semesterStartDate: start)
        schedule.timeSlotPreset = presets.first
        modelContext.insert(schedule)
        try? modelContext.save()
        UserDefaults.standard.set(defaultName, forKey: "activeScheduleName")
        if UserDefaults.standard.string(forKey: ScheduleDisplayKeys.activeTimeSlotPresetName)?.isEmpty != false,
           let firstPresetName = presets.first?.name {
            UserDefaults.standard.set(firstPresetName, forKey: ScheduleDisplayKeys.activeTimeSlotPresetName)
        }
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
