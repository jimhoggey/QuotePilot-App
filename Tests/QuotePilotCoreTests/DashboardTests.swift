import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct DashboardTests {
    let today = Day(year: 2026, month: 10, day: 15)

    @Test func financialYearEdges() {
        #expect(FinancialYear(containing: Day(year: 2027, month: 6, day: 30)) == FinancialYear(startYear: 2026))
        #expect(FinancialYear(containing: Day(year: 2027, month: 7, day: 1)) == FinancialYear(startYear: 2027))
        #expect(FinancialYear(startYear: 2026).label == "FY 2026–27")
        #expect(FinancialYear(startYear: 2026).contains(Day(year: 2026, month: 7, day: 1)))
        #expect(!FinancialYear(startYear: 2026).contains(Day(year: 2026, month: 6, day: 30)))
    }

    /// A made-up, busy library on 15 Oct 2026:
    /// - Q-0001 accepted 50/50 ($1,080). Deposit INV-0001 ($540) issued 15 Sep, paid 20 Sep.
    /// - INV-0002 $300, issued 15 Sep, due 29 Sep, $100 paid 10 Oct: 16 days late, $200 owing.
    /// - INV-0003 $90, issued 14 Oct, due 28 Oct, unpaid.
    /// - INV-0004 $500 draft (doesn't count).
    /// - INV-0005 $60, issued and paid 20 Jun 2026 (last financial year).
    /// - Q-0002 sent for $250, valid until 14 Nov.
    func busyLibrary() throws -> Library {
        var (library, quoteID) = Fixture.acceptedLibrary()
        let clientID = library.clients[0].id
        let deposit = try library.draftNextInvoice(forQuote: quoteID, on: Day(year: 2026, month: 9, day: 15))
        try library.markSent(invoice: deposit.id)
        try library.recordPayment(Payment(date: Day(year: 2026, month: 9, day: 20), amount: Money(dollars: 540)),
                                  toInvoice: deposit.id)

        func standalone(_ dollars: Int, issued: Day, send: Bool = true) throws -> Invoice {
            var invoice = library.newInvoice(on: issued, clientID: clientID)
            invoice.lines = [LineItem(title: "Extra work", rate: Money(dollars: dollars))]
            try library.update(invoice)
            if send { try library.markSent(invoice: invoice.id) }
            return invoice
        }

        let late = try standalone(300, issued: Day(year: 2026, month: 9, day: 15))
        try library.recordPayment(Payment(date: Day(year: 2026, month: 10, day: 10), amount: Money(dollars: 100)),
                                  toInvoice: late.id)
        _ = try standalone(90, issued: Day(year: 2026, month: 10, day: 14))
        _ = try standalone(500, issued: today, send: false)
        let old = try standalone(60, issued: Day(year: 2026, month: 6, day: 20))
        try library.recordPayment(Payment(date: Day(year: 2026, month: 6, day: 20), amount: Money(dollars: 60)),
                                  toInvoice: old.id)

        var second = library.newQuote(on: today, clientID: clientID)
        second.addLine(LineItem(title: "Phase 2 planning", rate: Money(dollars: 250)))
        try library.update(second)
        try library.markSent(quote: second.id)
        return library
    }

    @Test func waitingToBePaidPutsOverdueFirst() throws {
        let dashboard = Dashboard(library: try busyLibrary(), today: today)
        #expect(dashboard.waiting.map(\.number) == ["INV-0002", "INV-0003"])
        #expect(dashboard.waiting[0].daysLate == 16)
        #expect(dashboard.waiting[0].owing == Money(dollars: 200))
        #expect(dashboard.waiting[1].daysLate == 0)
        #expect(dashboard.waitingTotal == Money(dollars: 290))
        #expect(dashboard.overdueTotal == Money(dollars: 200))
    }

    @Test func receivedAndInvoicedFollowTheCalendar() throws {
        let dashboard = Dashboard(library: try busyLibrary(), today: today)
        #expect(dashboard.financialYear.label == "FY 2026–27")
        #expect(dashboard.receivedThisMonth == Money(dollars: 100))
        #expect(dashboard.receivedThisYear == Money(dollars: 640))
        #expect(dashboard.invoicedThisYear == Money(dollars: 930))
    }

    @Test func quotesAndJobsStillToInvoice() throws {
        let dashboard = Dashboard(library: try busyLibrary(), today: today)
        #expect(dashboard.openQuotes.map(\.number) == ["Q-0002"])
        #expect(dashboard.openQuotesTotal == Money(dollars: 250))
        #expect(dashboard.toInvoice.map(\.number) == ["Q-0001"])
        #expect(dashboard.toInvoice[0].remaining == Money(dollars: 540))
    }

    @Test func expiredQuotesAreShownButNotTotalled() throws {
        let dashboard = Dashboard(library: try busyLibrary(), today: Day(year: 2026, month: 11, day: 20))
        #expect(dashboard.openQuotes.first?.expired == true)
        #expect(dashboard.openQuotesTotal == .zero)
    }

    @Test func taxTimeCSVListsThisYearsPayments() throws {
        let csv = try busyLibrary().paymentsCSV(for: FinancialYear(startYear: 2026))
        #expect(csv == """
        Date,Client,Invoice,Amount,Method,Note
        2026-09-20,Sample Client Pty Ltd,INV-0001,540.00,Bank transfer,
        2026-10-10,Sample Client Pty Ltd,INV-0002,100.00,Bank transfer,

        """)
    }

    @Test func csvFieldsWithCommasOrQuotesAreQuoted() {
        #expect(csvField("Plain") == "Plain")
        #expect(csvField("Smith, Jones") == "\"Smith, Jones\"")
        #expect(csvField("The \"best\" job") == "\"The \"\"best\"\" job\"")
    }
}
