import SwiftUI

/// 页面与导航栏共用语义底色，课表网格使用独立的动态颜色资源。
enum SchedyAppearance {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let scheduleBackground = Color("ScheduleBackground")
}

private struct SchedyPageStyle: ViewModifier {
    let navigationBackground: Visibility

    func body(content: Content) -> some View {
        content
            .background(SchedyAppearance.background, ignoresSafeAreaEdges: [.horizontal, .bottom])
            // 大标题列表使用 automatic，保留系统的标题展开与折叠行为。
            .toolbarBackground(SchedyAppearance.background, for: .navigationBar)
            .toolbarBackground(navigationBackground, for: .navigationBar)
    }
}

extension View {
    /// 应用于 NavigationStack 内的页面根内容，供列表、表单和自定义页面共用。
    func schedyPageStyle(navigationBackground: Visibility = .visible) -> some View {
        modifier(SchedyPageStyle(navigationBackground: navigationBackground))
    }
}
