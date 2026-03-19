//
//  Calendar+Semester.swift
//  Schedy
//
//  学期周次计算：根据学期第一天与当前日期得到「当前是第几周」（1-based），供通知、小组件等复用。
//

import Foundation

extension Calendar {

    /// 根据学期第一天和当前日期计算当前周（1-based）。
    /// - Parameters:
    ///   - semesterStart: 学期第一天（通常为周一）
    ///   - calendar: 使用的日历，一般传 `Calendar.current`
    /// - Returns: 第几周，1 起算；若今天早于学期开始则返回 1；上限 25 周（与课程表最大周次一致）
    static func currentWeek(semesterStart: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: semesterStart)
        // 对齐到学期第一天所在周的周一
        let weekday = calendar.component(.weekday, from: start)  // 1=周日,2=周一,...,7=周六
        let daysToMonday = weekday == 1 ? -6 : -(weekday - 2)
        let weekOneMonday = calendar.date(byAdding: .day, value: daysToMonday, to: start) ?? start
        guard today >= weekOneMonday else { return 1 }
        let days = calendar.dateComponents([.day], from: weekOneMonday, to: today).day ?? 0
        return min(max(1, days / 7 + 1), 25)
    }
}
