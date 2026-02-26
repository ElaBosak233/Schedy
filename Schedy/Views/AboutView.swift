//
//  AboutView.swift
//  schedy
//
//  关于页面：应用信息与开源地址
//

import SwiftUI

struct AboutView: View {
    private let appName = "Schedy"
    private let appSubtitle = "课程表"
    private let repoURLString = "https://github.com/ElaBosak233/Schedy"

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                    Text(appName)
                        .font(.title2.bold())
                    Text(appSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)

            Section {
                Link(destination: URL(string: repoURLString)!) {
                    HStack {
                        Label("开源地址", systemImage: "link")
                        Spacer()
                        Text("GitHub")
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Label("仓库", systemImage: "chevron.left.forwardslash.chevron.right")
                    Spacer()
                    Text("ElaBosak233/Schedy")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } header: {
                Text("开源")
            } footer: {
                Text("Schedy 为开源项目，欢迎在 GitHub 上 star 与参与贡献。")
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
