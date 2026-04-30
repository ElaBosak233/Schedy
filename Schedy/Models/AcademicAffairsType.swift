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
    case qiangZhi = "强智教务"
    case chaoXing = "超星教务"
    case kingo = "金智教务"
    case urp = "URP 综合教务"
    case south = "南软教务"
    case wisedu = "金智 Wisedu"

    var displayName: String { rawValue }
}
