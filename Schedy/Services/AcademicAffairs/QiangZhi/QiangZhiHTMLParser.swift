//
//  QiangZhiHTMLParser.swift
//  Schedy
//
//  强智教务「学期理论课表」解析：
//  - 表格 id=kbtable
//  - 每一行首列为节次（0102节/0304节...）
//  - 每天单元格内课程显示在 div.kbcontent1（简版）或 div.kbcontent（详情）
//

import Foundation

enum QiangZhiHTMLParser: AcademicAffairsHTMLParserProtocol {
    static func parse(html: String) -> [ParsedCourseItem] {
        guard let tableHTML = extractKBTable(from: html) else { return [] }

        var rawItems: [ParsedCourseItem] = []
        let rows = extractRowBlocks(from: tableHTML)

        for rowHTML in rows {
            guard let (periodStart, periodEnd) = extractPeriodRange(from: rowHTML) else { continue }
            let cells = extractTDContents(from: rowHTML)
            guard !cells.isEmpty else { continue }

            for (index, cellHTML) in cells.enumerated() {
                let day = index + 1
                guard day <= 7 else { break }
                rawItems.append(contentsOf: parseCell(cellHTML, dayOfWeek: day, periodStart: periodStart, periodEnd: periodEnd))
            }
        }

        return mergeAdjacentPeriods(rawItems)
    }

    private static func extractKBTable(from html: String) -> String? {
        guard let start = html.range(of: "<table id=\"kbtable\"", options: .caseInsensitive) else {
            return nil
        }
        let remaining = String(html[start.lowerBound...])
        guard let end = remaining.range(of: "</table>", options: .caseInsensitive) else {
            return nil
        }
        return String(remaining[..<end.upperBound])
    }

    private static func extractRowBlocks(from tableHTML: String) -> [String] {
        let pattern = #"<tr[^>]*>(.*?)</tr>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let ns = tableHTML as NSString
        var rows: [String] = []
        regex.enumerateMatches(in: tableHTML, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard
                let match,
                match.numberOfRanges >= 2,
                match.range(at: 1).location != NSNotFound
            else { return }
            rows.append(ns.substring(with: match.range(at: 1)))
        }
        return rows
    }

    private static func extractPeriodRange(from rowHTML: String) -> (Int, Int)? {
        let pattern = #"(\d{2})(\d{2})节"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = rowHTML as NSString
        guard
            let match = regex.firstMatch(in: rowHTML, options: [], range: NSRange(location: 0, length: ns.length)),
            match.numberOfRanges >= 3,
            let start = Int(ns.substring(with: match.range(at: 1))),
            let end = Int(ns.substring(with: match.range(at: 2)))
        else {
            return nil
        }
        return (start, end)
    }

    private static func extractTDContents(from rowHTML: String) -> [String] {
        let pattern = #"<td[^>]*>(.*?)</td>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let ns = rowHTML as NSString
        var cells: [String] = []
        regex.enumerateMatches(in: rowHTML, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard
                let match,
                match.numberOfRanges >= 2,
                match.range(at: 1).location != NSNotFound
            else { return }
            cells.append(ns.substring(with: match.range(at: 1)))
        }
        return cells
    }

    private static func parseCell(_ cellHTML: String, dayOfWeek: Int, periodStart: Int, periodEnd: Int) -> [ParsedCourseItem] {
        let conciseBlocks = extractDivContents(from: cellHTML, className: "kbcontent1").filter { !isEmptyBlock($0) }
        let detailBlocks = extractDivContents(from: cellHTML, className: "kbcontent").filter { !isEmptyBlock($0) }
        let sourceBlocks = conciseBlocks.isEmpty ? detailBlocks : conciseBlocks

        var parsed: [ParsedCourseItem] = []
        for block in sourceBlocks {
            guard let meta = parseCourseMeta(from: block) else { continue }
            parsed.append(ParsedCourseItem(
                name: meta.name,
                teacher: meta.teacher,
                location: meta.location,
                credits: nil,
                weekRangesString: meta.weekRangesString,
                weekParity: meta.weekParity,
                dayOfWeek: dayOfWeek,
                periodIndex: periodStart,
                periodEnd: periodEnd
            ))
        }
        return parsed
    }

    private static func extractDivContents(from html: String, className: String) -> [String] {
        let pattern = #"<div[^>]*class\s*=\s*['"][^'"]*\bCLASS\b[^'"]*['"][^>]*>(.*?)</div>"#
            .replacingOccurrences(of: "CLASS", with: NSRegularExpression.escapedPattern(for: className))
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let ns = html as NSString
        var blocks: [String] = []
        regex.enumerateMatches(in: html, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard
                let match,
                match.numberOfRanges >= 2,
                match.range(at: 1).location != NSNotFound
            else { return }
            blocks.append(ns.substring(with: match.range(at: 1)))
        }
        return blocks
    }

