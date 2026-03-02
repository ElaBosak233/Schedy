//
//  Schedule.swift
//  Schedy
//
//  课程表数据模型
//

import Foundation
import SwiftData

/// 一张独立的课程表：名称、本学期第一天。时间段由全局「当前时间段」决定，不绑定在课表上。
@Model
final class Schedule {
    var name: String = ""
    /// 本学期第一天（用于按周计算日期，周一为第一天）
    var semesterStartDate: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \Course.schedule)
    var courses: [Course]?
    /// 该课程表下所有调课记录（独立数据结构，便于按课程表溯源与还原）
    @Relationship(deleteRule: .cascade, inverse: \CourseReschedule.schedule)
    var reschedules: [CourseReschedule]?

    init(name: String, semesterStartDate: Date) {
        self.name = name
        self.semesterStartDate = semesterStartDate
    }

    /// 课表显示周数上限：有课的最大周 + 1（无课时为 1 周）。用于课表滑动范围、调课可选周等。
    var effectiveMaxWeeks: Int {
        let c = courses ?? []
        let fromRanges = c.flatMap(\.parsedWeekRanges).map(\.end).max() ?? 0
        let fromReschedules = c.flatMap { ($0.reschedules ?? []) }.flatMap { [$0.week, $0.effectiveNewWeek] }.max() ?? 0
        let maxCourseWeek = max(fromRanges, fromReschedules)
        return max(1, maxCourseWeek + 1)
    }
}
