import Foundation
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// The money records kept in Records after every save. Made-up data; every folder is temporary.
@MainActor
@Suite struct MoneyRecordsTests {
    /// The fixture's deposit invoice INV-0001 ($900), sent on 20 June 2026, last financial year. Today
    /// is 15 October 2026.
    func sentDepositModel() throws -> (model: AppModel, invoiceID: UUID) {
        var (library, _) = try UIFixture.invoicedLibrary()
        let id = library.invoices[0].id
        try library.markSent(invoice: id, at: Day(year: 2026, month: 6, day: 20).date())
        return (try UIFixture.model(library), id)
    }

    func entry(_ id: UUID, _ amount: String, on day: Day = UIFixture.today) -> PaymentEntry {
        PaymentEntry(invoiceID: id, date: day, amount: amount, method: .bankTransfer, note: "")
    }

    func record(_ model: AppModel, _ startYear: Int) throws -> String {
        let name = AppModel.moneyRecordFileName(for: FinancialYear(startYear: startYear))
        return try String(contentsOf: model.recordsFolder.appendingPathComponent(name), encoding: .utf8)
    }

    @Test func recordingAPaymentRewritesThatYearsFile() throws {
        let (model, id) = try sentDepositModel()
        #expect(model.recordPayment(entry(id, "900", on: Day(year: 2026, month: 6, day: 30))))
        let lastYear = try record(model, 2025)
        #expect(lastYear.contains("2026-06-20,Invoice sent,INV-0001,Q-0001"))
        #expect(lastYear.contains(#"2026-06-30,Payment received,INV-0001,Q-0001,Sample Client Pty Ltd,"Design, Build",900.00,0.00,900.00,Bank transfer,0.00,"#))
        // This year's file is kept too, with nothing in it yet.
        #expect(try record(model, 2026) == Library.moneyRecordHeader + "\n")
    }

    @Test func removingAYearsLastPaymentRewritesThatYear() throws {
        let (model, id) = try sentDepositModel()
        #expect(model.recordPayment(entry(id, "900", on: Day(year: 2026, month: 6, day: 30))))
        let paymentID = try #require(model.library.invoice(id)?.payments.first?.id)
        #expect(model.change("Couldn't remove the payment") { try $0.removePayment(paymentID, fromInvoice: id) })
        #expect(!(try record(model, 2025)).contains("Payment received"))
    }

    @Test func aRecordThatCantBeWrittenDoesntStopTheSave() throws {
        let (model, id) = try sentDepositModel()
        // A file where the Records folder should be, so no record can be written.
        try FileManager.default.createDirectory(at: model.sentFolder, withIntermediateDirectories: true)
        try Data().write(to: model.recordsFolder)

        #expect(model.recordPayment(entry(id, "400")))
        #expect(model.library.invoice(id)?.paid == Money(dollars: 400))
        #expect(model.message == nil)
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Expected the saved library")
            return
        }
        #expect(saved.invoice(id)?.paid == Money(dollars: 400))
        func failures() -> Int {
            model.library.activity.filter { $0.message.hasPrefix("Couldn't update the money records") }.count
        }
        #expect(failures() == 1)

        // Said once, not at every save.
        #expect(model.recordPayment(entry(id, "100")))
        #expect(failures() == 1)
    }

    @Test func showMoneyRecordsOpensTheRecordsFolder() throws {
        let (model, _) = try sentDepositModel()
        var opened: [URL] = []
        model.openInFinder = { opened.append($0) }
        model.showMoneyRecords()
        #expect(model.recordsFolder == model.sentFolder.appendingPathComponent("Records", isDirectory: true))
        #expect(opened == [model.recordsFolder])
        // Made, with the records written, even before any change.
        #expect(try record(model, 2025).contains("Invoice sent,INV-0001"))
        #expect(AppModel.moneyRecordFileName(for: FinancialYear(startYear: 2026)) == "Money record FY 2026-27.csv")
    }
}
