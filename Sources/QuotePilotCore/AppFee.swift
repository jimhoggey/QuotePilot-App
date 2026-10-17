import Foundation

/// The Quote Pilot fee, at an early stage: a percentage of what's received each month, shown as a
/// figure on Brand → Settings. Nothing is charged, sent or added to any document.
public struct AppFee: Codable, Hashable, Sendable {
    /// What `percent` may be: 0% to 100%. `Library.problems()` refuses anything else.
    public static let percentLimit: ClosedRange<Decimal> = 0...100

    /// Whether Brand → Settings works the fee out. On unless turned off.
    public var calculates: Bool
    /// The fee as a percentage of what's received, such as 3 or 2.5.
    public var percent: Decimal

    public init(calculates: Bool = true, percent: Decimal = 3) {
        self.calculates = calculates
        self.percent = percent
    }

    /// `percent` of `received`, rounded half up to the cent.
    public func fee(on received: Money) -> Money {
        received.times(percent / 100)
    }
}

extension AppFee {
    enum CodingKeys: String, CodingKey {
        case calculates, percent
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppFee()
        calculates = try c.value(.calculates, or: d.calculates)
        percent = try c.value(.percent, or: d.percent)
    }
}

/// The fee's figures on one day: what was received this calendar month and last, and the fee on each.
/// "Received" is the Dashboard's: payments recorded on sent invoices (`Library.received(in:)`).
public struct AppFeeFigures: Equatable, Sendable {
    public var percent: Decimal
    public var receivedThisMonth: Money
    public var feeThisMonth: Money
    public var receivedLastMonth: Money
    public var feeLastMonth: Money

    /// Nil while the fee isn't calculated (Brand → Settings' checkbox is off).
    public init?(library: Library, today: Day) {
        let fee = library.brand.appFee
        guard fee.calculates else { return nil }
        let thisMonth = CalendarMonth(containing: today)
        percent = fee.percent
        receivedThisMonth = library.received(in: thisMonth)
        feeThisMonth = fee.fee(on: receivedThisMonth)
        receivedLastMonth = library.received(in: thisMonth.previous)
        feeLastMonth = fee.fee(on: receivedLastMonth)
    }
}

/// One calendar month, such as October 2026.
public struct CalendarMonth: Hashable, Sendable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init(containing day: Day) {
        self.init(year: day.year, month: day.month)
    }

    /// The month before: December of the year before, for a January.
    public var previous: CalendarMonth {
        month == 1 ? CalendarMonth(year: year - 1, month: 12) : CalendarMonth(year: year, month: month - 1)
    }

    public func contains(_ day: Day) -> Bool { day.year == year && day.month == month }
}

extension Library {
    /// What the payments recorded in `month` on sent invoices add up to: the Dashboard's "This month"
    /// and the Quote Pilot fee's "Received".
    public func received(in month: CalendarMonth) -> Money {
        invoices
            .filter { $0.stage == .sent }
            .flatMap(\.payments)
            .filter { month.contains($0.date) }
            .reduce(.zero) { $0 + $1.amount }
    }
}
