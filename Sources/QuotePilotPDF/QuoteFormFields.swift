import Foundation

/// Names of the form fields on a quote PDF. Every name carries the quote number, so a returned PDF
/// says which quote it answers.
///
/// The names use underscores, such as `quotepilot_Q-0007_line_03`. ISO 32000 reserves "." as the
/// separator in a field's place in the form hierarchy, and Adobe Acrobat may restructure a dotted name
/// when a client saves, which would make the returned quote unreadable.
public enum QuoteFormFields {
    static let prefix = "quotepilot_"

    public enum Part: Equatable {
        case all, name, date
        case line(String)
    }

    public static func acceptAll(_ quote: String) -> String { "\(prefix)\(quote)_all" }
    public static func line(_ quote: String, _ code: String) -> String { "\(prefix)\(quote)_line_\(code)" }
    public static func name(_ quote: String) -> String { "\(prefix)\(quote)_name" }
    public static func date(_ quote: String) -> String { "\(prefix)\(quote)_date" }

    /// Splits a field name into its quote number and part; nil for fields that aren't Quote Pilot's.
    public static func parse(_ field: String) -> (quote: String, part: Part)? {
        guard field.hasPrefix(prefix) else { return nil }
        let rest = String(field.dropFirst(prefix.count))
        if let range = rest.range(of: "_line_", options: .backwards) {
            let quote = String(rest[..<range.lowerBound])
            let code = String(rest[range.upperBound...])
            return quote.isEmpty || code.isEmpty ? nil : (quote, .line(code))
        }
        let endings: [(String, Part)] = [("_all", .all), ("_name", .name), ("_date", .date)]
        for (ending, part) in endings where rest.hasSuffix(ending) {
            let quote = String(rest.dropLast(ending.count))
            return quote.isEmpty ? nil : (quote, part)
        }
        return nil
    }
}
