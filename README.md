# Schedy 课程表

## 设计理念

Schedy 只做一件事：在本地管理课表、看今日/本周、收上课提醒。

- **纯净**：无广告、无拍照搜题、无交友/社区。界面和逻辑都围绕「课程表」本身，不堆功能。
- **无第三方在线服务**：数据全部在设备上。课表用 SwiftData 存本地；提醒用 `UNUserNotificationCenter` 本地调度；小组件用 WidgetKit 读同一份 SwiftData。从教务导入时，由内嵌浏览器打开你填的教务地址，在「导入当前页」时仅取当前页 HTML 在本地解析（正方等格式），不向任何第三方服务器上传或请求课表数据。
- **仅支持苹果设备**：依赖 SwiftUI、SwiftData、WidgetKit、UserNotifications 等系统能力，只针对 iOS/macOS（以及配套的 Widget）开发和测试。

以上选择在代码里直接可见：无广告/统计 SDK、无网络课表 API、无账号与云同步，仅必要的 `URL` 使用是打开教务页、设置页、关于中的 GitHub/GPL 链接。
