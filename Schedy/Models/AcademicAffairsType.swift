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

    var displayName: String {
        switch self {
        case .zhengFang: return String(localized: "academic_system.zhengfang.name", defaultValue: "Zhengfang Academic Affairs")
        case .qiangZhi: return String(localized: "academic_system.qiangzhi.name", defaultValue: "Qiangzhi Academic Affairs")
        case .chaoXing: return String(localized: "academic_system.chaoxing.name", defaultValue: "Chaoxing Academic Affairs")
        case .kingo: return String(localized: "academic_system.kingo.name", defaultValue: "Kingo Academic Affairs")
        case .urp: return String(localized: "academic_system.urp.name", defaultValue: "URP Academic Affairs")
        case .south: return String(localized: "academic_system.south.name", defaultValue: "Nansoft Academic Affairs")
        case .wisedu: return String(localized: "academic_system.wisedu.name", defaultValue: "Wisedu")
        }
    }
}
