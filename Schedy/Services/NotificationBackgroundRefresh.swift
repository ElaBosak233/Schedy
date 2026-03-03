//
//  NotificationBackgroundRefresh.swift
//  Schedy
//
//  后台刷新通知队列：用户长时间不打开 app 时，由系统在合适时机拉起 BGAppRefreshTask，
//  重算课程提醒并排入本地通知；任务内使用仅本地存储的 ModelContainer，避免后台 iCloud。
//

import Foundation
import SwiftData
import BackgroundTasks

/// BGTaskScheduler 使用的任务标识，需与 Info.plist 中 BGTaskSchedulerPermittedIdentifiers 一致
let kNotificationRefreshTaskIdentifier = "dev.e23.schedy.refreshNotifications"

/// 注册后台刷新任务（应在 app 启动时调用一次）
func registerNotificationRefreshTask() {
    BGTaskScheduler.shared.register(
        forTaskWithIdentifier: kNotificationRefreshTaskIdentifier,
        using: nil
    ) { task in
        handleNotificationRefreshTask(task as! BGAppRefreshTask)
    }
}

/// 安排下一次后台刷新的时间（建议在每次刷新通知队列后调用）
func scheduleNextNotificationRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: kNotificationRefreshTaskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600) // 最早 12 小时后
    do {
        try BGTaskScheduler.shared.submit(request)
    } catch {
        // 系统可能拒绝（如用户关闭后台刷新），忽略
    }
}

private func handleNotificationRefreshTask(_ task: BGAppRefreshTask) {
    Task { @MainActor in
        defer { task.setTaskCompleted(success: true) }
        guard let container = try? createModelContainerForBackground() else { return }
        let context = ModelContext(container)
        scheduleCourseReminders(modelContext: context)
        scheduleNextNotificationRefresh()
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
