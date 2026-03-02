//
//  AcademicAffairsType.swift
//  Schedy
//
//  教务类型（每种对应一种解析算法）
//

import Foundation

/// 教务类型（每种对应一种解析算法）
enum AcademicAffairsType: String, CaseIterable {
    case zhengFang = "正方教务"

    var displayName: String { rawValue }
}
