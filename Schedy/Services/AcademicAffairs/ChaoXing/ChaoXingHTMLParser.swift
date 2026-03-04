//
//  ChaoXingHTMLParser.swift
//  Schedy
//
//  超星教务「课程表」解析：
//  - 表格 tbody id=kbsjlist
//  - 每行 <tr name="rowkb" sid="{period}">，首列为节次
//  - 课程单元格 <td id="Cell{day}{period}" rowspan="{span}" name="tdbox tdbox{day}">
//  - 课程信息在 onclick="popBox(this, encodedName, teacher, '', encodedLocation, weekRange, ...)"
//

import Foundation

enum ChaoXingHTMLParser: AcademicAffairsHTMLParserProtocol {

    static func parse(html: String) -> [ParsedCourseItem] {
        // Extract tbody#kbsjlist
        guard let tbodyHTML = extractTBody(from: html) else { return [] }

        var items: [ParsedCourseItem] = []

        // Match all course cells: <td id="Cell{day}{period}" rowspan="{span}" ...>
        let cellPattern = #"<td\s+id="Cell(\d)(\d+)"\s+rowspan="(\d+)"[^>]*name="tdbox[^"]*"[^>]*>(.*?)</td>"#
        guard let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }

        let ns = tbodyHTML as NSString
        cellRegex.enumerateMatches(in: tbodyHTML, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard
                let match,
                match.numberOfRanges >= 5,
                let day = Int(ns.substring(with: match.range(at: 1))),
                let period = Int(ns.substring(with: match.range(at: 2))),
                let span = Int(ns.substring(with: match.range(at: 3)))
            else { return }

            let cellHTML = ns.substring(with: match.range(at: 4))
            items.append(contentsOf: parseCourses(from: cellHTML, day: day, periodStart: period, periodEnd: period + span - 1))
        }

        return items
    }

    // MARK: - Extraction

    private static func extractTBody(from html: String) -> String? {
        guard let start = html.range(of: #"<tbody id="kbsjlist""#, options: .caseInsensitive) else { return nil }
        let tail = String(html[start.lowerBound...])
        guard let end = tail.range(of: "</tbody>", options: .caseInsensitive) else { return nil }
        return String(tail[..<end.upperBound])
    }

    private static func parseCourses(from cellHTML: String, day: Int, periodStart: Int, periodEnd: Int) -> [ParsedCourseItem] {
        // Match all popBox calls in this cell
        let popPattern = #"onclick="popBox\(this\s*,\s*'([^']*)'\s*,\s*'([^']*)'\s*,\s*'[^']*'\s*,\s*'([^']*)'\s*,\s*'([^']*)'"#
        guard let popRegex = try? NSRegularExpression(pattern: popPattern, options: .caseInsensitive) else { return [] }

        var items: [ParsedCourseItem] = []
        let ns = cellHTML as NSString

        popRegex.enumerateMatches(in: cellHTML, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard
                let match, match.numberOfRanges >= 5,
                let nameRange = Range(match.range(at: 1), in: cellHTML),
                let teacherRange = Range(match.range(at: 2), in: cellHTML),
                let locationRange = Range(match.range(at: 3), in: cellHTML),
                let weekRange = Range(match.range(at: 4), in: cellHTML)
            else { return }

            let name = decode(String(cellHTML[nameRange]))
            guard !name.isEmpty else { return }

            let teacher = String(cellHTML[teacherRange])
            let location = decode(String(cellHTML[locationRange]))
            let weekStr = String(cellHTML[weekRange])

            let (weekRangesString, parity) = parseWeeks(weekStr)

            items.append(ParsedCourseItem(
                name: name,
                teacher: teacher.isEmpty ? nil : teacher,
                location: location.isEmpty ? nil : location,
                credits: nil,
                weekRangesString: weekRangesString,
                weekParity: parity,
                dayOfWeek: day,
                periodIndex: periodStart,
                periodEnd: periodEnd
            ))
        }

        return items
    }

    // MARK: - Week parsing

    /// Parses week strings like "1-16", "2,4,6,8", "2-2,4-4,6-6,8-8", "1-8,10-16"
    private static func parseWeeks(_ raw: String) -> (String, Course.WeekParity) {
        // Collect all individual week numbers
        var weeks = Set<Int>()
        let rangePattern = #"(\d+)-(\d+)|(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: rangePattern) else { return (raw, .all) }

        let ns = raw as NSString
        regex.enumerateMatches(in: raw, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            if match.range(at: 1).location != NSNotFound,
               match.range(at: 2).location != NSNotFound,
               let a = Int(ns.substring(with: match.range(at: 1))),
               let b = Int(ns.substring(with: match.range(at: 2))), a <= b {
                (a...b).forEach { weeks.insert($0) }
            } else if match.range(at: 3).location != NSNotFound,
                      let n = Int(ns.substring(with: match.range(at: 3))) {
                weeks.insert(n)
            }
        }

        guard !weeks.isEmpty else { return (raw, .all) }

        let sorted = weeks.sorted()
        let parity = detectParity(sorted)
        let rangesString = toRangesString(sorted)
        return (rangesString, parity)
    }

    private static func detectParity(_ weeks: [Int]) -> Course.WeekParity {
        guard weeks.count > 1 else { return .all }
        let allOdd = weeks.allSatisfy { $0 % 2 == 1 }
        let allEven = weeks.allSatisfy { $0 % 2 == 0 }
        if allOdd { return .odd }
        if allEven { return .even }
        return .all
    }

    private static func toRangesString(_ sorted: [Int]) -> String {
        var ranges: [(Int, Int)] = []
        var start = sorted[0], end = sorted[0]
        for w in sorted.dropFirst() {
            if w == end + 1 { end = w }
            else { ranges.append((start, end)); start = w; end = w }
        }
        ranges.append((start, end))
        return ranges.map { $0.0 == $0.1 ? "\($0.0)-\($0.0)" : "\($0.0)-\($0.1)" }.joined(separator: ",")
    }

    // MARK: - URL decode

    private static func decode(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }
}
