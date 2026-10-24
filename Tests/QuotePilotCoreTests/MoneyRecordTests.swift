import Foundation
import Testing
@testable import QuotePilotCore

/// The money record for a tax accountant. Made-up data; times are read in GMT so no day moves.
@Suite struct MoneyRecordTests {
    let header = Library.moneyRecordHeader

    static func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Day(year: year, month: month, day: day).date(in: .gmt)
    }

    /// Sample Client Pty Ltd's INV-0001, Design $400 and Build $600 with no title, sent on `sent`.
    func library(taxed: Bool = false, sent: Day = Day(year: 2026, month: 7, day: 1)) throws -> (library: Library, invoiceID: UUID) {
        var library = Library()
        let client = Client(name: "Sample Client Pty Ltd")
        library.addClient(client)
        var invoice = library.newInvoice(on: sent, clientID: client.id)
        invoice.lines = [LineItem(title: "Design", rate: Money(dollars: 400)),
                         LineItem(title: "Build", rate: Money(dollars: 600))]
        invoice.taxed = taxed
        try library.update(invoice)
        try library.markSent(invoice: invoice.id, at: sent.date(in: .gmt))
        return (library, invoice.id)
    }

    func csv(_ library: Library, _ startYear: Int = 2026) -> String {
        library.moneyRecordCSV(for: FinancialYear(startYear: startYear), timeZone: .gmt)
    }

    func rows(_ library: Library, _ startYear: Int = 2026) -> [String] {
        csv(library, startYear).split(separator: "\n").map(String.init)
    }

    @Test func aSentInvoiceWithoutGSTIsOneRow() throws {
        let (library, _) = try library()
        #expect(csv(library) == """
        \(header)
        2026-07-01,Income,Invoice sent,INV-0001,,Sample Client Pty Ltd,"Design, Build",,1000.00,0.00,1000.00,,1000.00,

        """)
    }

    @Test func paymentsSayWhatIsStillOwing() throws {
        var (library, id) = try library()
        try library.recordPayment(Payment(date: Day(year: 2026, month: 7, day: 10), amount: Money(dollars: 400),
                                          note: "Part payment"), toInvoice: id)
        try library.recordPayment(Payment(date: Day(year: 2026, month: 8, day: 2), amount: Money(dollars: 600),
                                          method: .cash), toInvoice: id)
        try library.markReceiptSent(invoice: id, at: Self.noon(2026, 8, 3))
        #expect(csv(library) == """
        \(header)
        2026-07-01,Income,Invoice sent,INV-0001,,Sample Client Pty Ltd,"Design, Build",,1000.00,0.00,1000.00,,1000.00,
        2026-07-10,Income,Payment received,INV-0001,,Sample Client Pty Ltd,"Design, Build",,400.00,0.00,400.00,Bank transfer,600.00,Part payment
        2026-08-02,Income,Payment received,INV-0001,,Sample Client Pty Ltd,"Design, Build",,600.00,0.00,600.00,Cash,0.00,
        2026-08-03,Income,Receipt sent,INV-0001,,Sample Client Pty Ltd,"Design, Build",,,,,,0.00,

        """)
    }

    @Test func gstIsSplitOutWhenTheInvoiceHasIt() throws {
        var (library, id) = try library(taxed: true)
        try library.recordPayment(Payment(date: Day(year: 2026, month: 7, day: 10), amount: Money(dollars: 550)),
                                  toInvoice: id)
        let rows = rows(library)
        #expect(rows[1] == #"2026-07-01,Income,Invoice sent,INV-0001,,Sample Client Pty Ltd,"Design, Build",,1000.00,100.00,1100.00,,1100.00,"#)
        #expect(rows[2] == #"2026-07-10,Income,Payment received,INV-0001,,Sample Client Pty Ltd,"Design, Build",,500.00,50.00,550.00,Bank transfer,550.00,"#)
    }

    @Test func theYearEndsOn30June() throws {
        var (library, id) = try library(sent: Day(year: 2027, month: 6, day: 30))
        try library.recordPayment(Payment(date: Day(year: 2027, month: 7, day: 1), amount: Money(dollars: 1000)),
                                  toInvoice: id)
        #expect(rows(library, 2026).dropFirst() == [
            #"2027-06-30,Income,Invoice sent,INV-0001,,Sample Client Pty Ltd,"Design, Build",,1000.00,0.00,1000.00,,1000.00,"#,
        ])
        #expect(rows(library, 2027).dropFirst() == [
            #"2027-07-01,Income,Payment received,INV-0001,,Sample Client Pty Ltd,"Design, Build",,1000.00,0.00,1000.00,Bank transfer,0.00,"#,
        ])
        #expect(library.moneyRecordYears(timeZone: .gmt) == [FinancialYear(startYear: 2026), FinancialYear(startYear: 2027)])
    }

    @Test func aYearWithNothingInItIsJustTheHeader() throws {
        #expect(Library().moneyRecordCSV(for: FinancialYear(startYear: 2026)) == header + "\n")
        #expect(Library().moneyRecordYears().isEmpty)
        #expect(csv(try library().library, 2025) == header + "\n")
    }

    @Test func aDepositShowsItsQuoteTitleAndShare() throws {
        var (library, quoteID) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: quoteID, on: Day(year: 2026, month: 9, day: 15))
        try library.markSent(invoice: deposit.id, at: Self.noon(2026, 9, 15))
        #expect(rows(library).dropFirst() == [
            #"2026-09-15,Income,Invoice sent,INV-0001,Q-0001,Sample Client Pty Ltd,"Booking app, phase 1",,540.00,0.00,540.00,,540.00,Deposit (50%)"#,
        ])
    }

    @Test func draftsAndVoidedInvoicesLeaveNoRows() throws {
        var (library, id) = try library()
        _ = library.newInvoice(on: Day(year: 2026, month: 7, day: 2))
        try library.voidInvoice(id)
        #expect(csv(library) == header + "\n")
    }

    @Test func typedTextCantRunAsAFormula() throws {
        var (library, id) = try library()
        try library.recordPayment(Payment(date: Day(year: 2026, month: 7, day: 10), amount: Money(dollars: 100),
                                          note: "=1+1"), toInvoice: id)
        #expect(rows(library)[2].hasSuffix(",900.00,'=1+1"))
    }

    // MARK: Expenses and the fee

    func day(_ year: Int, _ month: Int, _ day: Int) -> Day { Day(year: year, month: month, day: day) }

    @Test func anExpenseIsAnExpenseRowAfterThatDaysIncome() throws {
        var (library, _) = try library()
        try library.addExpense(Expense(date: day(2026, 7, 1), supplier: "Sample Supplies", description: "Laptop stand",
                                       category: "Equipment", total: Money(dollars: 110), gst: Money(dollars: 10),
                                       method: .card, note: "Receipt in folder"))
        #expect(rows(library).dropFirst() == [
            #"2026-07-01,Income,Invoice sent,INV-0001,,Sample Client Pty Ltd,"Design, Build",,1000.00,0.00,1000.00,,1000.00,"#,
            "2026-07-01,Expense,Expense paid,,,Sample Supplies,Laptop stand,Equipment,100.00,10.00,110.00,Card,,Receipt in folder",
        ])
    }

    @Test func aPaidQuotePilotFeeIsASoftwareExpense() {
        var library = Library()
        library.brand.appFee.paidMonths["2026-09"] = AppFeePaid(on: day(2026, 10, 2), amount: Money(cents: 1650))
        #expect(rows(library).dropFirst() == [
            "2026-10-02,Expense,Quote Pilot fee paid,,,Quote Pilot,Quote Pilot fee for September 2026,Software and subscriptions,16.50,0.00,16.50,,,",
        ])
    }

    /// An expense on 30 June is last year's and one on 1 July this year's; June's fee, paid in July,
    /// is in the year it was paid.
    @Test func expensesAndFeesFollowTheFinancialYear() throws {
        var library = Library()
        try library.addExpense(Expense(date: day(2027, 6, 30), supplier: "June Supplier", total: Money(dollars: 10)))
        try library.addExpense(Expense(date: day(2027, 7, 1), supplier: "July Supplier", total: Money(dollars: 20)))
        library.brand.appFee.paidMonths["2027-06"] = AppFeePaid(on: day(2027, 7, 2), amount: Money(dollars: 3))
        #expect(rows(library, 2026).dropFirst().map { $0.prefix(10) } == ["2027-06-30"])
        #expect(rows(library, 2027).dropFirst().map { $0.prefix(10) } == ["2027-07-01", "2027-07-02"])
        #expect(library.moneyRecordYears(timeZone: .gmt) == [FinancialYear(startYear: 2026), FinancialYear(startYear: 2027)])
    }

    // MARK: The summary

    /// A small made-up year, FY 2026–27: INV-0001 for $1,100 with $100 GST, paid $550 in July and $220
    /// on 30 June, and $330 on 1 July 2027 (next year); three expenses and September's fee in the
    /// year, and one expense the day after it ends.
    func summaryLibrary() throws -> Library {
        var (library, id) = try library(taxed: true)
        for (date, dollars) in [(day(2026, 7, 10), 550), (day(2027, 6, 30), 220), (day(2027, 7, 1), 330)] {
            try library.recordPayment(Payment(date: date, amount: Money(dollars: dollars)), toInvoice: id)
        }
        try library.addExpense(Expense(date: day(2026, 8, 20), supplier: "Sample Supplies", category: "Equipment",
                                       total: Money(dollars: 110), gst: Money(dollars: 10)))
        try library.addExpense(Expense(date: day(2026, 9, 1), supplier: "Sample Course", category: "Training",
                                       total: Money(dollars: 50)))
        try library.addExpense(Expense(date: day(2027, 6, 30), supplier: "Sample Taxi", category: "Travel",
                                       total: Money(dollars: 22), gst: Money(dollars: 2)))
        try library.addExpense(Expense(date: day(2027, 7, 1), supplier: "Next Year", category: "Office",
                                       total: Money(dollars: 99), gst: Money(dollars: 9)))
        library.brand.appFee.paidMonths["2026-09"] = AppFeePaid(on: day(2026, 10, 2), amount: Money(cents: 1650))
        return library
    }

    @Test func theSummaryAddsUpASmallYear() throws {
        let library = try summaryLibrary()
        let csv = library.summaryCSV(for: FinancialYear(startYear: 2026), today: day(2027, 8, 15), timeZone: .gmt)
        #expect(csv == """
        Item,Amount
        Financial year,FY 2026–27 (\(day(2026, 7, 1).short) to \(day(2027, 6, 30).short))
        Income received (GST included),770.00
        Income received ex GST,700.00
        GST collected,70.00
        Invoiced in the year (GST included),1100.00
        Owing at \(day(2027, 6, 30).short),330.00
        Expenses: Equipment (ex GST),100.00
        Expenses: Software and subscriptions (ex GST),16.50
        Expenses: Travel (ex GST),20.00
        Expenses: Training (ex GST),50.00
        Total expenses ex GST,186.50
        GST paid,12.00
        Total expenses (GST included),198.50
        Net (income ex GST less expenses ex GST),513.50
        Net GST (GST collected less GST paid),58.00
        Invoices sent,1
        Expenses,4
        Prepared by Quote Pilot on \(day(2027, 8, 15).short). Figures are from Quote Pilot's records; check with your accountant.,

        """)
    }

    @Test func theYearNotOverYetSaysWhatsOwingNow() throws {
        let library = try summaryLibrary()
        let today = day(2026, 10, 15)
        let rows = library.summaryCSV(for: FinancialYear(startYear: 2026), today: today, timeZone: .gmt)
            .split(separator: "\n").map(String.init)
        // Only July's $550 had been paid by 15 October.
        #expect(rows.contains("Owing now (\(today.short)),550.00"))
        // The next year has the last payment and the Office expense, and nothing owing.
        let next = library.summaryCSV(for: FinancialYear(startYear: 2027), today: day(2028, 7, 1), timeZone: .gmt)
            .split(separator: "\n").map(String.init)
        #expect(next.contains("Income received (GST included),330.00"))
        #expect(next.contains("Owing at \(day(2028, 6, 30).short),0.00"))
        #expect(next.contains("Expenses: Office (ex GST),90.00"))
        #expect(next.contains("Invoices sent,0"))
    }

    @Test func anEmptyYearsSummaryIsAllNoughts() {
        let rows = Library().summaryCSV(for: FinancialYear(startYear: 2026), today: day(2026, 10, 15))
            .split(separator: "\n").map(String.init)
        #expect(rows.first == "Item,Amount")
        #expect(rows.contains("Net (income ex GST less expenses ex GST),0.00"))
        #expect(rows.contains("Expenses,0"))
        #expect(!rows.contains { $0.hasPrefix("Expenses: ") })
    }
}
