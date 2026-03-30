//
//  PermissionsView.swift
//  Schedy
//
//  权限页：显示通知权限状态（已开启/已关闭等），并提供跳转系统「设置」的按钮。
//

import SwiftUI
import UserNotifications

struct PermissionsView: View {
    @Environment(\.openURL) private var openURL
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var isLoading = true

    private var notificationStatusText: String {
        guard let status = notificationStatus else { return "检查中…" }
        switch status {
        case .authorized: return "已开启"
        case .denied: return "已关闭"
        case .notDetermined: return "未选择"
        case .provisional: return "临时（摘要）"
        case .ephemeral: return "临时"
        @unknown default: return "未知"
        }
    }

    private var notificationStatusColor: Color {
        guard let status = notificationStatus else { return .secondary }
        switch status {
        case .authorized: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        default: return .secondary
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Label("通知", systemImage: "bell.badge")
                    Spacer()
                    Text(notificationStatusText)
                        .foregroundStyle(notificationStatusColor)
                        .fontWeight(.medium)
                }
                .opacity(isLoading ? 0.7 : 1)

                HStack {
                    Label("网络", systemImage: "wifi")
                    Spacer()
                    Text("随系统网络")
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                }

                Button {
                    openSystemSettings()
                } label: {
                    HStack {
                        Label("在系统设置中修改", systemImage: "gear")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Schedy 当前权限")
            } footer: {
                Text("通知权限用于在课程开始前 15 分钟提醒你；网络用于加载教务系统、开源链接等，随系统网络状态使用。若需修改通知权限，可点击「在系统设置中修改」跳转。")
            }
        }
        .navigationTitle("权限")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchNotificationStatus()
        }
    }

    private func fetchNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationStatus = settings.authorizationStatus
            isLoading = false
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: "app-settings:") else { return }
        openURL(url)
    }
}

#Preview {
    NavigationStack {
        PermissionsView()
    }
}