    private static func parseCourseMeta(from block: String) -> (name: String, teacher: String, location: String, weekRangesString: String, weekParity: Course.WeekParity)? {
        let name = parseCourseName(from: block)
        guard !name.isEmpty else { return nil }

        let weekSource = extractWeekSourceText(from: block)
        let weekRangesString = parseWeekRanges(from: weekSource)
        let weekParity = parseWeekParity(from: weekSource.isEmpty ? block : weekSource)
        let location = parseLocation(from: block)
        let teacher = parseTeacher(from: block)

        return (
            name: name,
            teacher: teacher,
            location: location,
            weekRangesString: weekRangesString,
            weekParity: weekParity
        )
    }

    private static func parseCourseName(from block: String) -> String {
        var prefix = block
        if let br = prefix.range(of: "<br", options: .caseInsensitive) {
            prefix = String(prefix[..<br.lowerBound])
        }
        if let font = prefix.range(of: "<font", options: .caseInsensitive) {
            prefix = String(prefix[..<font.lowerBound])
        }
        return cleanParsedText(stripHTML(prefix))
    }

    private static func extractWeekSourceText(from block: String) -> String {
        let patterns = [
            #"<font[^>]*title\s*=\s*['"]周次\(节次\)['"][^>]*>(.*?)</font>"#,
            #"<font[^>]*title\s*=\s*['"]班级['"][^>]*>[\s\S]*?<br/>\s*([^<]*(?:\(\s*全部\s*\)|\(\s*单周\s*\)|\(\s*双周\s*\))[^<]*)</font>"#
        ]
        for pattern in patterns {
            if let extracted = firstCapturedGroup(from: block, pattern: pattern) {
                let normalized = cleanParsedText(stripHTML(extracted))
                if !normalized.isEmpty { return normalized }
            }
        }
        return ""
    }

    private static func parseWeekParity(from text: String) -> Course.WeekParity {
        if text.contains("单周") { return .odd }
        if text.contains("双周") { return .even }
        return .all
    }

    private static func parseWeekRanges(from text: String) -> String {
        guard !text.isEmpty else { return "" }
        let source = extractWeekListCandidate(from: text)
        guard !source.isEmpty else { return "" }

        let maxWeek = 30
        let pattern = #"(\d{1,2})\s*-\s*(\d{1,2})|(\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }

        let ns = source as NSString
        var parts: [String] = []

        regex.enumerateMatches(in: source, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            if
                match.numberOfRanges >= 3,
                match.range(at: 1).location != NSNotFound,
                match.range(at: 2).location != NSNotFound,
                let a = Int(ns.substring(with: match.range(at: 1))),
                let b = Int(ns.substring(with: match.range(at: 2))),
                a >= 1, a <= maxWeek, b >= 1, b <= maxWeek, a <= b
            {
                parts.append("\(a)-\(b)")
                return
            }
            if
                match.numberOfRanges >= 4,
                match.range(at: 3).location != NSNotFound,
                let n = Int(ns.substring(with: match.range(at: 3))),
                n >= 1, n <= maxWeek
            {
                parts.append("\(n)-\(n)")
            }
        }

        var deduped: [String] = []
        var seen = Set<String>()
        for part in parts where !seen.contains(part) {
            seen.insert(part)
            deduped.append(part)
        }
        return deduped.joined(separator: ",")
    }

