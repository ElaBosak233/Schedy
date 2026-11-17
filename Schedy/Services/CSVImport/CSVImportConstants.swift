//
//  CSVImportConstants.swift
//  Schedy
//
//  CSV 导入相关常量：表头与列含义、示例模板、供用户复制给 LLM 的格式说明 Prompt。
//

import Foundation

/// CSV 导入使用的模板与说明文案
enum CSVImportConstants {
    /// CSV 模板内容（UTF-8，可用 Excel 打开）
    static let templateContent: String = String(
        localized: "import.csv.template.content",
        defaultValue: """
        课程名,教师,地点,学分,周次,单双周,星期,起始节,结束节
        Calculus,Dr. Smith,A101,4.0,1-16,all,1,1,2
        English,Dr. Lee,B201,2.0,1-16,all,3,3,4
        Programming,Dr. Wang,C301,3.0,1-8,odd,5,5,
        """
    )

    /// 用于复制到剪贴板的 LLM Prompt，用户可粘贴到 ChatGPT/Claude 等，让 LLM 根据课表生成 CSV
    static let llmPrompt: String = String(
        localized: "import.csv.prompt.content",
        defaultValue: """
        Generate a CSV file from the timetable information I provide, for import into Schedy: Timetable.

        CSV format:
        - Keep this exact header (the Chinese column names are required by the import format):
          课程名,教师,地点,学分,周次,单双周,星期,起始节,结束节
        - Columns, in order:
          1. Course name: required; preserve the original name.
          2. Teacher: optional.
          3. Location: optional.
          4. Credits: optional number, e.g. 4.0. Use a decimal point.
          5. Weeks: optional, e.g. 1-16. For multiple ranges, quote the cell: "1-1,5-8". Default: 1-1.
          6. Week pattern: all, odd, or even. Default: all.
          7. Weekday: required, 1=Monday through 7=Sunday.
          8. Start period: required, starting from 1.
          9. End period: optional; leave empty for a single period.

        Examples:
        Calculus,Dr. Smith,A101,4.0,1-16,all,1,1,2
        English,Dr. Lee,,2.0,1-16,all,3,3,

        Output only CSV, with the exact header above. Quote fields containing commas, quotes, or line breaks; double any quotes inside a quoted field.

        My timetable information:


        """
    )
}
