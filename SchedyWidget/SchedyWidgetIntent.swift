//
//  SchedyWidgetIntent.swift
//  SchedyWidget
//
//  小组件配置：选择显示哪张课表，默认「跟随 App 当前选中」。
//

import AppIntents
import WidgetKit

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
struct SchedyWidgetConfigIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "今日课程"
    static var description = IntentDescription("选择要在小组件中显示的课表")

    @Parameter(title: "课表", optionsProvider: ScheduleOptionsProvider())
    var scheduleName: String?

    @Parameter(title: "时间段", optionsProvider: PresetOptionsProvider())
    var presetName: String?

    init() {
        self.scheduleName = kWidgetScheduleOptionFollowApp
        self.presetName = kWidgetPresetOptionFollowApp
    }

    init(scheduleName: String?, presetName: String?) {
        self.scheduleName = scheduleName ?? kWidgetScheduleOptionFollowApp
        self.presetName = presetName ?? kWidgetPresetOptionFollowApp
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
extension SchedyWidgetConfigIntent {
    struct ScheduleOptionsProvider: DynamicOptionsProvider {
        func results() async throws -> [String] {
            let suite = UserDefaults(suiteName: kWidgetAppGroupSuiteName)
            let list = suite?.stringArray(forKey: WidgetDataKeys.scheduleNamesList) ?? []
            return [kWidgetScheduleOptionFollowApp] + list
        }
    }

    struct PresetOptionsProvider: DynamicOptionsProvider {
        func results() async throws -> [String] {
            let suite = UserDefaults(suiteName: kWidgetAppGroupSuiteName)
            let list = suite?.stringArray(forKey: WidgetDataKeys.presetNamesList) ?? []
            return [kWidgetPresetOptionFollowApp] + list
        }
    }
}
