//
//  TimeSlotItem.swift
//  Schedy
//
//  单节时间段
//

import Foundation
import SwiftData

/// 某一节课的起止时间，如 8:00~8:40
@Model
final class TimeSlotItem {
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

    var startTimeString: String {
        String(format: "%02d:%02d", startHour, startMinute)
    }

    var endTimeString: String {
        String(format: "%02d:%02d", endHour, endMinute)
    }

    var timeRangeString: String {
        "\(startTimeString) ~ \(endTimeString)"
    }
}
