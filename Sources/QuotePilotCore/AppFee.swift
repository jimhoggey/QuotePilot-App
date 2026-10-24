import Foundation

/// The Quote Pilot fee (beta, honour system): a percentage of what's received each calendar month.
/// Each month's fee is due on the 1st of the next; one still unpaid from the 5th locks the app until
/// "I've paid" marks it paid. Nothing is charged or sent anywhere, and no payment details are shown.
public struct AppFee: Codable, Hashable, Sendable {
    /// What `percent` may be: 0% to 100%. `Library.problems()` refuses anything else.
    public static let percentLimit: ClosedRange<Decimal> = 0...100

    /// Whether the fee is worked out, shown in the red bar and owed. On unless turned off.
    public var calculates: Bool
    /// The fee as a percentage of what's received, such as 3 or 2.5.
    public var percent: Decimal
    /// The first month that counts: the one the checkbox was last turned on in. A library saved before
    /// this existed counts from the month it's opened in, so no earlier month is ever owed.
    public var startMonth: CalendarMonth
    /// The months marked paid with "I've paid", by `CalendarMonth.key` ("2026-10").
    public var paidMonths: [String: AppFeePaid]

    public init(calculates: Bool = true, percent: Decimal = 3, startMonth: CalendarMonth = .thisMonth(),
                paidMonths: [String: AppFeePaid] = [:]) {
        self.calculates = calculates
        self.percent = percent
        self.startMonth = startMonth
        self.paidMonths = paidMonths
    }

    /// `percent` of `received`, rounded half up to the cent.
    public func fee(on received: Money) -> Money {
        received.times(percent / 100)
    }
}

/// A month's fee marked paid: the day "I've paid" was pressed and the fee then, for the money record.
public struct AppFeePaid: Codable, Hashable, Sendable {
    public var on: Day
    public var amount: Money

    public init(on: Day, amount: Money) {
        self.on = on
        self.amount = amount
    }
}

extension AppFee {
    enum CodingKeys: String, CodingKey {
        case calculates, percent, startMonth, paidMonths
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppFee()
        calculates = try c.value(.calculates, or: d.calculates)
        percent = try c.value(.percent, or: d.percent)
        startMonth = try c.value(.startMonth, or: d.startMonth)
        paidMonths = try c.value(.paidMonths, or: d.paidMonths)
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

/// What the red fee bar says, most important first. The bar shows while the fee is calculated.
public enum AppFeeState: Equatable, Sendable {
    /// Nothing owing: this month's fee so far, on what's been received, due on the 1st of next month.
    case running(month: CalendarMonth, fee: Money, received: Money)
    /// A closed month's fee, due and not marked paid yet, but not more than 3 days late.
    case due(month: CalendarMonth, fee: Money)
    /// A closed month's fee more than 3 days late: the app is locked until it's marked paid.
    case locked(month: CalendarMonth, fee: Money)

    public var isLocked: Bool {
        if case .locked = self { return true }
        return false
    }

    /// The month "I've paid" marks paid; nil while nothing is owing.
    public var monthToPay: CalendarMonth? {
        switch self {
        case .running: return nil
        case .due(let month, _), .locked(let month, _): return month
        }
    }
}

/// One calendar month, such as October 2026. Stored as "2026-10".
public struct CalendarMonth: Hashable, Comparable, Sendable, Codable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init(containing day: Day) {
        self.init(year: day.year, month: day.month)
    }

    /// The month this Mac's clock is in.
    public static func thisMonth() -> CalendarMonth { CalendarMonth(containing: Day.today()) }

    /// "2026-10". Nil for anything else, or a month a `Day` can't hold.
    public init?(key: String) {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]),
              (1...9999).contains(year), (1...12).contains(month)
        else { return nil }
        self.init(year: year, month: month)
    }

    public var key: String { String(format: "%04d-%02d", year, month) }

    /// The month before: December of the year before, for a January.
    public var previous: CalendarMonth {
        month == 1 ? CalendarMonth(year: year - 1, month: 12) : CalendarMonth(year: year, month: month - 1)
    }

    /// The month after: January of the year after, for a December.
    public var next: CalendarMonth {
        month == 12 ? CalendarMonth(year: year + 1, month: 1) : CalendarMonth(year: year, month: month + 1)
    }

    public var firstDay: Day { Day(year: year, month: month, day: 1) }

    /// The day this month's fee is due: the 1st of the next month.
    public var feeDue: Day { next.firstDay }

    /// The first day an unpaid fee locks the app: more than 3 days after it was due, the 5th.
    public var feeLocksOn: Day { feeDue.adding(days: 4) }

    /// "October"
    public var name: String {
        ["January", "February", "March", "April", "May", "June", "July", "August", "September",
         "October", "November", "December"][month - 1]
    }

    /// "October 2026"
    public var label: String { "\(name) \(year)" }

    public func contains(_ day: Day) -> Bool { day.year == year && day.month == month }

    public static func < (a: CalendarMonth, b: CalendarMonth) -> Bool { (a.year, a.month) < (b.year, b.month) }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let month = CalendarMonth(key: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Not a month: \(text)"))
        }
        self = month
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
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

    /// The fee for `month`: the percentage of what was received in it, rounded half up to the cent.
    public func appFee(for month: CalendarMonth) -> Money {
        brand.appFee.fee(on: received(in: month))
    }

    /// The closed months whose fee is owed, oldest first: before `thisMonth`, from the start month on,
    /// with a fee over $0, and not marked paid. Only months with payments can have a fee.
    public func unpaidAppFeeMonths(before thisMonth: CalendarMonth) -> [CalendarMonth] {
        let fee = brand.appFee
        let months = Set(invoices.filter { $0.stage == .sent }.flatMap(\.payments).map { CalendarMonth(containing: $0.date) })
        return months
            .filter { $0 >= fee.startMonth && $0 < thisMonth && fee.paidMonths[$0.key] == nil && appFee(for: $0) > .zero }
            .sorted()
    }

    /// What the fee bar shows on `today`, or nil while the fee isn't calculated. The oldest unpaid
    /// month comes first: locked from its `feeLocksOn`, due before that.
    public func appFeeState(today: Day) -> AppFeeState? {
        guard brand.appFee.calculates else { return nil }
        let thisMonth = CalendarMonth(containing: today)
        if let owed = unpaidAppFeeMonths(before: thisMonth).first {
            let fee = appFee(for: owed)
            return today >= owed.feeLocksOn ? .locked(month: owed, fee: fee) : .due(month: owed, fee: fee)
        }
        let received = received(in: thisMonth)
        return .running(month: thisMonth, fee: brand.appFee.fee(on: received), received: received)
    }

    /// "I've paid": marks `month`'s fee paid on `day`, with Activity saying so. Honour system.
    public mutating func markAppFeePaid(_ month: CalendarMonth, on day: Day, at time: Date = Date()) {
        let fee = appFee(for: month)
        brand.appFee.paidMonths[month.key] = AppFeePaid(on: day, amount: fee)
        log("Marked the \(month.label) Quote Pilot fee as paid (\(fee.formatted(currencyCode: brand.currencyCode)))", at: time)
    }
}
