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
        2026-07-01,Invoice sent,INV-0001,,Sample Client Pty Ltd,"Design, Build",1000.00,0.00,1000.00,,1000.00,

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
        2026-07-01,Invoice sent,INV-0001,,Sample Client Pty Ltd,"Design, Build",1000.00,0.00,1000.00,,1000.00,
        2026-07-10,Payment received,INV-0001,,Sample Client Pty Ltd,"Design, Build",400.00,0.00,400.00,Bank transfer,600.00,Part payment
        2026-08-02,Payment received,INV-0001,,Sample Client Pty Ltd,"Design, Build",600.00,0.00,600.00,Cash,0.00,
        2026-08-03,Receipt sent,INV-0001,,Sample Client Pty Ltd,"Design, Build",,,,,0.00,

        """)
    }

    @Test func gstIsSplitOutWhenTheInvoiceHasIt() throws {
        var (library, id) = try library(taxed: true)
        try library.recordPayment(Payment(date: Day(year: 2026, month: 7, day: 10), amount: Money(dollars: 550)),
                                  toInvoice: id)
        let rows = rows(library)
        #expect(rows[1] == #"2026-07-01,Invoice sent,INV-0001,,Sample Client Pty Ltd,"Design, Build",1000.00,100.00,1100.00,,1100.00,"#)
        #expect(rows[2] == #"2026-07-10,Payment received,INV-0001,,Sample Client Pty Ltd,"Design, Build",500.00,50.00,550.00,Bank transfer,550.00,"#)
    }

    @Test func theYearEndsOn30June() throws {
        var (library, id) = try library(sent: Day(year: 2027, month: 6, day: 30))
        try library.recordPayment(Payment(date: Day(year: 2027, month: 7, day: 1), amount: Money(dollars: 1000)),
                                  toInvoice: id)
        #expect(rows(library, 2026).dropFirst() == [
            #"2027-06-30,Invoice sent,INV-0001,,Sample Client Pty Ltd,"Design, Build",1000.00,0.00,1000.00,,1000.00,"#,
        ])
        #expect(rows(library, 2027).dropFirst() == [
            #"2027-07-01,Payment received,INV-0001,,Sample Client Pty Ltd,"Design, Build",1000.00,0.00,1000.00,Bank transfer,0.00,"#,
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
            #"2026-09-15,Invoice sent,INV-0001,Q-0001,Sample Client Pty Ltd,"Booking app, phase 1",540.00,0.00,540.00,,540.00,Deposit (50%)"#,
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
}
