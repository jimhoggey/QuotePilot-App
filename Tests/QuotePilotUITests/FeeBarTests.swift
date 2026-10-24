import AppKit
import Foundation
import QuotePilotCore
import SwiftUI
import Testing
@testable import QuotePilotUI

/// The red Quote Pilot fee bar and the lock: what it says, I've paid, and what stays open while
/// locked. Made-up amounts; every folder is temporary.
@MainActor
@Suite struct FeeBarTests {
    /// A model on `today` with $750 received on `paidOn` (one sent one-off invoice) and a draft quote,
    /// the fee counting from September 2026.
    func model(paidOn: Day = Day(year: 2026, month: 9, day: 20), today: Day = UIFixture.today) throws -> AppModel {
        var library = Library()
        library.brand.appFee = AppFee(startMonth: CalendarMonth(year: 2026, month: 9))
        let client = Client(name: "Sample Client Pty Ltd", email: "accounts@example.com")
        library.addClient(client)
        var invoice = library.newInvoice(on: paidOn, clientID: client.id)
        invoice.lines = [LineItem(title: "Sample work", rate: Money(dollars: 750))]
        try library.update(invoice)
        try library.markSent(invoice: invoice.id)
        try library.recordPayment(Payment(date: paidOn, amount: Money(dollars: 750)), toInvoice: invoice.id)
        var quote = library.newQuote(on: paidOn, clientID: client.id)
        quote.addLine(LineItem(title: "Sample design", rate: Money(dollars: 100)))
        try library.update(quote)
        let store = LibraryStore(folder: UIFixture.makeFolder())
        try store.save(library)
        let model = AppModel(store: store, now: { today.date() }, mail: FakeMail(), sentFolder: UIFixture.makeFolder())
        model.updates = UpdateFixture.offline()
        return model
    }

    /// 15 Oct 2026, with September's $22.50 unpaid since 1 Oct: locked.
    func lockedModel() throws -> AppModel { try model() }

