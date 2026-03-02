//
//  Course.swift
//  Schedy
//
//  课程数据模型
//

import Foundation
import SwiftData

/// 一门课程所需的数据：课程名、课程时间（周次范围 + 星期 + 节次）、任课老师、地点、学分
/// 支持跨节次：periodIndex 为起始节，periodEnd 为结束节（含），未设则单节
/// 周次：weekRangesString 格式为 "1-1,5-8" 表示第1周 + 第5~8周；可配合 weekParity 单双周
/// teacher、location 可选，为空时界面不展示对应项
@Model
final class Course {

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

    var name: String = ""
    var teacher: String?
    var location: String?
    /// 学分（可选，兼容旧数据）
    var credits: Double?
    /// 周次范围字符串，如 "1-1,5-8"（兼容旧数据：nil 或空时用 weekIndex）
    var weekRangesString: String?
    /// 单双周：0=全部，1=单周，2=双周（兼容旧数据：nil 视为 0）
    var weekParityRaw: Int?
    /// 兼容旧数据：仅当 weekRangesString 为空时使用，表示单周
    var weekIndex: Int = 1
    /// 周几（1 = 周一 … 7 = 周日）
    var dayOfWeek: Int = 1
    /// 起始节（1 起算，对应时间段中的节次）
    var periodIndex: Int = 1
    /// 结束节（含）；nil 或等于 periodIndex 表示单节
    var periodEnd: Int?
    /// 所属课程表
    var schedule: Schedule?
    /// 单次调课记录（仅影响指定周次的一块课）
    @Relationship(deleteRule: .cascade, inverse: \CourseReschedule.course)
    var reschedules: [CourseReschedule]?

    init(
        name: String,
        teacher: String? = nil,
        location: String? = nil,
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
        self.teacher = teacher?.isEmpty == true ? nil : teacher
        self.location = location?.isEmpty == true ? nil : location
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

    /// 该课程在指定周次是否已有调课记录（调至其他时间）
    func reschedule(forWeek week: Int) -> CourseReschedule? {
        (reschedules ?? []).first { $0.week == week }
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
