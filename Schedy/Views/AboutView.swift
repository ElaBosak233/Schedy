//
//  AboutView.swift
//  schedy
//
//  关于页面：应用信息、开源地址与协议
//

import SwiftUI

struct AboutView: View {
    private let appName = "Schedy"
    private let appSubtitle = "课程表"
    private let repoURLString = "https://github.com/ElaBosak233/Schedy"
    private let gpl3URLString = "https://www.gnu.org/licenses/gpl-3.0.html"

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

            // 协议 GPL-3
            Section {
                HStack {
                    Label("开源协议", systemImage: "doc.text")
                    Spacer()
                    Text("GPL-3.0")
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: gpl3URLString)!) {
                    HStack {
                        Label("GNU 通用公共许可证 v3.0", systemImage: "safari")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("协议")
            } footer: {
                Text("本软件采用 GNU General Public License v3.0 (GPL-3.0) 开源。您可自由使用、修改与分发，分发时须保留相同协议并公开源代码。")
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
