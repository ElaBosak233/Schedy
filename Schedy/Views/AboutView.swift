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
                    Label("仓库", systemImage: "chevron.left.forwardslash.chevron.right")
                    Spacer()
                    Text("ElaBosak233/Schedy")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
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
            } header: {
                Text("开源")
            } footer: {
                Text("Schedy 为开源项目，欢迎在 GitHub 上 star 与参与贡献。")
            }

            // 协议
            Section {
                HStack {
                    Label("开源协议", systemImage: "doc.text")
                    Spacer()
                    Text("Schedy 协议")
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: licenseURLString)!) {
                    HStack {
                        Label("查看完整协议", systemImage: "safari")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("协议")
            } footer: {
                Text("本软件采用 Schedy 开源协议。可自由使用、修改与基于本代码开发衍生产品；须保留原作者署名，衍生产品须开源；以应用形式分发须通过 App Store。详见仓库 LICENSE。")
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
