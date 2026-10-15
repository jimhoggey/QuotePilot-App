import Foundation

/// A calendar day with no time and no time zone: issue dates, due dates, payment dates.
public struct Day: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// The date must exist (not 31 February). A `Day` that can't be written as `iso` and read back
    /// would make a library the next launch can't open, so this traps rather than carry one.
    public init(year: Int, month: Int, day: Int) {
        precondition(Day.isValid(year: year, month: month, day: day),
                     "Day(year:month:day:) needs a date that exists, not \(year)-\(month)-\(day)")
        self.init(uncheckedYear: year, month: month, day: day)
    }

    /// For a date that has already been checked (`Day(iso:)`), and for tests that need a day that
    /// doesn't exist. Everything else goes through `init(year:month:day:)`.
    init(uncheckedYear year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Whether the date exists on the Gregorian calendar, with a four-digit year (the only years
    /// `iso` can write and `Day(iso:)` can read back).
    static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard (1...9999).contains(year), (1...12).contains(month), day >= 1 else { return false }
        let isLeapYear = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let daysInMonth = [31, isLeapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return day <= daysInMonth[month - 1]
    }

    /// The day a moment falls on in a time zone (this Mac's by default).
    public init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    public static func today() -> Day { Day(Date()) }

    /// "2026-10-15". Returns nil unless the text is exactly YYYY-MM-DD and names a real day.
    public init?(iso: String) {
        // Ten ASCII characters: four digits, a hyphen, two digits, a hyphen, two digits.
        let bytes = Array(iso.utf8)
        guard bytes.count == 10 else { return nil }
        for (index, byte) in bytes.enumerated() {
            let isHyphenPosition = index == 4 || index == 7
            let isValid = isHyphenPosition
                ? byte == UInt8(ascii: "-")
                : (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            guard isValid else { return nil }
        }
        guard let year = Int(iso.prefix(4)),
              let month = Int(iso.dropFirst(5).prefix(2)),
              let day = Int(iso.suffix(2)),
              Day.isValid(year: year, month: month, day: day)   // 2026-02-31 is rejected, not rolled over
        else { return nil }
        self.init(uncheckedYear: year, month: month, day: day)
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