    @Test func nothingDueShowsNoBarEvenWithMoneyReceived() throws {
        let model = try model(paidOn: Day(year: 2026, month: 10, day: 2))
        #expect(model.appFeeState == .running(month: CalendarMonth(year: 2026, month: 10),
                                              fee: Money(dollars: 22, cents: 50), received: Money(dollars: 750)))
        #expect(model.feeBarText == nil, "nothing is owed until 1 Nov")
        #expect(model.appFeeState?.monthToPay == nil, "no I've paid")
        #expect(!model.isLocked)
    }

    @Test func aClosedMonthIsDueUntilThe4th() throws {
        let model = try model(today: Day(year: 2026, month: 10, day: 4))
        #expect(model.feeBarText == "September fee $22.50 is due.")
        #expect(model.appFeeState?.monthToPay == CalendarMonth(year: 2026, month: 9))
        #expect(!model.isLocked)
        #expect(model.canEdit)
    }

    @Test func fromThe5thItsLocked() throws {
        let model = try model(today: Day(year: 2026, month: 10, day: 5))
        #expect(model.feeBarText == "Quote Pilot is locked until the September fee ($22.50) is paid. You can still view, back up and export.")
        #expect(model.isLocked)
        #expect(!model.canEdit)
    }

    @Test func iHavePaidUnlocksWithNoQuestionAndSaysSoInActivity() throws {
        let model = try lockedModel()
        model.markFeePaid()
        #expect(model.message == nil, "no confirm box")
        #expect(!model.isLocked)
        #expect(model.library.brand.appFee.paidMonths["2026-09"] == AppFeePaid(on: UIFixture.today, amount: Money(dollars: 22, cents: 50)))
        #expect(model.library.activity.first?.message == "Marked the September 2026 Quote Pilot fee as paid ($22.50)")
        // Nothing received this month yet: it's free, so no bar.
        #expect(model.feeBarText == nil)
    }

    @Test func lockedCommandsRefuse() throws {
        let model = try lockedModel()
        let quoteID = try #require(model.library.quotes.first?.id)
        let invoiceID = try #require(model.library.invoices.first?.id)
        #expect(!model.canEdit)
        model.openQuote(quoteID)
        #expect(model.sendableDocument == nil, "Send by Mail… is greyed out")
        #expect(model.resetNumbersBlockedReason != nil)
        model.selectedClientID = model.library.clients.first?.id
        #expect(!model.canDeleteClient)
        let pdf = FileManager.default.temporaryDirectory.appendingPathComponent("reply-\(UUID().uuidString).pdf")
        try Data("%PDF-1.4".utf8).write(to: pdf)
        #expect(!model.dropped([pdf]), "Read Reply by drop")
        model.readReturnedQuote(at: pdf)
        #expect(model.dialog == nil && model.message == nil)

        // Anything that gets past the greyed-out controls is refused, with nothing changed.
        let before = model.library.activity.count
        model.newQuote()
        #expect(model.library.quotes.count == 1)
        #expect(model.message?.text.hasPrefix("Quote Pilot is locked until the September fee ($22.50) is paid.") == true)
        model.message = nil
        model.deleteDraftQuote(quoteID)
        model.message.map { model.respond($0.choices[0]) }
        #expect(model.library.quote(quoteID) != nil)
        model.message = nil
        #expect(!model.recordPayment(PaymentEntry(invoiceID: invoiceID, date: UIFixture.today, amount: "1",
                                                  method: .bankTransfer, note: "")))
        model.message = nil
        model.newClient()
        #expect(model.library.clients.count == 1)
        #expect(model.library.activity.count == before)
    }

    @Test func viewingAndExportingStillWork() throws {
        let model = try lockedModel()
        let quoteID = try #require(model.library.quotes.first?.id)
        model.go(to: .invoices)
        #expect(model.section == .invoices)
        model.openQuote(quoteID)
        #expect(model.openQuoteID == quoteID)
        #expect(model.canExportPDF)
        model.exportPDF()
        #expect(model.pendingExport?.contentType == .pdf)
        model.pendingExport = nil
        #expect(model.canBackUp)
        model.exportBackupCopy()
        #expect(model.pendingExport?.contentType == .json)
        model.pendingExport = nil
        model.exportPayments(for: FinancialYear(startYear: 2026))
        #expect(model.pendingExport?.contentType == .commaSeparatedText)
        model.pendingExport = nil
        var opened: [URL] = []
        model.openInFinder = { opened.append($0) }
        model.showMoneyRecords()
        #expect(opened == [model.recordsFolder])
        // Restore Backup… works, and says so in Activity.
        let backup = try #require(model.latestBackup)
        model.restore(from: backup)
        #expect(model.message == nil)
        #expect(model.library.activity.first?.message.hasPrefix("Restored the") == true)
    }

    @Test func settingsStaysOpenButOnlyTheFeeChanges() throws {
        let model = try lockedModel()
        var brand = model.library.brand
        brand.businessName = "Sample Renamed"
        brand.appFee.percent = 2
        model.updateBrand(brand)
        #expect(model.message == nil)
        #expect(model.library.brand.appFee.percent == 2)
        #expect(model.library.brand.businessName == "", "only Settings is open while locked")
    }

    @Test func untickingTheBoxRemovesTheBarAndTheLock() throws {
        let model = try lockedModel()
        var brand = model.library.brand
        brand.appFee.calculates = false
        model.updateBrand(brand)
        #expect(model.feeBarText == nil)
        #expect(!model.isLocked)
        #expect(model.canEdit)
    }

    @Test func tickingItAgainCountsFromThisMonth() throws {
        let model = try lockedModel()
        var brand = model.library.brand
        brand.appFee.calculates = false
        model.updateBrand(brand)
        brand.appFee.calculates = true
        model.updateBrand(brand)
        #expect(model.library.brand.appFee.startMonth == CalendarMonth(year: 2026, month: 10))
        #expect(!model.isLocked, "September no longer counts")
        // October has nothing received yet, so it's free and there's no bar.
        #expect(model.feeBarText == nil)
    }

    /// One slim line across the smallest window, on top of the update banner when both show, with
    /// the Dashboard still fitting under the two.
    @Test func theBarIsOneSlimLineAndTheDashboardStillFits() throws {
        let model = try lockedModel()
        _ = NSApplication.shared
        let bar = FeeBar(text: try #require(model.feeBarText), canPay: true) {}
        let size = NSHostingView(rootView: bar).fittingSize
        #expect(size.height == FeeBar.height)
        #expect(size.width <= 980 - 8, "one line across the window")
        let taken = FeeBar.height + UpdateBanner.height + UpdateBanner.gapBelow - 4
        let area = CGSize(width: 778, height: 620 - 28 - 66 - 26 - 8 - taken)
        let needed = NSHostingView(rootView: DashboardView(model: model).frame(width: area.width)).fittingSize
        #expect(needed.height <= area.height, "the Dashboard needs \(needed.height) of \(area.height)")
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 980, height: 620), name: "fee-bar-locked")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
