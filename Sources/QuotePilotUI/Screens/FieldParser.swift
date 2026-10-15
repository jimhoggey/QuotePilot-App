import Foundation
import QuotePilotCore

/// Reads what someone typed into a number field. Anything that isn't a whole, sensible value gives
/// nil, so half-typed or mistyped text never replaces what's stored.
enum FieldParser {
    /// The most a field takes, in either direction: $10,000,000. `Money(parsing:)` goes up to Int.max
    /// cents, and a few lines that large add past Int.max, which traps. A quote saved like that would
    /// trap again each time the app opened it. The same limit as `Library.problems()`, so nothing
    /// typed can make the library unreadable.
    static let moneyLimitCents = Library.amountLimit.cents

    /// "$1,500.50", "1500", "-20" (a discount line). Rounds to the cent. Nil above $10,000,000.
    static func money(_ text: String) -> Money? {
        // A range check, not abs(): abs(Int.min) traps.
        guard let amount = Money(parsing: text.trimmingCharacters(in: .whitespaces)),
              (-moneyLimitCents...moneyLimitCents).contains(amount.cents)
        else { return nil }
        return amount
    }

    /// "1", "1.5", "0.25": zero or more, with at most two decimal places (what documents print).
    static func quantity(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              !parts[0].isEmpty,
              parts.allSatisfy({ part in part.allSatisfy { $0.isASCII && $0.isNumber } }),
              parts.count == 1 || (1...2).contains(parts[1].count),
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
              value <= Library.quantityLimit
        else { return nil }
        return value
    }

    /// A whole number of days from 0 to 365.
    static func days(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(trimmed), Library.dayCountLimit.contains(value)
        else { return nil }
        return value
    }

    /// "#0b6b66" or "0B6B66" → "#0B6B66".
    static func hex(_ text: String) -> String? {
        var digits = Substring(text.trimmingCharacters(in: .whitespaces))
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        // ASCII only: Character.isHexDigit also accepts fullwidth digits and letters.
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return "#" + digits.uppercased()
    }

    /// "1.5", "2": a quantity as a field shows it.
    static func quantityText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
