//
//  AcademicAffairsInjectedCourseParser.swift
//  Schedy
//
//  WebView 注入式教务课表抓取：provider 在网页上下文里把 DOM/API 数据压成
//  name~day~period~room~weeks~teacher，再由 Swift 转成 ParsedCourseItem。
//

import Foundation

enum AcademicAffairsInjectedCourseParser {
    static func providerScript(for type: AcademicAffairsType) -> String {
        do {
            let helper = try loadScript(named: "dom-matrix-helper")
            let provider = try loadScript(named: type.providerScriptName)
            return helper + "\n\n" + provider
        } catch {
            return "document.title = 'KEBIAO_ERR:' + \(javascriptStringLiteral(error.localizedDescription));"
        }
    }

    static func parseCompact(_ compact: String, type: AcademicAffairsType) -> [ParsedCourseItem] {
        var text = compact
        if text.hasPrefix("JSON|") { return [] }
        if text.hasPrefix("HTML|") { text.removeFirst("HTML|".count) }

        return text
            .split(separator: "|", omittingEmptySubsequences: true)
            .compactMap { parseItem(String($0)) }
    }

    private static func parseItem(_ item: String) -> ParsedCourseItem? {
        let parts = item.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }

        let name = clean(parts[safe: 0] ?? "")
        let day = Int(clean(parts[safe: 1] ?? "")) ?? 0
        guard !name.isEmpty, (1...7).contains(day) else { return nil }

        let period = parsePeriodRange(parts[safe: 2] ?? "") ?? (1, 2)
        let location = clean(parts[safe: 3] ?? "")
        let weeksText = clean(parts[safe: 4] ?? "")
        let teacher = clean(parts[safe: 5] ?? "")
        let (weekRanges, parity) = parseWeeks(weeksText)

        return ParsedCourseItem(
            name: name,
            teacher: teacher.isEmpty ? nil : teacher,
            location: location.isEmpty ? nil : location,
            credits: nil,
            weekRangesString: weekRanges,
            weekParity: parity,
            dayOfWeek: day,
            periodIndex: period.0,
            periodEnd: period.1
        )
    }

    private static func parsePeriodRange(_ raw: String) -> (Int, Int)? {
        let numbers = integers(in: raw)
        guard let first = numbers.first else { return nil }
        return (first, numbers.dropFirst().first ?? first)
    }

    private static func parseWeeks(_ raw: String) -> (String, Course.WeekParity) {
        let parity: Course.WeekParity
        if raw.contains("单周") {
            parity = .odd
        } else if raw.contains("双周") {
            parity = .even
        } else {
            parity = .all
        }

        let ranges = integerRanges(in: removingBracketedText(from: raw))
        guard !ranges.isEmpty else { return ("", parity) }
        return (ranges.map { "\($0.0)-\($0.1)" }.joined(separator: ","), parity)
    }

    private static func removingBracketedText(from text: String) -> String {
        var result = ""
        var depth = 0
        for char in text {
            if char == "[" || char == "【" {
                depth += 1
                continue
            }
            if char == "]" || char == "】" {
                depth = max(0, depth - 1)
                continue
            }
            if depth == 0 { result.append(char) }
        }
        return result
    }

    private static func integerRanges(in text: String) -> [(Int, Int)] {
        var ranges: [(Int, Int)] = []
        var numbers: [Int] = []
        var current = ""

        func flushNumber() {
            guard !current.isEmpty else { return }
            if let value = Int(current) { numbers.append(value) }
            current = ""
        }

        for char in text {
            if char.isNumber {
                current.append(char)
            } else {
                flushNumber()
                if char == "-" || char == "－" || char == "~" || char == "～" {
                    continue
                }
                appendRanges(from: &numbers, to: &ranges)
            }
        }
        flushNumber()
        appendRanges(from: &numbers, to: &ranges)

        return ranges
    }

    private static func appendRanges(from numbers: inout [Int], to ranges: inout [(Int, Int)]) {
        guard !numbers.isEmpty else { return }
        if numbers.count >= 2 {
            let start = numbers[0]
            let end = numbers[1]
            if start <= end { ranges.append((start, end)) }
        } else if let only = numbers.first {
            ranges.append((only, only))
        }
        numbers.removeAll()
    }

    private static func integers(in text: String) -> [Int] {
        var result: [Int] = []
        var current = ""
        for char in text {
            if char.isNumber {
                current.append(char)
            } else if !current.isEmpty {
                if let value = Int(current) { result.append(value) }
                current = ""
            }
        }
        if let value = Int(current) { result.append(value) }
        return result
    }

    private static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "教师：", with: "")
            .replacingOccurrences(of: "教师:", with: "")
            .replacingOccurrences(of: "上课地点：", with: "")
            .replacingOccurrences(of: "上课地点:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func loadScript(named name: String) throws -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: "js") {
            return try String(contentsOf: url, encoding: .utf8)
        }
        if let url = findScriptInBundle(named: "\(name).js") {
            return try String(contentsOf: url, encoding: .utf8)
        }
        throw ScriptLoadingError.missingResource("\(name).js")
    }

    private static func findScriptInBundle(named fileName: String) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: resourceURL,
                includingPropertiesForKeys: nil
              ) else {
            return nil
        }
        for case let url as URL in enumerator where url.lastPathComponent == fileName {
            return url
        }
        return nil
    }

    private static func javascriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else {
            return "''"
        }
        return String(json.dropFirst().dropLast())
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension AcademicAffairsType {
    var providerScriptName: String {
        switch self {
        case .zhengFang: return "zheng-fang"
        case .qiangZhi: return "qiang-zhi"
        case .chaoXing: return "chao-xing"
        case .kingo: return "kingo"
        case .urp: return "urp"
        case .south: return "south"
        case .wisedu: return "wisedu"
        }
    }
}

private enum ScriptLoadingError: LocalizedError {
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let path):
            return "未找到注入脚本资源：\(path)"
        }
    }
}
