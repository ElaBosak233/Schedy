//
//  ScheduleModels.swift
//  schedy
//
//  课程表数据模型
//

import Foundation
import SwiftData

// MARK: - 课程表
/// 一张独立的课程表：名称、本学期第一天、绑定的时间段预设
@Model
final class Schedule {
    var name: String
    /// 本学期第一天（用于按周计算日期，周一为第一天）
    var semesterStartDate: Date
    /// 绑定的时间段预设（冬令时/夏令时等）
    var timeSlotPreset: TimeSlotPreset?
    @Relationship(deleteRule: .cascade, inverse: \Course.schedule)
    var courses: [Course] = []

    init(name: String, semesterStartDate: Date, timeSlotPreset: TimeSlotPreset? = nil) {
        self.name = name
        self.semesterStartDate = semesterStartDate
        self.timeSlotPreset = timeSlotPreset
    }
}

// MARK: - 周次奇偶
/// 单双周：全部 / 单周 / 双周
enum WeekParity: Int, CaseIterable {
    case all = 0
    case odd = 1   // 单周：1,3,5,...
    case even = 2  // 双周：2,4,6,...

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .odd: return "单周"
        case .even: return "双周"
        }
    }
}

// MARK: - 课程
/// 一门课程所需的数据：课程名、课程时间（周次范围 + 星期 + 节次）、任课老师、地点、学分
/// 支持跨节次：periodIndex 为起始节，periodEnd 为结束节（含），未设则单节
/// 周次：weekRangesString 格式为 "1-1,5-8" 表示第1周 + 第5~8周；可配合 weekParity 单双周
@Model
final class Course {
    var name: String
    var teacher: String
    var location: String
    /// 学分（可选，兼容旧数据）
    var credits: Double?
    /// 周次范围字符串，如 "1-1,5-8"（兼容旧数据：nil 或空时用 weekIndex）
    var weekRangesString: String?
    /// 单双周：0=全部，1=单周，2=双周（兼容旧数据：nil 视为 0）
    var weekParityRaw: Int?
    /// 兼容旧数据：仅当 weekRangesString 为空时使用，表示单周
    var weekIndex: Int
    /// 周几（1 = 周一 … 7 = 周日）
    var dayOfWeek: Int
    /// 起始节（1 起算，对应时间段预设中的节次）
    var periodIndex: Int
    /// 结束节（含）；nil 或等于 periodIndex 表示单节
    var periodEnd: Int?
    /// 所属课程表
    var schedule: Schedule?

    init(
        name: String,
        teacher: String,
        location: String,
        credits: Double? = nil,
        weekRangesString: String = "",
        weekParity: WeekParity = .all,
        weekIndex: Int = 1,
        dayOfWeek: Int,
        periodIndex: Int,
        periodEnd: Int? = nil,
        schedule: Schedule? = nil
    ) {
        self.name = name
        self.teacher = teacher
        self.location = location
        self.credits = credits
        self.weekRangesString = weekRangesString.isEmpty ? nil : weekRangesString
        self.weekParityRaw = weekParity == .all ? nil : weekParity.rawValue
        self.weekIndex = weekIndex
        self.dayOfWeek = dayOfWeek
        self.periodIndex = periodIndex
        self.periodEnd = periodEnd
        self.schedule = schedule
    }

    /// 单双周
    var weekParity: WeekParity {
        get { WeekParity(rawValue: weekParityRaw ?? 0) ?? .all }
        set { weekParityRaw = newValue == .all ? nil : newValue.rawValue }
    }

    /// 解析周次范围为 [(start, end)]，空时退回为 [weekIndex, weekIndex]
    var parsedWeekRanges: [(start: Int, end: Int)] {
        let s = (weekRangesString ?? "").trimmingCharacters(in: .whitespaces)
        if !s.isEmpty {
            var out: [(Int, Int)] = []
            let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for part in parts {
                let nums = part.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if nums.count >= 2 {
                    let a = max(1, nums[0])
                    let b = max(a, nums[1])
                    out.append((a, b))
                } else if let single = nums.first {
                    out.append((max(1, single), max(1, single)))
                }
            }
            if !out.isEmpty { return out }
        }
        return [(max(1, weekIndex), max(1, weekIndex))]
    }

