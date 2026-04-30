//
//  QiangZhiHTMLParser.swift
//  Schedy
//
//  强智教务「学期理论课表」解析：
//  - 表格 id=kbtable
//  - 每一行首列为节次（0102节/0304节...）
//  - 每天单元格内课程显示在 div.kbcontent（详情）或 div.kbcontent1（简版）
//  - 同一单元格可能包含多门课，用 --------------------- 分隔
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
        var sourceDivs = extractDivContents(from: cellHTML, className: "kbcontent").filter { !isEmptyBlock($0) }
        if sourceDivs.isEmpty {
            sourceDivs = extractDivContents(from: cellHTML, className: "kbcontent1").filter { !isEmptyBlock($0) }
        }
        guard !sourceDivs.isEmpty else { return [] }

        var parsed: [ParsedCourseItem] = []
        for div in sourceDivs {
            let blocks = splitCourseBlocks(div).filter { !isEmptyBlock($0) }
            for block in blocks {
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

    private static func splitCourseBlocks(_ block: String) -> [String] {
        let pattern = #"-{5,}(?:<br\s*/?>)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [block] }

        let ns = block as NSString
        var result: [String] = []
        var lastEnd = 0

        regex.enumerateMatches(in: block, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let sub = ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sub.isEmpty { result.append(sub) }
            lastEnd = match.range.upperBound
        }

        let tail = ns.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }

        return result.isEmpty ? [block] : result
    }

    private static func parseCourseMeta(from block: String) -> (name: String, teacher: String, location: String, weekRangesString: String, weekParity: Course.WeekParity)? {
        let name = parseCourseName(from: block)
        guard !name.isEmpty else { return nil }

        let weekLine = extractWeekLineText(from: block)
        let weekRangesString = parseWeekRanges(from: weekLine.isEmpty ? block : weekLine)
        let weekParity = parseWeekParity(from: weekLine.isEmpty ? block : weekLine)

        return (
            name: name,
            teacher: parseTeacher(from: block),
            location: parseLocation(from: block),
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

    private static func extractWeekLineText(from block: String) -> String {
        let plain = cleanParsedText(stripHTML(block))
        if plain.isEmpty { return "" }

        let pattern = #"(\d{1,2}(?:\s*-\s*\d{1,2})?(?:\s*[，,]\s*\d{1,2}(?:\s*-\s*\d{1,2})?)*)\s*\((全部|单周|双周)\)\s*\[[^\]]*节\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }

        let ns = plain as NSString
        var last: NSTextCheckingResult?
        regex.enumerateMatches(in: plain, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            if let match { last = match }
        }
        guard let match = last else { return "" }

        return ns.substring(with: match.range(at: 0))
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
                let start = Int(ns.substring(with: match.range(at: 1))),
                let end = Int(ns.substring(with: match.range(at: 2))),
                start >= 1, start <= maxWeek, end >= 1, end <= maxWeek, start <= end
            {
                parts.append("\(start)-\(end)")
                return
            }
            if
                match.numberOfRanges >= 4,
                match.range(at: 3).location != NSNotFound,
                let week = Int(ns.substring(with: match.range(at: 3))),
                week >= 1, week <= maxWeek
            {
                parts.append("\(week)-\(week)")
            }
        }

        var seen = Set<String>()
        var deduped: [String] = []
        for part in parts where seen.insert(part).inserted {
            deduped.append(part)
        }
        return deduped.joined(separator: ",")
    }

    private static func extractWeekListCandidate(from text: String) -> String {
        var cleaned = cleanParsedText(stripHTML(text))
        if cleaned.isEmpty { return "" }

        if let bracketRegex = try? NSRegularExpression(pattern: #"\[\d{2}(?:-\d{2})*节\]"#) {
            cleaned = bracketRegex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(location: 0, length: (cleaned as NSString).length),
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.isEmpty { return "" }

        let pattern = #"(\d{1,2}(?:\s*-\s*\d{1,2})?(?:\s*[，,]\s*\d{1,2}(?:\s*-\s*\d{1,2})?)*)\s*\((全部|单周|双周)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return cleaned }

        let ns = cleaned as NSString
        var last: NSTextCheckingResult?
        regex.enumerateMatches(in: cleaned, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            if let match { last = match }
        }

        guard
            let match = last,
            match.numberOfRanges >= 2,
            match.range(at: 1).location != NSNotFound
        else {
            return cleaned
        }

        return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
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
            #"<font[^>]*title\s*=\s*['"]老师['"][^>]*>(.*?)</font>"#,
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
