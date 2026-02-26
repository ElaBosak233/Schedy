//
//  AcademicAffairsImportModels.swift
//  schedy
//
//  学校→教务（Academic Affairs）映射、解析结果模型
//

import Foundation

// MARK: - 教务类型（每种对应一种解析算法）
enum AcademicAffairsType: String, CaseIterable {
    case zhengFang = "正方教务"

    var displayName: String { rawValue }
}

// MARK: - 学校信息：名称、使用的教务类型、教务系统入口 URL
struct SchoolInfo: Identifiable {
    let id: String
    let name: String
    let academicAffairsType: AcademicAffairsType
    let entryURL: URL

    static let all: [SchoolInfo] = [
        SchoolInfo(
            id: "tzc",
            name: "台州学院",
            academicAffairsType: .zhengFang,
            entryURL: URL(string: "https://jwc.tzc.edu.cn")!
        ),
    ]
}

// MARK: - 解析出的一门课（尚未写入 SwiftData）
struct ParsedCourseItem {
    var name: String
    var teacher: String
    var location: String
    /// 学分（可选，从教务 HTML 解析）
    var credits: Double?
    var weekRangesString: String
    var weekParity: WeekParity
    var dayOfWeek: Int   // 1=周一 … 7=周日
    var periodIndex: Int
    var periodEnd: Int
}
