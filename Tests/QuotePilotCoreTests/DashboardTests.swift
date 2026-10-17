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
        #expect(dashboard.waiting.filter { $0.daysLate > 0 }.map(\.number) == ["INV-0002"])
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
        // Q-0001's $1,080 less its sent $540 deposit; one-off invoices aren't accepted work.
        #expect(dashboard.toInvoiceTotal == Money(dollars: 540))
    }

    /// Each headline total is the sum of the list behind it (Quotes out counts the open quotes only).
    func expectTotalsMatchTheLists(_ dashboard: Dashboard, sourceLocation: SourceLocation = #_sourceLocation) {
        func sum(_ amounts: [Money]) -> Money { amounts.reduce(.zero, +) }
        #expect(dashboard.openQuotesTotal == sum(dashboard.openQuotes.filter { !$0.expired }.map(\.total)),
                sourceLocation: sourceLocation)
        #expect(dashboard.toInvoiceTotal == sum(dashboard.toInvoice.map(\.remaining)), sourceLocation: sourceLocation)
        #expect(dashboard.waitingTotal == sum(dashboard.waiting.map(\.owing)), sourceLocation: sourceLocation)
    }

    /// For every accepted quote, its row in Still to invoice, what its invoices still owe in Waiting
    /// to be paid and what they've been paid add up to its accepted total: each dollar is in one place.
    func expectAcceptedJobsAddUp(_ library: Library, _ dashboard: Dashboard,
                                 sourceLocation: SourceLocation = #_sourceLocation) {
        for quote in library.quotes where quote.stage == .accepted {
            let invoices = library.invoices(forQuote: quote.id)
            let ids = Set(invoices.map(\.id))
            let notInvoiced = dashboard.toInvoice.first { $0.quoteID == quote.id }?.remaining ?? .zero
            let owing = dashboard.waiting.filter { ids.contains($0.invoiceID) }.map(\.owing).reduce(.zero, +)
            let paid = invoices.map(\.paid).reduce(.zero, +)
            #expect(notInvoiced + owing + paid == quote.acceptedTotals.total, "\(quote.number)",
                    sourceLocation: sourceLocation)
        }
    }

    /// The sample business and the hand-made busy library (Q-0001 partly accepted, one-off invoices,
    /// a draft, last year's payment, an expired quote in the sample).
    @Test func totalsMatchTheirListsAndAcceptedJobsAddUp() throws {
        for library in [try busyLibrary(), try SampleLibrary.make(today: today)] {
            let dashboard = Dashboard(library: library, today: today)
            expectTotalsMatchTheLists(dashboard)
            expectAcceptedJobsAddUp(library, dashboard)
        }
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

    /// The user's example: a $5,000 quote is accepted and its $500 deposit sent and paid, so $4,500 is
    /// not invoiced yet and nothing is waiting. Sending the $4,500 final invoice moves it to Waiting.
    @Test func theUsersFiveThousandDollarJob() throws {
        var (library, quoteID, depositID) = try fiveThousandDollarJob()
        try library.markSent(invoice: depositID)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 500)), toInvoice: depositID)
        var dashboard = Dashboard(library: library, today: today)
        #expect(dashboard.toInvoiceTotal == Money(dollars: 4500))
        #expect(dashboard.waitingTotal == .zero)
        #expect(dashboard.receivedThisYear == Money(dollars: 500))

        let final = try #require(try library.completeJob(quote: quoteID, on: today))
        #expect(final.amount == Money(dollars: 4500))
        dashboard = Dashboard(library: library, today: today)
        #expect(dashboard.toInvoiceTotal == Money(dollars: 4500), "a draft final invoice is not invoiced yet")
        #expect(dashboard.waitingTotal == .zero)

        try library.markSent(invoice: final.id)
        dashboard = Dashboard(library: library, today: today)
        #expect(dashboard.toInvoiceTotal == .zero)
        #expect(dashboard.toInvoice.isEmpty)
        #expect(dashboard.waitingTotal == Money(dollars: 4500))
        #expect(dashboard.receivedThisYear == Money(dollars: 500))
        expectTotalsMatchTheLists(dashboard)
        expectAcceptedJobsAddUp(library, dashboard)
    }

    /// No dollar is in two boxes: as a $5,000 job goes from quote to paid, the four totals add up to
    /// $5,000 at every step, whichever box the money is in.
    @Test func aJobsMoneyIsInOneBoxAtATime() throws {
        var library = Library()
        let client = Client(name: "Sample Client Pty Ltd")
        library.addClient(client)
        var quote = library.newQuote(on: today, clientID: client.id)
        quote.addLine(LineItem(title: "Fit-out", rate: Money(dollars: 5000)))
        try library.update(quote)
        // Dollars in Quotes out, Not invoiced yet, Waiting to be paid and Received, after each step.
        var boxes: [[Int]] = []
        func look() {
            let dashboard = Dashboard(library: library, today: today)
            boxes.append([dashboard.openQuotesTotal, dashboard.toInvoiceTotal, dashboard.waitingTotal,
                          dashboard.receivedThisYear].map { $0.cents / 100 })
            expectTotalsMatchTheLists(dashboard)
            expectAcceptedJobsAddUp(library, dashboard)
        }
        look()
        try library.markSent(quote: quote.id)
        look()
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01"], declined: []), forQuote: quote.id)
        look()
        let deposit = try library.draftNextInvoice(forQuote: quote.id, on: today)
        look()
        try library.markSent(invoice: deposit.id)
        look()
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 2500)), toInvoice: deposit.id)
        look()
        let final = try #require(try library.completeJob(quote: quote.id, on: today))
        look()
        try library.markSent(invoice: final.id)
        look()
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 1000)), toInvoice: final.id)
        look()
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 1500)), toInvoice: final.id)
        look()
        #expect(boxes == [
            [0, 0, 0, 0],          // a draft quote
            [5000, 0, 0, 0],       // sent
            [0, 5000, 0, 0],       // accepted
            [0, 5000, 0, 0],       // the deposit drafted
            [0, 2500, 2500, 0],    // the deposit sent
            [0, 2500, 0, 2500],    // the deposit paid
            [0, 2500, 0, 2500],    // the final invoice drafted
            [0, 0, 2500, 2500],    // the final invoice sent
            [0, 0, 1500, 3500],    // part paid
            [0, 0, 0, 5000],       // paid
        ])
    }

    /// With GST charged, the job is worth $5,500 and the 10% deposit $550.
    @Test func notInvoicedYetIncludesGST() throws {
        var (library, _, depositID) = try fiveThousandDollarJob(taxed: true)
        try library.markSent(invoice: depositID)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 550)), toInvoice: depositID)
        let dashboard = Dashboard(library: library, today: today)
        #expect(dashboard.toInvoiceTotal == Money(dollars: 4950))
        expectAcceptedJobsAddUp(library, dashboard)
    }

    /// A deposit sent but not paid yet is waiting to be paid, not "not invoiced yet".
    @Test func aSentUnpaidDepositIsWaitingNotUninvoiced() throws {
        var (library, _, depositID) = try fiveThousandDollarJob()
        try library.markSent(invoice: depositID)
        let dashboard = Dashboard(library: library, today: today)
        #expect(dashboard.toInvoiceTotal == Money(dollars: 4500))
        #expect(dashboard.waitingTotal == Money(dollars: 500))
        expectAcceptedJobsAddUp(library, dashboard)
    }

    @Test func aFullyPaidJobIsOnlyReceived() throws {
        var (library, quoteID, depositID) = try fiveThousandDollarJob()
        try library.markSent(invoice: depositID)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 500)), toInvoice: depositID)
        let final = try #require(try library.completeJob(quote: quoteID, on: today))
        try library.markSent(invoice: final.id)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 4500)), toInvoice: final.id)
        let dashboard = Dashboard(library: library, today: today)
        #expect(dashboard.toInvoice.isEmpty)
        #expect(dashboard.toInvoiceTotal == .zero)
        #expect(dashboard.waitingTotal == .zero)
        #expect(dashboard.receivedThisYear == Money(dollars: 5000))
    }

    /// A draft or void invoice leaves its money in Not invoiced yet and out of Waiting; declined,
    /// expired and draft quotes are in no box, even with lines marked accepted; a draft one-off
    /// invoice isn't waiting.
    @Test func voidAndDraftInvoicesAndDeclinedExpiredAndDraftQuotes() throws {
        var (library, quoteID, depositID) = try fiveThousandDollarJob()
        var dashboard = Dashboard(library: library, today: today)
        #expect(dashboard.toInvoice.first?.invoiced == .zero, "the deposit is only drafted")
        #expect(dashboard.toInvoiceTotal == Money(dollars: 5000))
        #expect(dashboard.waiting.isEmpty)

        try library.markSent(invoice: depositID)
        try library.voidInvoice(depositID)
        let clientID = library.clients[0].id
        for (stage, issued) in [(QuoteStage.declined, today), (.sent, today.adding(days: -60)), (.draft, today)] {
            var quote = library.newQuote(on: issued, clientID: clientID)
            quote.addLine(LineItem(title: "Other work", rate: Money(dollars: 800)))
            quote.lines[0].decision = .accepted
            quote.stage = stage
            try library.update(quote)
        }
        var oneOff = library.newInvoice(on: today, clientID: clientID)
        oneOff.lines = [LineItem(title: "Extra work", rate: Money(dollars: 300))]
        try library.update(oneOff)

        dashboard = Dashboard(library: library, today: today)
        #expect(dashboard.openQuotes.filter(\.expired).count == 1)
        #expect(dashboard.openQuotesTotal == .zero)
        #expect(dashboard.toInvoice.map(\.quoteID) == [quoteID])
        #expect(dashboard.toInvoiceTotal == Money(dollars: 5000))
        #expect(dashboard.waiting.isEmpty)
        #expect(dashboard.waitingTotal == .zero)
        #expect(dashboard.receivedThisYear == .zero)
        expectTotalsMatchTheLists(dashboard)
        expectAcceptedJobsAddUp(library, dashboard)
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
