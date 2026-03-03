//
//  TimeSlotPreset.swift
//  Schedy
//
//  时间段预设：一套节次起止时间（如冬令时/夏令时），可被多张课表绑定。
//

import Foundation
import SwiftData

/// 一套时间段，如「冬令时」「夏令时」，包含多节 TimeSlotItem；课表可绑定其一，未绑定时用 App 默认预设
@Model
final class TimeSlotPreset {
    var name: String = ""
    var createdAt: Date = Date()
    var slots: [TimeSlotItem]?
    @Relationship(inverse: \Schedule.timeSlotPreset)
    var schedules: [Schedule]?

    init(name: String, slots: [TimeSlotItem] = []) {
        self.name = name
        self.createdAt = Date()
        self.slots = slots.isEmpty ? nil : slots
    }

    // MARK: - 默认时间段（首次启动时由 ScheduleDataService 写入）

    /// 内置冬令时 / 夏令时数据，供创建默认预设使用
    enum Default {
        /// 冬令时：15 节，节次 1…15 的起止时间
        static func winter() -> [(period: Int, start: (h: Int, m: Int), end: (h: Int, m: Int))] {
            [
                (1, (8, 00), (8, 40)),
                (2, (8, 45), (9, 25)),
                (3, (9, 45), (10, 25)),
                (4, (10, 30), (11, 10)),
                (5, (11, 15), (11, 55)),
                (6, (13, 30), (14, 10)),
                (7, (14, 15), (14, 55)),
                (8, (15, 15), (15, 55)),
                (9, (16, 00), (16, 40)),
                (10, (18, 30), (19, 10)),
                (11, (19, 15), (19, 55)),
                (12, (20, 00), (20, 40)),
                (13, (20, 45), (21, 25)),
                (14, (21, 30), (22, 10)),
                (15, (22, 15), (22, 55)),
            ]
        }

        /// 夏令时：15 节，下午/晚上比冬令时略晚
        static func summer() -> [(period: Int, start: (h: Int, m: Int), end: (h: Int, m: Int))] {
            [
                (1, (8, 00), (8, 40)),
                (2, (8, 45), (9, 25)),
                (3, (9, 45), (10, 25)),
                (4, (10, 30), (11, 10)),
                (5, (11, 15), (11, 55)),
                (6, (14, 00), (14, 40)),
                (7, (14, 45), (15, 25)),
                (8, (15, 45), (16, 25)),
                (9, (16, 30), (17, 10)),
                (10, (19, 00), (19, 40)),
                (11, (19, 45), (20, 25)),
                (12, (20, 30), (21, 10)),
                (13, (21, 15), (21, 55)),
                (14, (22, 00), (22, 40)),
                (15, (22, 45), (23, 25)),
            ]
        }
    }
}
