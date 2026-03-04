//
//  SchoolInfo.swift
//  Schedy
//
//  学校信息：名称、使用的教务类型、教务系统入口 URL
//

import Foundation

/// 学校信息：名称、使用的教务类型、教务系统入口 URL
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
        SchoolInfo(
            id: "kdcnu",
            name: "首都师范大学科德学院",
            academicAffairsType: .qiangZhi,
            entryURL: URL(string: "http://jw.kdcnu.com/sdsfdxkdxy_jsxsd/")!
        ),
        SchoolInfo(
            id: "tzvcst",
            name: "台州科技职业学院",
            academicAffairsType: .chaoXing,
            entryURL: URL(string: "https://tzvcst.jw.chaoxing.com/admin/login")!
        )
    ]
}
