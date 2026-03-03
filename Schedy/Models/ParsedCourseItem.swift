//
//  ParsedCourseItem.swift
//  Schedy
//
//  导入流程中的中间结构：CSV/教务解析得到的一门课，校验后转为 Course 写入 SwiftData。
//

import Foundation

/// 解析出的一门课（来自 CSV 或教务 HTML），尚未写入 SwiftData；dayOfWeek 与 Course 一致（1=周一…7=周日）
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
