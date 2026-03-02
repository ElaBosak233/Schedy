//
//  CourseReschedule.swift
//  Schedy
//
//  单次调课记录
//

import Foundation
import SwiftData

/// 一条调课记录：与某门课程绑定，记录「从哪周哪时」调至「哪周哪时」，不修改课程本身，便于溯源与还原。
@Model
final class CourseReschedule {
    /// 绑定的课程（被调课的那门课）
    var course: Course?
    /// 所属课程表（与 course.schedule 一致，便于按课程表查询所有调课）
    var schedule: Schedule?

    /// 来源周次：被调走的是第几周的那一次课
    var week: Int = 1
    /// 原时间：来源周的星期几（1 = 周一 … 7 = 周日），用于溯源与还原展示
    var originalDayOfWeek: Int = 1
    /// 原时间：起始节、结束节（1 起算），用于溯源与还原展示
    var originalPeriodStart: Int = 1
    var originalPeriodEnd: Int = 1

    /// 目标周次：调至第几周
    var newWeek: Int = 1
    /// 调至周几（1 = 周一 … 7 = 周日）
    var newDayOfWeek: Int = 1
    /// 调至起始节、结束节（1 起算）
    var newPeriodStart: Int = 1
    var newPeriodEnd: Int = 1

    /// 兼容旧数据：若 newWeek 为 0 视为与 week 相同（当周内调课）
    var effectiveNewWeek: Int { newWeek > 0 ? newWeek : week }

    /// 兼容旧数据：无原始时间时用课程的当前时间描述
    var hasOriginalSlot: Bool { originalDayOfWeek >= 1 && originalDayOfWeek <= 7 && originalPeriodStart > 0 }

    init(
        course: Course? = nil,
        schedule: Schedule? = nil,
        week: Int,
        originalDayOfWeek: Int,
        originalPeriodStart: Int,
        originalPeriodEnd: Int,
        newWeek: Int,
        newDayOfWeek: Int,
        newPeriodStart: Int,
        newPeriodEnd: Int
    ) {
        self.course = course
        self.schedule = schedule
        self.week = week
        self.originalDayOfWeek = originalDayOfWeek
        self.originalPeriodStart = originalPeriodStart
        self.originalPeriodEnd = originalPeriodEnd
        self.newWeek = newWeek
        self.newDayOfWeek = newDayOfWeek
        self.newPeriodStart = newPeriodStart
        self.newPeriodEnd = newPeriodEnd
    }

    /// 调课后占几节
    var periodSpan: Int { max(1, newPeriodEnd - newPeriodStart + 1) }
}
