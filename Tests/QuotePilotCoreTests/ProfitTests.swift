import Foundation
import Testing
@testable import QuotePilotCore

/// A financial year's profit, for the Expenses tab's pie. Made-up data.
@Suite struct ProfitTests {
    let year = FinancialYear(startYear: 2026)

    func day(_ year: Int, _ month: Int, _ day: Int) -> Day { Day(year: year, month: month, day: day) }

    /// INV-0001 for $1,000 ($1,100 with GST when `taxed`), paid `paid` on each of the days.
    func library(taxed: Bool = false, paid: [(Day, Int)]) throws -> Library {
        var (library, id) = try MoneyRecordTests().library(taxed: taxed, sent: day(2026, 6, 1))
        for (date, dollars) in paid {
            try library.recordPayment(Payment(date: date, amount: Money(dollars: dollars)), toInvoice: id)
        }
        return library
    }

    @Test func incomeIsTheYearsPaymentsLessTheirGST() throws {
        let library = try self.library(taxed: true, paid: [(day(2026, 6, 30), 110), (day(2026, 7, 1), 550),
                                                           (day(2027, 6, 30), 330), (day(2027, 7, 1), 110)])
        let profit = library.profit(in: year)
        #expect(profit.year == year)
        #expect(profit.income == Money(dollars: 800), "$880 paid in the year, $80 of it GST")
    }

    @Test func expensesLeaveOutGSTOnlyWhenRegistered() throws {
        var library = try self.library(paid: [(day(2026, 8, 1), 1000)])
        try library.addExpense(Expense(date: day(2026, 7, 1), total: Money(dollars: 110), gst: Money(dollars: 10)))
        try library.addExpense(Expense(date: day(2026, 6, 30), total: Money(dollars: 50)))
        try library.addExpense(Expense(date: day(2027, 7, 1), total: Money(dollars: 60)))
        library.brand.appFee.paidMonths["2026-08"] = AppFeePaid(on: day(2026, 9, 2), amount: Money(cents: 1650))

        #expect(library.profit(in: year).expenses == Money(cents: 12650), "unregistered, the GST was a cost")
        library.brand.gstRegistered = true
        #expect(library.profit(in: year).expenses == Money(cents: 11650), "registered, it's claimed back")
    }

    @Test func theMarginAndTheExpensesShare() {
        let healthy = Profit(year: year, income: Money(dollars: 1000), expenses: Money(dollars: 270))
        #expect(healthy.profit == Money(dollars: 730))
        #expect(healthy.margin == 73)
        #expect(healthy.expenseShare == 0.27)

        let loss = Profit(year: year, income: Money(dollars: 1000), expenses: Money(dollars: 1250))
        #expect(loss.profit == Money(dollars: -250))
        #expect(loss.margin == -25)
        #expect(loss.expenseShare == 1, "a loss fills the pie")

        let nothingSpent = Profit(year: year, income: Money(dollars: 1000), expenses: .zero)
        #expect(nothingSpent.margin == 100)
        #expect(nothingSpent.expenseShare == 0)

        let rounded = Profit(year: year, income: Money(dollars: 3), expenses: Money(dollars: 2))
        #expect(rounded.margin == 33, "33.3% rounds to 33")
    }

    @Test func noIncomeHasNoMarginOrPie() {
        let spending = Profit(year: year, income: .zero, expenses: Money(dollars: 40))
        #expect(spending.margin == nil)
        #expect(spending.expenseShare == nil)
        #expect(spending.profit == Money(dollars: -40))
    }
}
