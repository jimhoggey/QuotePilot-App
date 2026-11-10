import Foundation

/// A financial year's profit, as the Expenses tab's pie shows it: the payments received in the year
/// against the expenses and Quote Pilot fees paid in it.
///
/// GST that belongs to the tax office is left out: a payment's always, and an expense's when the
/// business is registered for GST and so claims it back. Unregistered, an expense's GST was part of
/// what it cost. Income is then the money record's "Amount ex GST" of the year's payments.
public struct Profit: Equatable, Sendable {
    public var year: FinancialYear
    public var income: Money
    public var expenses: Money

    public init(year: FinancialYear, income: Money, expenses: Money) {
        self.year = year
        self.income = income
        self.expenses = expenses
    }

    /// Below zero for a loss.
    public var profit: Money { income - expenses }

    /// Profit as a whole percentage of income, rounded half up: 73, or -25 for a loss. Nil before any
    /// income.
    public var margin: Int? {
        guard income > .zero else { return nil }
        var exact = Decimal(profit.cents) * 100 / Decimal(income.cents)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// The part of the pie expenses take, 0 to 1: all of it once they reach the income. Nil before any
    /// income.
    public var expenseShare: Double? {
        guard income > .zero else { return nil }
        return min(1, max(0, Double(expenses.cents) / Double(income.cents)))
    }
}

extension Library {
    /// `year`'s profit: the payments on sent invoices dated in it, and the expenses and fees paid in it.
    public func profit(in year: FinancialYear) -> Profit {
        let income = invoices.filter { $0.stage == .sent }.flatMap { invoice in
            invoice.payments.filter { year.contains($0.date) }.map { $0.amount - invoice.gstShare(of: $0.amount) }
        }
        let expenses = moneyOut().filter { year.contains($0.date) }.map { brand.gstRegistered ? $0.total - $0.gst : $0.total }
        return Profit(year: year, income: income.reduce(.zero, +), expenses: expenses.reduce(.zero, +))
    }
}
