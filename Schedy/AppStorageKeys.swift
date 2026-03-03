//
//  AppStorageKeys.swift
//  Schedy
//
//  应用内 UserDefaults / AppStorage 使用的键名集中定义，便于维护与查找。
//

import Foundation

// MARK: - 课表显示与全局状态

/// 课表网格与显示相关设置、当前使用的时间段名称（全局可切换）
enum ScheduleDisplayKeys {
    static let showHorizontalLines = "scheduleGridShowHorizontalLines"
    static let showVerticalLines = "scheduleGridShowVerticalLines"
    static let showWeekends = "scheduleShowWeekends"
    static let firstWeekday = "scheduleFirstWeekday"
    /// 当前使用的时间段名称（所有课程表共用）
    static let activeTimeSlotPresetName = "activeTimeSlotPresetName"
}

// MARK: - 外观与 iCloud

/// 外观模式键（跟随系统 / 浅色 / 深色）
let kAppearanceModeKey = "appearanceMode"
/// iCloud 同步开关键
let kICloudSyncEnabledKey = "iCloudSyncEnabled"
