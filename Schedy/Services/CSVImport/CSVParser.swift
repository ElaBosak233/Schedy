//
//  CSVParser.swift
//  Schedy
//
//  从 CSV 字符串解析为 [ParsedCourseItem]；列定义与错误类型见 CSVImportConstants。
//

import Foundation

/// CSV 解析过程中的错误类型，用于导入失败时提示用户
enum CSVParserError: Error, LocalizedError {
    case emptyFile
    case invalidHeader
    case missingColumn(String)
    case noValidCourses

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "CSV 文件为空"
        case .invalidHeader: return "表头解析失败"
        case .missingColumn(let col): return "缺少必填列：\(col)"
        case .noValidCourses: return "未能解析到任何有效课程，请检查 CSV 格式"
        }
    }
}

enum CSVParser {
    /// CSV 表头（必须包含）
    static let requiredColumns = ["课程名", "星期", "起始节"]

    /// 从 CSV 字符串解析为 [ParsedCourseItem]
    /// - Parameter csvString: CSV 内容（支持 UTF-8，建议带 BOM）
    /// - Returns: 解析结果，失败时返回 nil 并附带错误信息
    static func parse(csvString: String) -> Result<[ParsedCourseItem], CSVParserError> {
        let lines = csvString.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return .failure(.emptyFile)
        }

        let headerRow = parseCSVLine(lines[0])
        guard !headerRow.isEmpty else {
            return .failure(.invalidHeader)
        }

        let columnMap = buildColumnMap(headerRow)
        for col in requiredColumns {
            if columnMap[col] == nil {
                return .failure(.missingColumn(col))
            }
        }

        var result: [ParsedCourseItem] = []
        for (idx, line) in lines.dropFirst().enumerated() {
            let row = parseCSVLine(line)
            if row.isEmpty { continue }

            guard let item = parseRow(row, columnMap: columnMap, lineNumber: idx + 2) else {
                continue
            }
            result.append(item)
        }

        if result.isEmpty {
            return .failure(.noValidCourses)
        }
        return .success(result)
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex

        while i < line.endIndex {
            let c = line[i]
            if c == "\"" {
                if inQuotes {
                    let next = line.index(after: i)
                    if next < line.endIndex, line[next] == "\"" {
                        current.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if (c == "," && !inQuotes) || c == "\n" || c == "\r" {
                if c == "," {
                    result.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
            } else {
                if c != "\r" { current.append(c) }
            }
            i = line.index(after: i)
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    private static func buildColumnMap(_ header: [String]) -> [String: Int] {
        var map: [String: Int] = [:]
        for (idx, col) in header.enumerated() {
            let key = col.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, map[key] == nil {
                map[key] = idx
            }
        }
        return map
    }

    private static func value(_ row: [String], column: String, map: [String: Int]) -> String? {
        guard let idx = map[column], idx < row.count else { return nil }
        let v = row[idx].trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    private static func parseRow(_ row: [String], columnMap: [String: Int], lineNumber: Int) -> ParsedCourseItem? {
        guard let name = value(row, column: "课程名", map: columnMap), !name.isEmpty,
              let dayStr = value(row, column: "星期", map: columnMap),
              let dayOfWeek = parseDayOfWeek(dayStr),
              let periodStr = value(row, column: "起始节", map: columnMap),
              let periodIndex = Int(periodStr.trimmingCharacters(in: .whitespaces)), periodIndex >= 1
        else { return nil }

        let teacher = value(row, column: "教师", map: columnMap) ?? ""
        let location = value(row, column: "地点", map: columnMap) ?? ""
        let credits: Double? = {
            guard let s = value(row, column: "学分", map: columnMap), let d = Double(s), d >= 0 else { return nil }
            return d
        }()
        let weekRangesString = value(row, column: "周次", map: columnMap) ?? "1-1"
        let weekParity = parseWeekParity(value(row, column: "单双周", map: columnMap))
        var periodEnd = periodIndex
        if let endStr = value(row, column: "结束节", map: columnMap), let end = Int(endStr), end >= periodIndex {
            periodEnd = end
        }

        return ParsedCourseItem(
            name: name,
            teacher: teacher,
            location: location,
            credits: credits,
            weekRangesString: weekRangesString,
            weekParity: weekParity,
            dayOfWeek: dayOfWeek,
            periodIndex: periodIndex,
            periodEnd: periodEnd
        )
    }

    private static func parseDayOfWeek(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if let n = Int(trimmed), n >= 1, n <= 7 { return n }
        let map: [String: Int] = [
            "星期一": 1, "周一": 1, "星期二": 2, "周二": 2, "星期三": 3, "周三": 3,
            "星期四": 4, "周四": 4, "星期五": 5, "周五": 5,
            "星期六": 6, "周六": 6, "星期日": 7, "周日": 7,
            "monday": 1, "tuesday": 2, "wednesday": 3, "thursday": 4,
            "friday": 5, "saturday": 6, "sunday": 7,
            "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6, "sun": 7
        ]
        return map[trimmed.lowercased()]
    }

    private static func parseWeekParity(_ s: String?) -> Course.WeekParity {
        guard let str = s?.trimmingCharacters(in: .whitespaces).lowercased(), !str.isEmpty else { return .all }
        if str == "单周" || str == "1" || str == "odd" { return .odd }
        if str == "双周" || str == "2" || str == "even" { return .even }
        return .all
    }
}
