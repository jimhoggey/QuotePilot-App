import Foundation

/// A calendar day with no time and no time zone: issue dates, due dates, payment dates.
public struct Day: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day a moment falls on in a time zone (this Mac's by default).
    public init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    public static func today() -> Day { Day(Date()) }

    /// "2026-10-15". Returns nil for text that isn't a real date.
    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        let candidate = Day(year: parts[0], month: parts[1], day: parts[2])
        // 2026-02-31 would roll over to March; reject it.
        guard Day(candidate.midnightUTC, timeZone: .gmt) == candidate else { return nil }
        self = candidate
    }

    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { iso }

    /// "15 October 2026"
    public var long: String { format("d MMMM yyyy") }

    /// "15 Oct 2026"
    public var short: String { format("d MMM yyyy") }

    public func adding(days: Int) -> Day {
        Day(Day.utc.date(byAdding: .day, value: days, to: midnightUTC)!, timeZone: .gmt)
    }

    /// Whole days from `other` to this day; positive when this day is later.
    public func days(since other: Day) -> Int {
        Day.utc.dateComponents([.day], from: other.midnightUTC, to: midnightUTC).day!
    }

    public static func < (a: Day, b: Day) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let day = Day(iso: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Not a date: \(text)"))
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }

    var midnightUTC: Date {
        Day.utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func format(_ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = .gmt
        formatter.dateFormat = pattern
        return formatter.string(from: midnightUTC)
    }
}
