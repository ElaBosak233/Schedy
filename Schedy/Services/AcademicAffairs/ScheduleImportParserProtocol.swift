//
//  ScheduleImportParserProtocol.swift
//  schedy
//
//  教务系统课表 HTML 解析协议：不同实现（正方等）放在 AcademicAffairs 子目录
//

import Foundation

/// 从教务系统「个人课表查询」页面 HTML 解析出课程列表的协议
protocol ScheduleImportParserProtocol {
    /// 解析完整 HTML，返回课程列表；解析失败或非课表页返回空数组
    static func parse(html: String) -> [ParsedCourseItem]
}
