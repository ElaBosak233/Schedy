//
//  SchedyWidgetIntent.swift
//  SchedyWidget
//
//  小组件配置 Intent：用户可选择要显示的课表（或「跟随 App 当前选中」），选项来自 App Group 的课表列表。
//

import AppIntents
import WidgetKit

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
struct SchedyWidgetConfigIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("widget.title", defaultValue: "Today's Classes")
    static var description = IntentDescription(LocalizedStringResource("widget.configuration.description", defaultValue: "Choose a timetable for this widget. Its assigned time preset will be used."))

    @Parameter(title: LocalizedStringResource("widget.configuration.schedule.title", defaultValue: "Timetable"), optionsProvider: ScheduleOptionsProvider())
    var scheduleName: String?

    init() {
        self.scheduleName = kWidgetScheduleOptionFollowApp
    }

    init(scheduleName: String?) {
        self.scheduleName = scheduleName ?? kWidgetScheduleOptionFollowApp
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
extension SchedyWidgetConfigIntent {
    struct ScheduleOptionsProvider: DynamicOptionsProvider {
        func results() async throws -> IntentItemCollection<String> {
            let suite = UserDefaults(suiteName: kWidgetAppGroupSuiteName)
            let list = suite?.stringArray(forKey: WidgetDataKeys.scheduleNamesList) ?? []
            let items = [IntentItem(kWidgetScheduleOptionFollowApp, title: LocalizedStringResource("widget.configuration.follow_app", defaultValue: "Follow App Selection"))]
                + list.map { IntentItem($0, title: LocalizedStringResource("widget.configuration.schedule_name", defaultValue: "\($0)")) }
            return IntentItemCollection(sections: [IntentItemSection(items: items)])
        }
    }
}
