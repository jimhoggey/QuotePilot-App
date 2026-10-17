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
        // Q-0001's $1,080 less its paid $540 deposit; standalone invoices aren't accepted work.
        #expect(dashboard.acceptedWorkRemaining == Money(dollars: 540))
        #expect(dashboard.acceptedJobsOpen == 1)
        #expect(dashboard.acceptedWorkNotInvoiced == Money(dollars: 540))
    }

    /// A $5,000 job (50/50), accepted in full, with its deposit invoice drafted and cut to 10% ($500).
    func fiveThousandDollarJob(taxed: Bool = false) throws -> (library: Library, quoteID: UUID, depositID: UUID) {
        var library = Library()
        let client = Client(name: "Sample Client Pty Ltd")
        library.addClient(client)
        var quote = library.newQuote(on: today, clientID: client.id)
        quote.taxed = taxed
        quote.addLine(LineItem(title: "Fit-out", rate: Money(dollars: 5000)))
        quote.stage = .sent
        try library.update(quote)
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01"], declined: []), forQuote: quote.id)
        let deposit = try library.draftNextInvoice(forQuote: quote.id, on: today)
        let index = try #require(library.invoices.firstIndex { $0.id == deposit.id })
        library.invoices[index].depositPercent = 10
        return (library, quote.id, deposit.id)
    }

    /// The user's example: a $5,000 quote is accepted and its $500 deposit invoiced and paid, so $4,500
    /// is left on the job, none of it invoiced yet.
    @Test func leftOnAcceptedJobsIsTheAcceptedTotalLessWhatsPaid() throws {
        var (library, _, depositID) = try fiveThousandDollarJob()
        try library.markSent(invoice: depositID)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 500)), toInvoice: depositID)
        let dashboard = Dashboard(library: library, today: today)
        #expect(dashboard.acceptedWorkRemaining == Money(dollars: 4500))
        #expect(dashboard.acceptedJobsOpen == 1)
        #expect(dashboard.acceptedWorkNotInvoiced == Money(dollars: 4500))
        #expect(dashboard.acceptedWorkNotInvoiced == dashboard.toInvoice.map(\.remaining).reduce(.zero, +))
    }

    /// With GST charged, the job is worth $5,500 and the 10% deposit $550.
    @Test func leftOnAcceptedJobsIncludesGST() throws {
        var (library, _, depositID) = try fiveThousandDollarJob(taxed: true)
        try library.markSent(invoice: depositID)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 550)), toInvoice: depositID)
        let dashboard = Dashboard(library: library, today: today)
        #expect(dashboard.acceptedWorkRemaining == Money(dollars: 4950))
        #expect(dashboard.acceptedWorkNotInvoiced == Money(dollars: 4950))
    }

    /// A deposit invoiced but not paid yet is still money to come: only the part not invoiced drops.
    @Test func anInvoicedButUnpaidDepositStillCounts() throws {
        var (library, _, depositID) = try fiveThousandDollarJob()
        try library.markSent(invoice: depositID)
        let dashboard = Dashboard(library: library, today: today)
        #expect(dashboard.acceptedWorkRemaining == Money(dollars: 5000))
        #expect(dashboard.acceptedJobsOpen == 1)
        #expect(dashboard.acceptedWorkNotInvoiced == Money(dollars: 4500))
    }

    @Test func aFullyPaidJobCountsNothing() throws {
        var (library, quoteID, depositID) = try fiveThousandDollarJob()
        try library.markSent(invoice: depositID)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 500)), toInvoice: depositID)
        let final = try #require(try library.completeJob(quote: quoteID, on: today))
        #expect(final.amount == Money(dollars: 4500))
        try library.markSent(invoice: final.id)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 4500)), toInvoice: final.id)
        let dashboard = Dashboard(library: library, today: today)
        #expect(dashboard.acceptedWorkRemaining == .zero)
        #expect(dashboard.acceptedJobsOpen == 0)
        #expect(dashboard.acceptedWorkNotInvoiced == .zero)
    }

    /// Declined and expired quotes are no work to come, even with lines marked accepted, and a void
    /// invoice no longer counts as invoiced.
    @Test func declinedAndExpiredQuotesAndVoidInvoicesAreIgnored() throws {
        var (library, _, depositID) = try fiveThousandDollarJob()
        try library.markSent(invoice: depositID)
        try library.voidInvoice(depositID)
        let clientID = library.clients[0].id
        for (stage, issued) in [(QuoteStage.declined, today), (.sent, today.adding(days: -60))] {
            var quote = library.newQuote(on: issued, clientID: clientID)
            quote.addLine(LineItem(title: "Other work", rate: Money(dollars: 800)))
            quote.lines[0].decision = .accepted
            quote.stage = stage
            try library.update(quote)
        }
        let dashboard = Dashboard(library: library, today: today)
        #expect(dashboard.openQuotes.filter(\.expired).count == 1)
        #expect(dashboard.acceptedWorkRemaining == Money(dollars: 5000))
        #expect(dashboard.acceptedJobsOpen == 1)
        #expect(dashboard.acceptedWorkNotInvoiced == Money(dollars: 5000))
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

    @Test func csvFieldsWithCommasQuotesOrLineBreaksAreQuoted() {
        #expect(csvField("Plain") == "Plain")
        #expect(csvField("Smith, Jones") == "\"Smith, Jones\"")
        #expect(csvField("The \"best\" job") == "\"The \"\"best\"\" job\"")
        #expect(csvField("line one\nline two") == "\"line one\nline two\"")
        #expect(csvField("line one\r\nline two") == "\"line one\r\nline two\"")
    }
}
