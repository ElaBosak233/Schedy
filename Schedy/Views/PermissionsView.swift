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
        guard let status = notificationStatus else { return String(localized: "permissions.status.checking", defaultValue: "Checking…") }
        switch status {
        case .authorized: return String(localized: "permissions.status.on", defaultValue: "On")
        case .denied: return String(localized: "permissions.status.off", defaultValue: "Off")
        case .notDetermined: return String(localized: "permissions.notifications.status.not_set", defaultValue: "Not Set")
        case .provisional: return String(localized: "permissions.notifications.status.provisional", defaultValue: "Provisional (Summary)")
        case .ephemeral: return String(localized: "permissions.notifications.status.ephemeral", defaultValue: "Ephemeral")
        @unknown default: return String(localized: "common.status.unknown", defaultValue: "Unknown")
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
                    Label(String(localized: "permissions.notifications.title", defaultValue: "Notifications"), systemImage: "bell.badge")
                    Spacer()
                    Text(notificationStatusText)
                        .foregroundStyle(notificationStatusColor)
                        .fontWeight(.medium)
                }
                .opacity(isLoading ? 0.7 : 1)

                HStack {
                    Label(String(localized: "permissions.network.title", defaultValue: "Network"), systemImage: "wifi")
                    Spacer()
                    Text(String(localized: "permissions.network.status.system", defaultValue: "Uses System Connection"))
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                }

                Button {
                    openSystemSettings()
                } label: {
                    HStack {
                        Label(String(localized: "permissions.action.open_settings", defaultValue: "Open System Settings"), systemImage: "gear")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(String(localized: "permissions.summary.title", defaultValue: "Schedy Permissions"))
            } footer: {
                Text(String(localized: "permissions.description", defaultValue: "Notifications remind you 15 minutes before class. Network access loads school systems and project links using your device's connection. Tap Open System Settings to change notification permissions."))
            }
        }
        .schedyPageStyle()
        .navigationTitle(String(localized: "navigation.permissions.title", defaultValue: "Permissions"))
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
