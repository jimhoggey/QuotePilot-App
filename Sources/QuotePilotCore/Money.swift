import Foundation

/// An amount of money in whole cents. Amounts never pass through floating point.
public struct Money: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public var cents: Int

    public init(cents: Int) {
        self.cents = cents
    }

    /// `Money(dollars: 1500)` or `Money(dollars: 12, cents: 50)`.
    public init(dollars: Int, cents: Int = 0) {
        self.cents = dollars * 100 + cents
    }

    /// Reads what someone types into an amount field: "1500", "$1,500.50", "12.345" (rounds to the cent).
    public init?(parsing text: String) {
        let cleaned = text.filter { "0123456789.-".contains($0) }
        guard !cleaned.isEmpty,
              let dollars = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        self = Money(cents: 100).times(dollars)
    }

    public static let zero = Money(cents: 0)

    public static func + (a: Money, b: Money) -> Money { Money(cents: a.cents + b.cents) }
    public static func - (a: Money, b: Money) -> Money { Money(cents: a.cents - b.cents) }
    public static func += (a: inout Money, b: Money) { a.cents += b.cents }
    public static func -= (a: inout Money, b: Money) { a.cents -= b.cents }
    public static func < (a: Money, b: Money) -> Bool { a.cents < b.cents }

    /// This amount times a quantity (1.5 hours, say), rounded half up to the nearest cent.
    public func times(_ quantity: Decimal) -> Money {
        var exact = Decimal(cents) * quantity
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, 0, .plain)
        return Money(cents: NSDecimalNumber(decimal: rounded).intValue)
    }

    /// A whole-number percentage of this amount, rounded half up to the nearest cent.
    public func percent(_ percent: Int) -> Money {
        times(Decimal(percent) / 100)
    }

    /// "$1,500.00", Australian style.
    public func formatted(currencyCode: String = "AUD") -> String {
        (Decimal(cents) / 100).formatted(.currency(code: currencyCode).locale(Locale(identifier: "en_AU")))
    }

    /// "1500.00": no symbol and no thousands separators, for CSV files.
    public var plain: String {
        let sign = cents < 0 ? "-" : ""
        let whole = abs(cents)
        return "\(sign)\(whole / 100)." + String(format: "%02d", whole % 100)
    }

    public var description: String { formatted() }

    public init(from decoder: Decoder) throws {
        cents = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(cents)
    }
}
