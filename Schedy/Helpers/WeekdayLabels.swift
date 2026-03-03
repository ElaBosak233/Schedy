//
//  WeekdayLabels.swift
//  Schedy
//
//  星期几的中文标签统一常量，避免在 Course、课表网格、调课/编辑等多处重复定义。
//

import Foundation

/// 星期几的中文显示名称（与 Course.dayOfWeek 一致：1=周一 … 7=周日）
enum WeekdayLabels {

    /// 索引 0 占位不用，索引 1…7 对应周一…周日，用于按 dayOfWeek 直接下标访问
    static let chinese: [String] = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    /// 仅周一…周日的 7 个标签（无占位），用于课表表头等列标题
    static let columnLabels: [String] = Array(chinese.dropFirst())

    /// 根据 dayOfWeek（1…7）返回中文名，越界返回 "?"
    static func name(forDayOfWeek day: Int) -> String {
        guard day >= 1, day <= 7 else { return "?" }
        return chinese[day]
    }
}
