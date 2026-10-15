import Foundation

/// Names of the form fields on a quote PDF. Every name carries the quote number, so a returned PDF
/// says which quote it answers.
public enum QuoteFormFields {
    static let prefix = "quotepilot."

    public enum Part: Equatable {
        case all, name, date
        case line(String)
    }

    public static func acceptAll(_ quote: String) -> String { "\(prefix)\(quote).all" }
    public static func line(_ quote: String, _ code: String) -> String { "\(prefix)\(quote).line.\(code)" }
    public static func name(_ quote: String) -> String { "\(prefix)\(quote).name" }
    public static func date(_ quote: String) -> String { "\(prefix)\(quote).date" }

    /// Splits a field name into its quote number and part; nil for fields that aren't Quote Pilot's.
    public static func parse(_ field: String) -> (quote: String, part: Part)? {
        guard field.hasPrefix(prefix) else { return nil }
        let rest = String(field.dropFirst(prefix.count))
        if let range = rest.range(of: ".line.", options: .backwards) {
            let quote = String(rest[..<range.lowerBound])
            let code = String(rest[range.upperBound...])
            return quote.isEmpty || code.isEmpty ? nil : (quote, .line(code))
        }
        let endings: [(String, Part)] = [(".all", .all), (".name", .name), (".date", .date)]
        for (ending, part) in endings where rest.hasSuffix(ending) {
            let quote = String(rest.dropLast(ending.count))
            return quote.isEmpty ? nil : (quote, part)
        }
        return nil
    }
}
