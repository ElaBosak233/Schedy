//
//  TimeSlotItem.swift
//  Schedy
//
//  单节时间段：节次序号 + 起止时分，属于某个 TimeSlotPreset。
//

import Foundation
import SwiftData

/// 某一节课的起止时间（如 8:00~8:40），节次 1 起算；归属某个时间段预设
@Model
final class TimeSlotItem {
    /// 节次序号（1 起算，与 Course.periodIndex 对应）
    var periodIndex: Int = 1
    var startHour: Int = 0
    var startMinute: Int = 0
    var endHour: Int = 0
    var endMinute: Int = 0

    var preset: TimeSlotPreset?

    init(periodIndex: Int, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.periodIndex = periodIndex
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    /// 开始时间字符串，如 "08:00"
    var startTimeString: String {
        String(format: "%02d:%02d", startHour, startMinute)
    }

    /// 结束时间字符串，如 "08:40"
    var endTimeString: String {
        String(format: "%02d:%02d", endHour, endMinute)
    }

    /// 整段显示，如 "08:00 ~ 08:40"
    var timeRangeString: String {
        "\(startTimeString) ~ \(endTimeString)"
    }
}
