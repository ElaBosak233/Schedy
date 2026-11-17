import Foundation

/// Run with scripts/check-localization.sh after building the app for Simulator.
@main
struct LocalizationChecks {
    static func main() throws {
        let appPath = CommandLine.arguments[1]
        for (language, expectedName) in [("en", "Schedy: Timetable"), ("zh-Hans", "Schedy 课程表")] {
            let locale = Locale(identifier: language)
            let bundle = Bundle(path: appPath + "/\(language).lproj")!
            let infoData = try Data(contentsOf: URL(fileURLWithPath: appPath + "/\(language).lproj/InfoPlist.strings"))
            let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as! [String: String]
            precondition(info["CFBundleDisplayName"] == expectedName)
            let one = String(localized: "import.success.course_count", defaultValue: "Imported \(1) courses.", bundle: bundle, locale: locale)
            let many = String(localized: "import.success.course_count", defaultValue: "Imported \(2) courses.", bundle: bundle, locale: locale)
            if language == "en" {
                precondition(one == "Imported 1 course.", one)
                precondition(many == "Imported 2 courses.", many)
            } else {
                precondition(one == "已导入 1 门课程。", one)
                precondition(many == "已导入 2 门课程。", many)
            }
            let prompt = bundle.localizedString(forKey: "import.csv.prompt.content", value: nil, table: nil)
            precondition(prompt.contains("课程名,教师,地点,学分,周次,单双周,星期,起始节,结束节"))
            precondition(prompt.hasPrefix(language == "en" ? "Generate a CSV" : "请根据我提供"))
            let localizedTemplate = bundle.localizedString(forKey: "import.csv.template.content", value: nil, table: nil)
            let rows = try CSVParser.parse(csvString: localizedTemplate).get()
            precondition(rows.count == 3 && rows[2].weekParity == .odd)
            precondition(rows[0].name == (language == "en" ? "Calculus" : "高等数学"))
            let slotCount = String(localized: "preset.periods.count", defaultValue: "\(1) time slots", bundle: bundle, locale: locale)
            precondition(slotCount == (language == "en" ? "1 time slot" : "1 个时间段"))
            let widgetBundle = Bundle(path: appPath + "/PlugIns/SchedyWidgetExtension.appex/\(language).lproj")!
            precondition(widgetBundle.localizedString(forKey: "widget.title", value: nil, table: nil)
                         == (language == "en" ? "Today's Classes" : "今日课程"))
            precondition(widgetBundle.localizedString(forKey: "widget.configuration.follow_app", value: nil, table: nil)
                         == (language == "en" ? "Follow App Selection" : "跟随 App 当前选中"))
            // English and Chinese place the course name and week in different orders.
            let courseName = "用户课程"
            let week = 3
            let weekday = "Mon"
            let start = 2
            let end = 4
            let reschedule = String(
                localized: "reschedule.description",
                defaultValue: "Move “\(courseName)” from week \(week) (\(weekday), periods \(start)–\(end)) to the time below, keeping the same number of periods.",
                bundle: bundle,
                locale: locale
            )
            let expected = language == "en"
                ? "Move “用户课程” from week 3 (Mon, periods 2–4) to the time below, keeping the same number of periods."
                : "将 第 3 周 的「用户课程」（Mon 第 2–4 节）调至下方选择的时间，课时数保持不变。"
            precondition(reschedule == expected, reschedule)

            let notificationFormat = bundle.localizedString(forKey: "notification.course.body", value: nil, table: nil)
            let notification = String(format: notificationFormat, "用户课表", courseName)
            precondition(notification == (language == "en"
                ? "“用户课程” in “用户课表” is starting soon."
                : "「用户课表」用户课程 快要开始啦"), notification)

            // A user name matching a translation key must still be shown literally.
            let userName = "widget.title"
            let optionTitle = String(localized: "widget.configuration.schedule_name", defaultValue: "\(userName)",
                                     bundle: widgetBundle, locale: locale)
            precondition(optionTitle == userName, optionTitle)
        }

        // Export must remain importable after the display names of week patterns are translated.
        for parity in Course.WeekParity.allCases {
            let schedule = Schedule(name: "用户课表", semesterStartDate: Date())
            let course = Course(name: "Course, with \"quotes\"", teacher: "王老师", location: "A101",
                                weekRangesString: "1-1,5-8", weekParity: parity,
                                dayOfWeek: 3, periodIndex: 2, periodEnd: 4, schedule: schedule)
            schedule.courses = [course]
            let parsed = try CSVParser.parse(csvString: CSVExport.csvString(from: schedule)).get()
            precondition(parsed.count == 1)
            precondition(parsed[0].name == course.name && parsed[0].teacher == course.teacher)
            precondition(parsed[0].weekParity == parity && parsed[0].weekRangesString == "1-1,5-8")
            precondition(parsed[0].dayOfWeek == 3 && parsed[0].periodIndex == 2 && parsed[0].periodEnd == 4)
        }
        let template = try CSVParser.parse(csvString: CSVImportConstants.templateContent).get()
        precondition(template.count == 3 && template[2].weekParity == .odd)

        // Existing widget choices remain valid, and dates are rendered from a timestamp.
        let suiteName = "dev.e23.schedy.localization-checks.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        suite.set(["用户课表"], forKey: WidgetDataKeys.scheduleNamesList)
        suite.set("用户课表", forKey: WidgetDataKeys.defaultScheduleName)
        precondition(WidgetEntry.resolveScheduleNameToShow(suite: suite, configuredName: "跟随 App 当前选中") == "用户课表")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        suite.set([WidgetDataKeys.scheduleName: "用户课表", WidgetDataKeys.displayDate: String(date.timeIntervalSince1970),
                   WidgetDataKeys.date: "旧日期", WidgetDataKeys.weekday: "旧星期"],
                  forKey: "\(WidgetDataKeys.entryPrefix)_用户课表\(WidgetDataKeys.entrySeparator)Winter")
        let entry = WidgetEntry.load(from: suite, scheduleName: "用户课表", presetName: "Winter")
        precondition(entry.scheduleName == "用户课表")
        precondition(entry.dateString == date.formatted(.dateTime.month(.abbreviated).day()))
        precondition(entry.weekdayString == date.formatted(.dateTime.weekday(.abbreviated)))
        print("Passed: bilingual names, plurals, CSV round trips, and legacy widget selection/date formatting.")
    }
}