    private static func extractWeekListCandidate(from text: String) -> String {
        let cleaned = cleanParsedText(text)
        if cleaned.isEmpty { return "" }

        let markerPattern = #"(.+?)\s*\((全部|单周|双周)\)\s*$"#
        if
            let markerRegex = try? NSRegularExpression(pattern: markerPattern),
            let match = markerRegex.firstMatch(in: cleaned, options: [], range: NSRange(location: 0, length: (cleaned as NSString).length)),
            match.numberOfRanges >= 2,
            match.range(at: 1).location != NSNotFound,
            let range = Range(match.range(at: 1), in: cleaned)
        {
            let beforeMarker = String(cleaned[range]).trimmingCharacters(in: .whitespaces)
            let trailingPattern = #"\d{1,2}(?:\s*-\s*\d{1,2})?(?:\s*[，,]\s*\d{1,2}(?:\s*-\s*\d{1,2})?)*\s*$"#
            if
                let trailingRegex = try? NSRegularExpression(pattern: trailingPattern),
                let trailingMatch = trailingRegex.firstMatch(in: beforeMarker, options: [], range: NSRange(location: 0, length: (beforeMarker as NSString).length)),
                let trailingRange = Range(trailingMatch.range(at: 0), in: beforeMarker)
            {
                let candidate = String(beforeMarker[trailingRange]).trimmingCharacters(in: .whitespaces)
                let prefix = String(beforeMarker[..<trailingRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                return normalizeStickyLeadingWeekToken(candidate: candidate, prefix: prefix)
            }
        }

        return cleaned
    }

    /// 处理「班级号+周次」粘连导致的首 token 偏大问题：
    /// 例如 "...2023011-16(全部)" 被提成 "11-16"，需要修正为 "1-16"。
    private static func normalizeStickyLeadingWeekToken(candidate: String, prefix: String) -> String {
        guard
            let lastPrefixChar = prefix.last,
            lastPrefixChar.isNumber,
            lastPrefixChar == "0"
        else {
            return candidate
        }

        var parts = candidate.split(whereSeparator: { $0 == "," || $0 == "，" }).map(String.init)
        guard !parts.isEmpty else { return candidate }

        let first = parts[0].trimmingCharacters(in: .whitespaces)
        let rangePattern = #"^(\d{2})\s*-\s*(\d{1,2})$"#
        if
            let regex = try? NSRegularExpression(pattern: rangePattern),
            let m = regex.firstMatch(in: first, options: [], range: NSRange(location: 0, length: (first as NSString).length)),
            m.numberOfRanges >= 3,
            m.range(at: 1).location != NSNotFound,
            m.range(at: 2).location != NSNotFound
        {
            let ns = first as NSString
            let left = ns.substring(with: m.range(at: 1))
            let right = ns.substring(with: m.range(at: 2))
            if
                left.hasPrefix("1"),
                let tailLeft = Int(String(left.suffix(1))),
                let rightValue = Int(right),
                tailLeft >= 1, tailLeft <= 9, rightValue >= 1, tailLeft <= rightValue
            {
                parts[0] = "\(tailLeft)-\(rightValue)"
                return parts.joined(separator: ",")
            }
        }

        let singlePattern = #"^(\d{2})$"#
        if
            let regex = try? NSRegularExpression(pattern: singlePattern),
            let m = regex.firstMatch(in: first, options: [], range: NSRange(location: 0, length: (first as NSString).length)),
            m.numberOfRanges >= 2,
            m.range(at: 1).location != NSNotFound
        {
            let ns = first as NSString
            let left = ns.substring(with: m.range(at: 1))
            if left.hasPrefix("1"), let tailLeft = Int(String(left.suffix(1))), tailLeft >= 1, tailLeft <= 9 {
                parts[0] = "\(tailLeft)"
                return parts.joined(separator: ",")
            }
        }

        return candidate
    }

    private static func parseLocation(from block: String) -> String {
        let patterns = [
            #"<font[^>]*title\s*=\s*['"]教室['"][^>]*>(.*?)</font>"#,
            #"<font[^>]*title\s*=\s*['"]上课地点['"][^>]*>(.*?)</font>"#
        ]
        for pattern in patterns {
            if let extracted = firstCapturedGroup(from: block, pattern: pattern) {
                let cleaned = cleanParsedText(stripHTML(extracted))
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return ""
    }

    private static func parseTeacher(from block: String) -> String {
        let patterns = [
            #"<font[^>]*title\s*=\s*['"]教师['"][^>]*>(.*?)</font>"#,
            #"教师[：:]\s*([^<\n\r]+)"#
        ]
        for pattern in patterns {
            if let extracted = firstCapturedGroup(from: block, pattern: pattern) {
                let cleaned = cleanParsedText(stripHTML(extracted))
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return ""
    }

    private static func firstCapturedGroup(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        guard
            let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)),
            match.numberOfRanges >= 2,
            match.range(at: 1).location != NSNotFound,
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[range])
    }

    private static func isEmptyBlock(_ block: String) -> Bool {
        let cleaned = cleanParsedText(stripHTML(block))
        return cleaned.isEmpty || cleaned == "&nbsp;"
    }

    private static func mergeAdjacentPeriods(_ items: [ParsedCourseItem]) -> [ParsedCourseItem] {
        guard !items.isEmpty else { return [] }

        let groupKey: (ParsedCourseItem) -> String = {
            "\($0.name)|\($0.teacher ?? "")|\($0.location ?? "")|\($0.weekRangesString)|\($0.weekParity.rawValue)|\($0.dayOfWeek)"
        }

        var grouped: [String: [ParsedCourseItem]] = [:]
        for item in items {
            grouped[groupKey(item), default: []].append(item)
        }

        var merged: [ParsedCourseItem] = []
        for (_, group) in grouped {
            let sorted = group.sorted { lhs, rhs in
                if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
                return lhs.periodIndex < rhs.periodIndex
            }
            guard var current = sorted.first else { continue }
            for item in sorted.dropFirst() {
                if item.periodIndex <= current.periodEnd + 1 {
                    current.periodEnd = max(current.periodEnd, item.periodEnd)
                } else {
                    merged.append(current)
                    current = item
                }
            }
            merged.append(current)
        }

        return merged.sorted { lhs, rhs in
            if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
            return lhs.periodIndex < rhs.periodIndex
        }
    }

    private static func stripHTML(_ s: String) -> String {
        var out = s
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
            let ns = out as NSString
            out = regex.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
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
        while out.contains("  ") {
            out = out.replacingOccurrences(of: "  ", with: " ")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
