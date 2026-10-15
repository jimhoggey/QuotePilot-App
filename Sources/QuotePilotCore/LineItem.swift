import Foundation

public enum Unit: String, Codable, CaseIterable, Sendable {
    case hours, days, units

    /// "2 hrs", "1 day", "1.5 hrs"; plain units print as a bare number ("3").
    public func describe(_ quantity: Decimal) -> String {
        let number = quantity.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_AU")))
        switch self {
        case .hours: return quantity == 1 ? "\(number) hr" : "\(number) hrs"
        case .days: return quantity == 1 ? "\(number) day" : "\(number) days"
        case .units: return number
        }
    }
}

public enum LineDecision: String, Codable, Sendable {
    case accepted, declined
}

/// One line on a quote or invoice.
public struct LineItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// The line ID a client sees on a quote: "01", "02", …
    public var code: String
    public var title: String
    public var detail: String
    public var quantity: Decimal
    public var unit: Unit
    public var rate: Money
    /// Quotes only: what the client decided.
    public var decision: LineDecision?

    public init(id: UUID = UUID(), code: String = "", title: String, detail: String = "",
                quantity: Decimal = 1, unit: Unit = .units, rate: Money, decision: LineDecision? = nil) {
        self.id = id
        self.code = code
        self.title = title
        self.detail = detail
        self.quantity = quantity
        self.unit = unit
        self.rate = rate
        self.decision = decision
    }

    public var amount: Money { rate.times(quantity) }
}

extension Array where Element == LineItem {
    public var subtotal: Money { reduce(.zero) { $0 + $1.amount } }
}

/// Subtotal, GST and total. GST is 10% on top, and only when the document is taxed.
public struct Totals: Equatable, Sendable {
    public static let gstPercent = 10

    public var subtotal: Money
    public var gst: Money
    public var total: Money

    public init(subtotal: Money, taxed: Bool) {
        self.subtotal = subtotal
        gst = taxed ? subtotal.percent(Totals.gstPercent) : .zero
        total = subtotal + gst
    }
}