    /// 判断某周是否在课程周次内（含单双周）
    func appliesToWeek(_ week: Int) -> Bool {
        let ranges = parsedWeekRanges
        let inRange = ranges.contains { week >= $0.start && week <= $0.end }
        guard inRange else { return false }
        switch weekParity {
        case .all: return true
        case .odd: return week % 2 == 1
        case .even: return week % 2 == 0
        }
    }

    /// 结束节（含），未设则与起始节相同
    var effectivePeriodEnd: Int { periodEnd ?? periodIndex }

    /// 跨几节（至少为 1）
    var periodSpan: Int { max(1, effectivePeriodEnd - periodIndex + 1) }

    var dayOfWeekName: String {
        let names = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        guard dayOfWeek >= 1, dayOfWeek <= 7 else { return "?" }
        return names[dayOfWeek]
    }

    /// 周次展示文案，如 "第1、5-8周"、"第1、5-8周 单周"
    var weekRangesDisplayString: String {
        let ranges = parsedWeekRanges
        let parts = ranges.map { r in
            r.start == r.end ? "\(r.start)" : "\(r.start)-\(r.end)"
        }
        let base = "第" + parts.joined(separator: "、") + "周"
        if weekParity == .all { return base }
        return base + " " + weekParity.displayName
    }
}

// MARK: - 单节时间段（用于预设内）
/// 某一节课的起止时间，如 8:00~8:40
@Model
final class TimeSlotItem {
    var periodIndex: Int
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

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

// MARK: - 时间段预设
/// 一套时间段预设，如「冬令时」「夏令时」，包含多节课的起止时间
@Model
final class TimeSlotPreset {
    var name: String
    var createdAt: Date
    var slots: [TimeSlotItem] = []

    init(name: String, slots: [TimeSlotItem] = []) {
        self.name = name
        self.createdAt = Date()
        self.slots = slots
    }
}

// MARK: - 默认时间段（一天最多 20 节，每节 40 分钟、课间 10 分钟）
enum DefaultTimeSlots {
    /// 常见冬令时：8:00 起
    static func winter() -> [(period: Int, start: (h: Int, m: Int), end: (h: Int, m: Int))] {
        [
            (1, (8, 0), (8, 40)),
            (2, (8, 50), (9, 30)),
            (3, (9, 50), (10, 30)),
            (4, (10, 40), (11, 20)),
            (5, (11, 30), (12, 10)),
            (6, (14, 0), (14, 40)),
            (7, (14, 50), (15, 30)),
            (8, (15, 40), (16, 20)),
            (9, (16, 30), (17, 10)),
            (10, (19, 0), (19, 40)),
            (11, (19, 50), (20, 30)),
            (12, (20, 40), (21, 20)),
            (13, (21, 30), (22, 10)),
            (14, (22, 20), (23, 0)),
            (15, (23, 10), (23, 50)),
            (16, (0, 10), (0, 50)),
            (17, (1, 0), (1, 40)),
            (18, (1, 50), (2, 30)),
            (19, (2, 40), (3, 20)),
            (20, (3, 30), (4, 10)),
        ]
    }

    /// 常见夏令时：8:30 起
    static func summer() -> [(period: Int, start: (h: Int, m: Int), end: (h: Int, m: Int))] {
        [
            (1, (8, 30), (9, 10)),
            (2, (9, 20), (10, 0)),
            (3, (10, 20), (11, 0)),
            (4, (11, 10), (11, 50)),
            (5, (12, 0), (12, 40)),
            (6, (14, 30), (15, 10)),
            (7, (15, 20), (16, 0)),
            (8, (16, 10), (16, 50)),
            (9, (17, 0), (17, 40)),
            (10, (19, 30), (20, 10)),
            (11, (20, 20), (21, 0)),
            (12, (21, 10), (21, 50)),
            (13, (22, 0), (22, 40)),
            (14, (22, 50), (23, 30)),
            (15, (23, 40), (0, 20)),
            (16, (0, 30), (1, 10)),
            (17, (1, 20), (2, 0)),
            (18, (2, 10), (2, 50)),
            (19, (3, 0), (3, 40)),
            (20, (3, 50), (4, 30)),
        ]
    }
}
