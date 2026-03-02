//
//  CSVExport.swift
//  Schedy
//
//  将当前课表导出为 CSV（与导入格式一致，便于备份或二次编辑）
//

import Foundation

enum CSVExport {
    /// 与 CSV 导入一致的表头
    private static let header = "课程名,教师,地点,学分,周次,单双周,星期,起始节,结束节"

    /// 将课程表导出为 CSV 字符串（UTF-8，与导入模板列一致）
    static func csvString(from schedule: Schedule?) -> String {
        guard let schedule = schedule, let courses = schedule.courses, !courses.isEmpty else {
            return header + "\n"
        }
        let lines = [header] + courses.sorted(by: { c1, c2 in
            if c1.dayOfWeek != c2.dayOfWeek { return c1.dayOfWeek < c2.dayOfWeek }
            return c1.periodIndex < c2.periodIndex
        }).map { row(for: $0) }
        return lines.joined(separator: "\n")
    }

    private static func row(for course: Course) -> String {
        let courseName = escapeCSV(course.name)
        let teacher = escapeCSV(course.teacher ?? "")
        let location = escapeCSV(course.location ?? "")
        let credits: String = course.credits.map { String(format: "%g", $0) } ?? ""
        let weekRanges = escapeCSV(course.weekRangesString ?? weekRangesExportString(course))
        let weekParityStr = course.weekParity.displayName
        let day = "\(course.dayOfWeek)"
        let startPeriod = "\(course.periodIndex)"
        let endPeriod = course.periodIndex == course.effectivePeriodEnd ? "" : "\(course.effectivePeriodEnd)"
        return [courseName, teacher, location, credits, weekRanges, weekParityStr, day, startPeriod, endPeriod].joined(separator: ",")
    }

    /// 从 parsedWeekRanges 生成导入格式的周次字符串，如 "1-16" 或 "1-1,5-8"
    private static func weekRangesExportString(_ course: Course) -> String {
        let ranges = course.parsedWeekRanges
        return ranges.map { r in r.start == r.end ? "\(r.start)" : "\(r.start)-\(r.end)" }.joined(separator: ",")
    }

    /// 字段含逗号、换行或双引号时用双引号包裹，内部双引号加倍
    private static func escapeCSV(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\n") || value.contains("\r") || value.contains("\"")
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
