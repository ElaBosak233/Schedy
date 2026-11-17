//
//  AboutView.swift
//  Schedy
//
//  关于页：应用名称、副标题、开源仓库与许可证链接。
//

import SwiftUI

struct AboutView: View {
    private let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Schedy"
    private let appSubtitle = String(localized: "navigation.timetable.title", defaultValue: "Timetable")
    private let repoURLString = "https://github.com/ElaBosak233/Schedy"
    private let licenseURLString = "https://github.com/ElaBosak233/Schedy/blob/main/LICENSE"

    var body: some View {
        List {
            // 头部：Logo + 名称
            Section {
                VStack(spacing: 16) {
                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(.secondary.opacity(0.2), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
                    VStack(spacing: 4) {
                        Text(appName)
                            .font(.title.bold())
                        Text(appSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)

            // 开源
            Section {
                HStack {
                    Label(String(localized: "about.repository.title", defaultValue: "Repository"), systemImage: "chevron.left.forwardslash.chevron.right")
                    Spacer()
                    Text(verbatim: "ElaBosak233/Schedy")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Link(destination: URL(string: repoURLString)!) {
                    HStack {
                        Label(String(localized: "about.repository.open_action", defaultValue: "View on GitHub"), systemImage: "link")
                        Spacer()
                        Text(verbatim: "GitHub")
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(String(localized: "about.open_source.title", defaultValue: "Open Source"))
            } footer: {
                Text(String(localized: "about.open_source.description", defaultValue: "Schedy is open source. Star the project or contribute on GitHub."))
            }

            // 协议
            Section {
                HStack {
                    Label(String(localized: "about.license.section_title", defaultValue: "Open Source License"), systemImage: "doc.text")
                    Spacer()
                    Text(String(localized: "about.license.name", defaultValue: "Schedy License"))
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: licenseURLString)!) {
                    HStack {
                        Label(String(localized: "about.license.read_action", defaultValue: "Read Full License"), systemImage: "safari")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(String(localized: "about.license.title", defaultValue: "License"))
            } footer: {
                Text(String(localized: "about.license.description", defaultValue: "This software uses the Schedy License. You may use, modify, and create derivative works from this code. Retain the original author attribution and release derivative works as open source. App distributions must use the App Store. See LICENSE in the repository for details."))
            }
        }
        .schedyPageStyle()
        .navigationTitle(String(localized: "navigation.about.title", defaultValue: "About"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
