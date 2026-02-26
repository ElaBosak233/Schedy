//
//  WidgetDataKeys.swift
//  SchedyWidget
//
//  与主 App WidgetDataService 中写入的 key 保持一致
//

import Foundation

let kWidgetAppGroupSuiteName = "group.dev.e23.schedy"

enum WidgetDataKeys {
    static let scheduleName = "widgetScheduleName"
    static let date = "widgetDate"
    static let weekday = "widgetWeekday"
    static let status = "widgetStatus"
    static let course1Name = "widgetCourse1Name"
    static let course1Time = "widgetCourse1Time"
    static let course1Location = "widgetCourse1Location"
    static let course2Name = "widgetCourse2Name"
    static let course2Time = "widgetCourse2Time"
    static let course2Location = "widgetCourse2Location"
}

struct WidgetEntry {
    let scheduleName: String
    let dateString: String
    let weekdayString: String
    let status: String  // "noClass" | "allDone" | "next"
    let course1: (name: String, time: String, location: String)?
    let course2: (name: String, time: String, location: String)?

    static func load(from suite: UserDefaults?) -> WidgetEntry {
        guard let suite = suite else {
            return WidgetEntry(scheduleName: "课程表", dateString: "", weekdayString: "", status: "noClass", course1: nil, course2: nil)
        }
        let scheduleName = suite.string(forKey: WidgetDataKeys.scheduleName) ?? "课程表"
        let dateString = suite.string(forKey: WidgetDataKeys.date) ?? ""
        let weekdayString = suite.string(forKey: WidgetDataKeys.weekday) ?? ""
        let status = suite.string(forKey: WidgetDataKeys.status) ?? "noClass"
        let c1Name = suite.string(forKey: WidgetDataKeys.course1Name) ?? ""
        let c1Time = suite.string(forKey: WidgetDataKeys.course1Time) ?? ""
        let c1Location = suite.string(forKey: WidgetDataKeys.course1Location) ?? ""
        let c2Name = suite.string(forKey: WidgetDataKeys.course2Name) ?? ""
        let c2Time = suite.string(forKey: WidgetDataKeys.course2Time) ?? ""
        let c2Location = suite.string(forKey: WidgetDataKeys.course2Location) ?? ""

        let course1: (name: String, time: String, location: String)? = c1Name.isEmpty ? nil : (c1Name, c1Time, c1Location)
        let course2: (name: String, time: String, location: String)? = c2Name.isEmpty ? nil : (c2Name, c2Time, c2Location)

        return WidgetEntry(
            scheduleName: scheduleName,
            dateString: dateString,
            weekdayString: weekdayString,
            status: status,
            course1: course1,
            course2: course2
        )
    }
}
