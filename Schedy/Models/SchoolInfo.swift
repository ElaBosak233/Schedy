//
//  SchoolInfo.swift
//  Schedy
//
//  学校信息：名称、使用的教务类型、教务系统入口 URL
//

import Foundation

/// 学校教务系统类型
enum SchoolAcademicAffairsType: String {
    case zhengFang
    case qiangZhi
    case chaoXing
    case unknown
    case kingo
    case urp
    case south

    init(rawType: String) {
        switch rawType {
        case "zhengFang":
            self = .zhengFang
        case "qiangZhi":
            self = .qiangZhi
        case "chaoXing":
            self = .chaoXing
        case "unkown":
            self = .unknown
        case "kingo":
            self = .kingo
        case "urp":
            self = .urp
        case "south":
            self = .south
        default:
            self = .unknown
        }
    }

    var academicAffairsType: AcademicAffairsType? {
        switch self {
        case .zhengFang:
            return .zhengFang
        case .qiangZhi:
            return .qiangZhi
        case .chaoXing:
            return .chaoXing
        case .unknown, .kingo, .urp, .south:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .zhengFang:
            return AcademicAffairsType.zhengFang.displayName
        case .qiangZhi:
            return AcademicAffairsType.qiangZhi.displayName
        case .chaoXing:
            return AcademicAffairsType.chaoXing.displayName
        case .kingo:
            return "Kingo（暂未支持）"
        case .urp:
            return "URP（暂未支持）"
        case .south:
            return "South（暂未支持）"
        case .unknown:
            return "未知教务"
        }
    }
}

/// 学校信息：名称、使用的教务类型、教务系统入口 URL
struct SchoolInfo: Identifiable {
    let id: String
    let name: String
    let systemType: SchoolAcademicAffairsType
    let entryURL: URL?

    var academicAffairsType: AcademicAffairsType? {
        systemType.academicAffairsType
    }

    var isSupportedType: Bool {
        academicAffairsType != nil
    }

    var isEnabled: Bool {
        isSupportedType && entryURL != nil
    }

    var typeDisplayName: String {
        systemType.displayName
    }

    static let all: [SchoolInfo] = SchoolCatalogStore.loadAll()
}

private enum SchoolCatalogStore {
    private struct SchoolDTO: Decodable {
        let id: String
        let name: String
        let type: String
        let url: String
    }

    static func loadAll() -> [SchoolInfo] {
        guard let resourceURL = schoolsResourceURL,
              let data = try? Data(contentsOf: resourceURL),
              let items = try? JSONDecoder().decode([SchoolDTO].self, from: data) else {
            assertionFailure("Failed to load schools.json from app bundle")
            return []
        }

        return items.map {
            SchoolInfo(
                id: $0.id,
                name: $0.name,
                systemType: SchoolAcademicAffairsType(rawType: $0.type),
                entryURL: URL(string: $0.url)
            )
        }
    }

    private static var schoolsResourceURL: URL? {
        let candidates = [Bundle.main, Bundle(for: BundleMarker.self)]
        for bundle in candidates {
            if let url = bundle.url(forResource: "schools", withExtension: "json") {
                return url
            }
        }
        return nil
    }

    private final class BundleMarker {}
}
