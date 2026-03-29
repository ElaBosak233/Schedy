//
//  BackgroundRefreshService.swift
//  Schedy
//
//  后台刷新统一入口：由系统在合适时机拉起 BGAppRefreshTask，
//  重排课程提醒并同步 Widget 数据；任务内使用仅本地存储的 ModelContainer，避免后台 iCloud。
//

import Foundation
import SwiftData
import BackgroundTasks

/// 新版后台刷新任务标识，需与 Info.plist 的 BGTaskSchedulerPermittedIdentifiers 一致
let kBackgroundRefreshTaskIdentifier = "dev.e23.schedy.backgroundRefresh"
private var hasRegisteredBackgroundRefreshTasks = false
private var lastBackgroundRefreshScheduleAt: Date?
private let kBackgroundRefreshScheduleDebounceSeconds: TimeInterval = 300

/// 注册后台刷新任务（应在 app 启动时调用一次）
func registerBackgroundRefreshTasks() {
    guard !hasRegisteredBackgroundRefreshTasks else { return }
    registerBackgroundRefreshTask(identifier: kBackgroundRefreshTaskIdentifier)
    hasRegisteredBackgroundRefreshTasks = true
}

private func registerBackgroundRefreshTask(identifier: String) {
    BGTaskScheduler.shared.register(
        forTaskWithIdentifier: identifier,
        using: nil
    ) { task in
        guard let refreshTask = task as? BGAppRefreshTask else {
            task.setTaskCompleted(success: false)
            return
        }
        handleBackgroundRefreshTask(refreshTask)
    }
}

/// 安排下一次后台刷新（建议在启动与每次后台任务执行后调用）
func scheduleNextBackgroundRefresh() {
    let now = Date()
    if let last = lastBackgroundRefreshScheduleAt,
       now.timeIntervalSince(last) < kBackgroundRefreshScheduleDebounceSeconds {
        return
    }

    _ = submitBackgroundRefreshRequest(identifier: kBackgroundRefreshTaskIdentifier)
}

@discardableResult
private func submitBackgroundRefreshRequest(identifier: String) -> Bool {
    let request = BGAppRefreshTaskRequest(identifier: identifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600) // 最早 12 小时后
    do {
        try BGTaskScheduler.shared.submit(request)
        lastBackgroundRefreshScheduleAt = Date()
        return true
    } catch {
        // 系统可能拒绝（如用户关闭后台刷新），忽略
        return false
    }
}

private func handleBackgroundRefreshTask(_ task: BGAppRefreshTask) {
    Task { @MainActor in
        var success = false
        defer { task.setTaskCompleted(success: success) }

        guard let container = try? createModelContainerForBackground() else {
            scheduleNextBackgroundRefresh()
            return
        }

        let context = ModelContext(container)
        scheduleCourseReminders(modelContext: context)
        let activeScheduleName = UserDefaults.standard.string(forKey: ScheduleDisplayKeys.activeScheduleName) ?? "我的课程表"
        refreshWidgetData(modelContext: context, activeScheduleName: activeScheduleName)
        scheduleNextBackgroundRefresh()
        success = true
    }
}

/// 供后台任务使用的 ModelContainer（仅本地存储，不启用 iCloud，避免后台同步问题）
private func createModelContainerForBackground() throws -> ModelContainer {
    let schema = Schema([
        Schedule.self,
        Course.self,
        CourseReschedule.self,
        TimeSlotPreset.self,
        TimeSlotItem.self,
    ])
    let config = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
}
