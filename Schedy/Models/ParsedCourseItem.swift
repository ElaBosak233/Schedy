//
//  ParsedCourseItem.swift
//  Schedy
//
//  解析出的一门课（尚未写入 SwiftData）
//

import Foundation

/// 解析出的一门课（来自 CSV 或教务 HTML，尚未写入 SwiftData）
struct ParsedCourseItem {
    var name: String
    var teacher: String
    var location: String
    /// 学分（可选）
    var credits: Double?
    var weekRangesString: String
    var weekParity: Course.WeekParity
    var dayOfWeek: Int   // 1=周一 … 7=周日
    var periodIndex: Int
    var periodEnd: Int
}
