//
//  WidgetDataKeys.swift
//  SchedyWidget
//
//  与主 App WidgetDataService 中写入的 key 保持一致
//

import Foundation

let kWidgetAppGroupSuiteName = "group.dev.e23.schedy"

/// 跟随 App 当前选中的课表（设置里显示的选项值；若用户某张课表恰好同名则选该选项时仍视为「跟随」）
let kWidgetScheduleOptionFollowApp = "跟随 App 当前选中"

/// 跟随 App 当前选中的时间段
let kWidgetPresetOptionFollowApp = "跟随 App 当前选中"

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

    static let scheduleNamesList = "widgetScheduleNamesList"
    static let defaultScheduleName = "widgetDefaultScheduleName"
    static let presetNamesList = "widgetPresetNamesList"
    static let defaultPresetName = "widgetDefaultPresetName"
    static let entryPrefix = "widgetEntry"
    static let entrySeparator = "__SEP__"
}

struct WidgetEntry {
    let scheduleName: String
    let dateString: String
    let weekdayString: String
    let status: String  // "noClass" | "allDone" | "next"
    let course1: (name: String, time: String, location: String)?
    let course2: (name: String, time: String, location: String)?

    /// 从 suite 读取「课表+时间段」的缓存数据（key 为 entryPrefix_scheduleName__SEP__presetName）
    static func load(from suite: UserDefaults?, scheduleName name: String, presetName preset: String) -> WidgetEntry {
        guard let suite = suite else {
            return WidgetEntry(scheduleName: "课程表", dateString: "", weekdayString: "", status: "noClass", course1: nil, course2: nil)
        }
        let key = "\(WidgetDataKeys.entryPrefix)_\(name)\(WidgetDataKeys.entrySeparator)\(preset)"
        if let dict = suite.dictionary(forKey: key) as? [String: String] {
            return parseEntryDict(dict: dict, fallbackScheduleName: name)
        }
        // 兼容旧版：仅课表名的 key（主 App 未刷新前）
        if let legacy = loadLegacy(from: suite, scheduleName: name) {
            return legacy
        }
        return WidgetEntry(scheduleName: name.isEmpty ? "课程表" : name, dateString: "", weekdayString: "", status: "noClass", course1: nil, course2: nil)
    }

    private static func parseEntryDict(dict: [String: String], fallbackScheduleName: String) -> WidgetEntry {
        let scheduleName = dict[WidgetDataKeys.scheduleName] ?? fallbackScheduleName
        let dateString = dict[WidgetDataKeys.date] ?? ""
        let weekdayString = dict[WidgetDataKeys.weekday] ?? ""
        let status = dict[WidgetDataKeys.status] ?? "noClass"
        let c1Name = dict[WidgetDataKeys.course1Name] ?? ""
        let c1Time = dict[WidgetDataKeys.course1Time] ?? ""
        let c1Location = dict[WidgetDataKeys.course1Location] ?? ""
        let c2Name = dict[WidgetDataKeys.course2Name] ?? ""
        let c2Time = dict[WidgetDataKeys.course2Time] ?? ""
        let c2Location = dict[WidgetDataKeys.course2Location] ?? ""
        let course1: (name: String, time: String, location: String)? = c1Name.isEmpty ? nil : (c1Name, c1Time, c1Location)
        let course2: (name: String, time: String, location: String)? = c2Name.isEmpty ? nil : (c2Name, c2Time, c2Location)
        return WidgetEntry(scheduleName: scheduleName, dateString: dateString, weekdayString: weekdayString, status: status, course1: course1, course2: course2)
    }

    /// 解析「小组件要显示的课表名」：若为跟随 App 或该课表已不存在，则回退到默认/第一张
    static func resolveScheduleNameToShow(suite: UserDefaults?, configuredName: String) -> String {
        let list = suite?.stringArray(forKey: WidgetDataKeys.scheduleNamesList) ?? []
        let defaultName = suite?.string(forKey: WidgetDataKeys.defaultScheduleName) ?? ""

        let nameToUse: String
        if configuredName == kWidgetScheduleOptionFollowApp {
            nameToUse = defaultName
        } else {
            nameToUse = configuredName
        }
        if list.contains(nameToUse) {
            return nameToUse
        }
        if !defaultName.isEmpty && list.contains(defaultName) {
            return defaultName
        }
        return list.first ?? ""
    }

    /// 解析「小组件要使用的时间段名」：若为跟随 App 或该时间段已不存在，则回退到默认/第一个
    static func resolvePresetNameToShow(suite: UserDefaults?, configuredPreset: String) -> String {
        let list = suite?.stringArray(forKey: WidgetDataKeys.presetNamesList) ?? []
        let defaultPreset = suite?.string(forKey: WidgetDataKeys.defaultPresetName) ?? ""

        let presetToUse: String
        if configuredPreset == kWidgetPresetOptionFollowApp {
            presetToUse = defaultPreset
        } else {
            presetToUse = configuredPreset
        }
        if list.contains(presetToUse) {
            return presetToUse
        }
        if !defaultPreset.isEmpty && list.contains(defaultPreset) {
            return defaultPreset
        }
        return list.first ?? ""
    }
}

extension WidgetEntry {
    /// 兼容旧版：按课表名读取 key "widgetEntry_\(scheduleName)"（无时间段时的单课表 key）
    static func loadLegacy(from suite: UserDefaults?, scheduleName name: String) -> WidgetEntry? {
        guard let suite = suite else { return nil }
        let key = "\(WidgetDataKeys.entryPrefix)_\(name)"
        guard let dict = suite.dictionary(forKey: key) as? [String: String] else { return nil }
        return parseEntryDict(dict: dict, fallbackScheduleName: name)
    }

    /// 兼容旧版 App：从旧版扁平 key（无 widgetEntry_*）读取
    static func loadLegacy(from suite: UserDefaults?) -> WidgetEntry? {
        guard let suite = suite else { return nil }
        let scheduleName = suite.string(forKey: WidgetDataKeys.scheduleName)
        guard scheduleName != nil else { return nil }
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
        return WidgetEntry(scheduleName: scheduleName ?? "课程表", dateString: dateString, weekdayString: weekdayString, status: status, course1: course1, course2: course2)
    }
}
