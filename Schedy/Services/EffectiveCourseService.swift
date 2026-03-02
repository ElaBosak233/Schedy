//
//  EffectiveCourseService.swift
//  schedy
//
//  按「某周某日」计算有效课次（含调课：排除被调出、包含被调入），供「今天」页、小组件等复用。
//

import Foundation
import SwiftData

/// 某周某日的一次有效课：同一门课可能因调课在不同节次出现，用 periodStart/periodEnd 表示本次显示的节次范围
struct EffectiveCourseOccurrence: Identifiable {
    let course: Course
    /// 本次显示的起始节（1 起算）
    let periodStart: Int
    /// 本次显示的结束节（含）
    let periodEnd: Int

    var id: String {
        "\(course.persistentModelID)_\(periodStart)_\(periodEnd)"
    }
}

enum EffectiveCourseService {
    /// 给定某张课表的课程列表（需已加载 reschedules），计算指定周、指定星期的有效课次。
    /// - 正常排课：本周该日有课且未被调走 → 使用课程原 periodIndex / effectivePeriodEnd
    /// - 调课调入：被调到「本周该日」的课 → 使用调课记录的 newPeriodStart / newPeriodEnd
    static func effectiveCourseOccurrences(
        courses: [Course],
        week: Int,
        dayOfWeek: Int
    ) -> [EffectiveCourseOccurrence] {
        var result: [EffectiveCourseOccurrence] = []

        // 1. 正常排课：本周该日有课且未被调走
        for c in courses where c.dayOfWeek == dayOfWeek && c.appliesToWeek(week) {
            if c.reschedule(forWeek: week) == nil {
                result.append(EffectiveCourseOccurrence(
                    course: c,
                    periodStart: c.periodIndex,
                    periodEnd: c.effectivePeriodEnd
                ))
            }
        }

        // 2. 调课调入：被调到「本周该日」的课
        for c in courses {
            for r in c.reschedules where r.effectiveNewWeek == week && r.newDayOfWeek == dayOfWeek {
                result.append(EffectiveCourseOccurrence(
                    course: c,
                    periodStart: r.newPeriodStart,
                    periodEnd: r.newPeriodEnd
                ))
            }
        }

        result.sort { $0.periodStart < $1.periodStart }
        return result
    }
}
