//
//  ZhengFangHTMLParser.swift
//  schedy
//
//  正方教务个人课表 HTML 解析（表格 id=kbgrid_table_0，td.td_wrap id="星期-节次"）
//  支持解析课程名、教师、地点、周次、单双周、学分
//

import Foundation

enum ZhengFangHTMLParser: AcademicAffairsHTMLParserProtocol {
    /// 从正方教务「个人课表查询」完整 HTML 中解析出课程列表
    static func parse(html: String) -> [ParsedCourseItem] {
        var result: [ParsedCourseItem] = []
        if let tableRange = html.range(of: "id=\"kbgrid_table_0\"", options: .caseInsensitive) {
            let tableSection = String(html[tableRange.lowerBound...])
            result = parseGridTable(html: tableSection)
        }
        if result.isEmpty, let listRange = html.range(of: "id=\"kblist_table\"", options: .caseInsensitive) {
            let listSection = String(html[listRange.lowerBound...])
            result = parseListTable(html: listSection)
        }
        return result
    }

    /// 解析网格课表：td.td_wrap id="day-period"（1=周一…7=周日，节次 1 起）
    private static func parseGridTable(html: String) -> [ParsedCourseItem] {
        var list: [ParsedCourseItem] = []
        let cellPattern = #"<td[^>]*\sid="(\d+)-(\d+)"[^>]*class="[^"]*td_wrap[^"]*"[^>]*>(.*?)</td>"#
        guard let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        cellRegex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges >= 4,
                  let dayStr = ns.substring(with: m.range(at: 1)) as String?,
                  let periodStr = ns.substring(with: m.range(at: 2)) as String?,
                  let day = Int(dayStr), let period = Int(periodStr),
                  day >= 1, day <= 7, period >= 1,
                  m.range(at: 3).location != NSNotFound else { return }
            let cellContent = ns.substring(with: m.range(at: 3))
            let items = parseTimetableConBlocks(html: cellContent, defaultDay: day, defaultPeriod: period)
            list.append(contentsOf: items)
        }
        return list
    }

    /// 解析列表课表 kblist_table
    private static func parseListTable(html: String) -> [ParsedCourseItem] {
        var list: [ParsedCourseItem] = []
        let dayPattern = #"<tbody\s+id="xq_(\d+)"[^>]*>(.*?)</tbody>"#
        let rowPattern = #"<span\s+class="festival">(\d+)(?:-(\d+))?</span></td><td><div\s+class="timetable_con[^"]*">(.*?)</div></td>"#
        guard let dayRegex = try? NSRegularExpression(pattern: dayPattern, options: [.dotMatchesLineSeparators]),
              let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        dayRegex.enumerateMatches(in: html, options: [], range: NSRange(location: 0, length: ns.length)) { dayMatch, _, _ in
            guard let dm = dayMatch, dm.numberOfRanges >= 3,
                  let dayInt = Int(ns.substring(with: dm.range(at: 1))),
                  dayInt >= 1, dayInt <= 7,
                  dm.range(at: 2).location != NSNotFound else { return }
            let tbody = ns.substring(with: dm.range(at: 2))
            let tbodyNs = tbody as NSString
            rowRegex.enumerateMatches(in: tbody, options: [], range: NSRange(location: 0, length: tbodyNs.length)) { rowMatch, _, _ in
                guard let rm = rowMatch, rm.numberOfRanges >= 4,
                      let p1 = Int(tbodyNs.substring(with: rm.range(at: 1))) else { return }
                let p2 = rm.range(at: 2).location != NSNotFound ? Int(tbodyNs.substring(with: rm.range(at: 2))) : nil
                let block = rm.range(at: 3).location != NSNotFound ? tbodyNs.substring(with: rm.range(at: 3)) : ""
                let parsed = parseOneTimetableCon(html: block)
                guard !parsed.name.isEmpty else { return }
                list.append(ParsedCourseItem(
                    name: parsed.name,
                    teacher: parsed.teacher,
                    location: parsed.location,
                    credits: parsed.credits,
                    weekRangesString: parsed.weekRangesString,
                    weekParity: parsed.weekParity,
                    dayOfWeek: dayInt,
                    periodIndex: p1,
                    periodEnd: p2 ?? p1
                ))
            }
        }
        return list
    }

    /// 从一个 td 内解析多个 .timetable_con
    private static func parseTimetableConBlocks(html: String, defaultDay: Int, defaultPeriod: Int) -> [ParsedCourseItem] {
        var list: [ParsedCourseItem] = []
        let blockPattern = #"<div\s+class="timetable_con[^"]*">(.*?)</div>\s*(?=<div\s+class="timetable_con|$)"#
        guard let blockRegex = try? NSRegularExpression(pattern: blockPattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        blockRegex.enumerateMatches(in: html, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let m = match, m.numberOfRanges >= 1, m.range(at: 1).location != NSNotFound else { return }
            let block = ns.substring(with: m.range(at: 1))
            let parsed = parseOneTimetableCon(html: block)
            var periodStart = defaultPeriod
            var periodEnd = defaultPeriod
            if let (s, e) = parsePeriodRange(block) {
                periodStart = s
                periodEnd = e
            }
            guard !parsed.name.isEmpty else { return }
            list.append(ParsedCourseItem(
                name: parsed.name,
                teacher: parsed.teacher,
                location: parsed.location,
                credits: parsed.credits,
                weekRangesString: parsed.weekRangesString,
                weekParity: parsed.weekParity,
                dayOfWeek: defaultDay,
                periodIndex: periodStart,
                periodEnd: periodEnd
            ))
        }
        return list
    }

    /// 从一块 timetable_con 中解析：课程名、教师、地点、周次串、单双周、学分
    private static func parseOneTimetableCon(html: String) -> (name: String, teacher: String, location: String, weekRangesString: String, weekParity: Course.WeekParity, credits: Double?) {
        var name = ""
        var teacher = ""
        var location = ""
        var weekRangesString = ""
        var weekParity: Course.WeekParity = .all

        // 课程名
        if let r = html.range(of: "class=\"title\"", options: .caseInsensitive),
           let end = html[r.upperBound...].range(of: "</span>") {
            let slice = String(html[r.upperBound..<end.lowerBound])
            name = stripHTML(slice)
//            name = name.replacingOccurrences(of: "★", with: "").replacingOccurrences(of: "○", with: "")
//                .replacingOccurrences(of: "◆", with: "").replacingOccurrences(of: "◇", with: "").replacingOccurrences(of: "●", with: "")
            name = cleanParsedText(name)
        }

        // 周数
        if let weekRange = html.range(of: "周数：", options: .caseInsensitive) {
            let after = String(html[weekRange.upperBound...])
            weekRangesString = parseWeekRangesString(from: after)
        } else if let paren = html.range(of: "节)", options: .caseInsensitive) {
            let after = String(html[paren.upperBound...])
            weekRangesString = parseWeekRangesString(from: after)
        }
        if weekRangesString.isEmpty, let left = html.range(of: "("), let right = html.range(of: "节)", range: left.upperBound..<html.endIndex) {
            let mid = String(html[left.upperBound..<right.lowerBound])
            if let dash = mid.range(of: "-"), let p = Int(mid[mid.startIndex..<dash.lowerBound].trimmingCharacters(in: .whitespaces)) {
                weekRangesString = "\(p)-\(p)"
            }
        }

        if html.contains("单周") { weekParity = .odd }
        else if html.contains("双周") { weekParity = .even }

        // 上课地点
        if let marker = html.range(of: "glyphicon-map-marker", options: .caseInsensitive) {
            let after = String(html[marker.upperBound...])
            location = extractFirstFontContent(after) ?? ""
            if location.hasPrefix("校区") { location = String(location.dropFirst()).trimmingCharacters(in: .whitespaces) }
            if let spaceIdx = location.firstIndex(of: " "), spaceIdx != location.endIndex {
                let afterSpace = location[location.index(after: spaceIdx)...].trimmingCharacters(in: .whitespaces)
                if !afterSpace.isEmpty, afterSpace.count < location.count { location = afterSpace }
            }
            location = cleanParsedText(location)
        }
        if location.isEmpty, let locLabel = html.range(of: "上课地点：", options: .caseInsensitive) {
            let after = String(html[locLabel.upperBound...])
            location = extractFirstFontContent(after) ?? takeUntilNextTagOrP(after)
            location = cleanParsedText(location)
        }
        if location.contains("上课地点：") { location = location.replacingOccurrences(of: "上课地点：", with: "").trimmingCharacters(in: .whitespaces) }

        // 教师
        if let user = html.range(of: "glyphicon-user", options: .caseInsensitive) {
            let after = String(html[user.upperBound...])
            teacher = extractFirstFontContent(after) ?? ""
            teacher = cleanParsedText(teacher)
        }
        if teacher.isEmpty, let teacherLabel = html.range(of: "教师", options: .caseInsensitive) {
            let after = String(html[teacherLabel.upperBound...])
            var s = extractFirstFontContent(after) ?? takeUntilNextTagOrP(after)
            if s.hasPrefix("：") || s.hasPrefix(":") { s = String(s.dropFirst()) }
            teacher = cleanParsedText(s)
        }
        if teacher.contains("教师") {
            teacher = teacher.replacingOccurrences(of: "教师 ：", with: "").replacingOccurrences(of: "教师：", with: "").trimmingCharacters(in: .whitespaces)
        }

        // 学分：<span ... title="学分">...</span><font ...> 3.0</font> 或 学分：2.0
        let credits = parseCredits(from: html)

        return (name, teacher, location, weekRangesString, weekParity, credits)
    }

    /// 从 timetable_con 块中解析学分（正方格式：title="学分" 后紧跟 font 内容，或 学分：2.0）
    private static func parseCredits(from block: String) -> Double? {
        // 网格课表：<span ... title="学分">...</span><font ...> 3.0</font>
        if let range = block.range(of: "title=\"学分\"", options: .caseInsensitive) {
            let after = String(block[range.upperBound...])
            if let fontContent = extractFirstFontContent(after) {
                let trimmed = fontContent.trimmingCharacters(in: .whitespaces)
                if let value = Double(trimmed), value >= 0 { return value }
            }
        }
        // 列表课表：学分：2.0 或 学分：3.0
        let pattern = #"学分[：:]\s*(\d+\.?\d*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
              m.numberOfRanges >= 2, m.range(at: 1).location != NSNotFound,
              let r = Range(m.range(at: 1), in: block) else { return nil }
        return Double(block[r].trimmingCharacters(in: .whitespaces))
    }

    private static func parseWeekRangesString(from raw: String) -> String {
        let s = raw.prefix(200)
        var out: [String] = []
        let pattern = #"(\d+)(?:-(\d+))?周"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let ns = String(s) as NSString
        regex.enumerateMatches(in: String(s), options: [], range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let match = m, match.numberOfRanges >= 2 else { return }
            let a = ns.substring(with: match.range(at: 1))
            if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound {
                let b = ns.substring(with: match.range(at: 2))
                out.append("\(a)-\(b)")
            } else {
                out.append("\(a)-\(a)")
            }
        }
        return out.joined(separator: ",")
    }

    private static func parsePeriodRange(_ block: String) -> (Int, Int)? {
        let pattern = #"\((\d+)-(\d+)节\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
              m.numberOfRanges >= 3,
              let r1 = Range(m.range(at: 1), in: block),
              let r2 = Range(m.range(at: 2), in: block),
              let a = Int(block[r1]), let b = Int(block[r2]) else { return nil }
        return (a, b)
    }

    private static func stripHTML(_ s: String) -> String {
        var out = s
        let tagPattern = "<[^>]+>"
        if let r = try? NSRegularExpression(pattern: tagPattern) {
            let ns = out as NSString
            out = r.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        }
        out = out
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
        return cleanParsedText(out)
    }

    private static func cleanParsedText(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let badPrefixes = [">", "\">", "\"", "<", "\"<", "> "]
        let badSuffixes = ["<", ">", "\"", "\"<", "\">", " <"]
        for pre in badPrefixes {
            if out.hasPrefix(pre) { out = String(out.dropFirst(pre.count)).trimmingCharacters(in: .whitespaces) }
        }
        for suf in badSuffixes {
            if out.hasSuffix(suf) { out = String(out.dropLast(suf.count)).trimmingCharacters(in: .whitespaces) }
        }
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractFirstFontContent(_ s: String) -> String? {
        let pattern = #"<font[^>]*>([^<]*)</font>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges >= 2, m.range(at: 1).location != NSNotFound,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        let inner = String(s[r])
        let cleaned = stripHTML(inner).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func takeUntilNextTagOrP(_ s: String) -> String {
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "<" || c == "\n" { break }
            result.append(c)
            i = s.index(after: i)
        }
        return cleanParsedText(result)
    }
}
