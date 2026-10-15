import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// The remembered hourly rate on the screens: the line table fills it in, the Brand field takes it.
/// The rule itself (`LineItem.withHourlyRate`) is tested in QuotePilotCoreTests.
@MainActor
@Suite struct HourlyRateScreenTests {
    let hourly = Money(dollars: 95)

    /// A model with the hourly rate set and one draft quote whose single line is in units at $0.
    func modelWithADraft() throws -> (model: AppModel, quoteID: UUID) {
        var library = Library()
        library.brand.businessName = "Sample Studio"
        library.brand.hourlyRate = hourly
        var quote = library.newQuote(on: UIFixture.today)
        quote.addLine(LineItem(title: "Planning", rate: .zero))
        try library.update(quote)
        return (try UIFixture.model(library), quote.id)
    }

    // MARK: Add Line and the unit picker, through the line table's own store

    @Test func theUnitPickerSwitchingToHoursFillsTheRateIn() throws {
        let (model, quoteID) = try modelWithADraft()
        #expect(!model.billingLocked(forQuote: quoteID))
        let lines = model.library.quote(quoteID)!.lines
        var edited = lines[0]
        edited.unit = .hours
        let stored = try #require(lines.replacing(edited, id: edited.id, hourlyRate: model.library.brand.hourlyRate,
                                                  editable: !model.billingLocked(forQuote: quoteID)))
        #expect(stored[0].unit == .hours)
        #expect(stored[0].rate == hourly)
        #expect(stored[0].title == "Planning")
        #expect(stored.count == lines.count)
    }

    @Test func aTypedRateSurvivesTheUnitPicker() throws {
        let (model, quoteID) = try modelWithADraft()
        var line = model.library.quote(quoteID)!.lines[0]
        line.rate = Money(dollars: 120)
        var edited = line
        edited.unit = .hours
        let stored = try #require([line].replacing(edited, id: line.id, hourlyRate: hourly, editable: true))
        #expect(stored[0].rate == Money(dollars: 120))
    }

    @Test func noHourlyRateMeansTheUnitPickerChangesNothingElse() throws {
        let (model, quoteID) = try modelWithADraft()
        var brand = model.library.brand
        brand.hourlyRate = nil
        model.updateBrand(brand)
        let lines = model.library.quote(quoteID)!.lines
        var edited = lines[0]
        edited.unit = .hours
        let stored = try #require(lines.replacing(edited, id: edited.id, hourlyRate: model.library.brand.hourlyRate,
                                                  editable: true))
        #expect(stored == [edited])
        #expect(stored[0].rate == .zero)
    }

    @Test func aLineThatIsGoneIsNotStored() throws {
        let (model, quoteID) = try modelWithADraft()
        let lines = model.library.quote(quoteID)!.lines
        #expect(lines.replacing(lines[0], id: UUID(), hourlyRate: hourly, editable: true) == nil)
    }

    /// A quote with invoices is locked: its lines show but don't edit, and the rate is never filled in.
    @Test func aQuoteLockedByInvoicesKeepsItsLines() throws {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let model = try UIFixture.model(library)
        var brand = model.library.brand
        brand.hourlyRate = hourly
        model.updateBrand(brand)
        #expect(model.billingLocked(forQuote: quoteID))

        let lines = model.library.quote(quoteID)!.lines
        var edited = lines[0]
        edited.unit = .hours
        edited.rate = .zero
        let stored = try #require(lines.replacing(edited, id: edited.id, hourlyRate: model.library.brand.hourlyRate,
                                                  editable: !model.billingLocked(forQuote: quoteID)))
        #expect(stored[0].rate == .zero)
    }

    /// Add Line on a quote, as the editor does it: `addLine(.blank(hourlyRate:))`.
    @Test func addLineOnAQuoteStartsInHoursAtTheHourlyRate() throws {
        let (model, quoteID) = try modelWithADraft()
        var quote = model.library.quote(quoteID)!
        quote.addLine(.blank(hourlyRate: model.library.brand.hourlyRate))
        let added = try #require(quote.lines.last)
        #expect(added.unit == .hours)
        #expect(added.rate == hourly)
        #expect(added.title.isEmpty)
        #expect(added.code == "02")
        // The line that was there is not touched.
        #expect(quote.lines[0].unit == .units)
        #expect(quote.lines[0].rate == .zero)
    }

    @Test func addLineOnAQuoteWithNoHourlyRateStartsInUnitsAtNothing() throws {
        let (model, quoteID) = try modelWithADraft()
        var brand = model.library.brand
        brand.hourlyRate = nil
        model.updateBrand(brand)
        var quote = model.library.quote(quoteID)!
        quote.addLine(.blank(hourlyRate: model.library.brand.hourlyRate))
        let added = try #require(quote.lines.last)
        #expect(added.unit == .units)
        #expect(added.rate == .zero)
        #expect(added.code == "02")
    }

    /// Add Line on an invoice, as the editor does it: `lines.append(.blank(hourlyRate:))`.
    @Test func addLineOnAnInvoiceStartsInHoursAtTheHourlyRate() throws {
        var library = Library()
        library.brand.hourlyRate = hourly
        var invoice = library.newInvoice(on: UIFixture.today)
        invoice.lines.append(.blank(hourlyRate: library.brand.hourlyRate))
        let added = try #require(invoice.lines.last)
        #expect(added.unit == .hours)
        #expect(added.rate == hourly)
        #expect(added.title.isEmpty)
        try library.update(invoice)
        #expect(library.invoice(invoice.id)?.lines.last?.rate == hourly)
    }

    @Test func addLineOnAnInvoiceWithNoHourlyRateStartsInUnitsAtNothing() throws {
        var library = Library()
        var invoice = library.newInvoice(on: UIFixture.today)
        invoice.lines.append(.blank(hourlyRate: library.brand.hourlyRate))
        let added = try #require(invoice.lines.last)
        #expect(added.unit == .units)
        #expect(added.rate == .zero)
        // Blank on the Brand page is stored as no rate; a stray $0 means the same thing.
        library.brand.hourlyRate = .zero
        invoice.lines.append(.blank(hourlyRate: library.brand.hourlyRate))
        #expect(invoice.lines.last?.unit == .units)
    }

    /// A rate typed over the filled-in one stays through the line table, and switching the unit away
    /// and back keeps the typed rate too.
    @Test func aRateTypedOverTheFilledInOneSurvivesTheLineTable() throws {
        let (model, quoteID) = try modelWithADraft()
        var quote = model.library.quote(quoteID)!
        quote.addLine(.blank(hourlyRate: hourly))
        var line = try #require(quote.lines.last)
        line.rate = Money(dollars: 120)
        let stored = try #require(quote.lines.replacing(line, id: line.id, hourlyRate: hourly, editable: true))
        #expect(stored.last?.rate == Money(dollars: 120))
        var days = line
        days.unit = .days
        let toDays = try #require(stored.replacing(days, id: line.id, hourlyRate: hourly, editable: true))
        var back = days
        back.unit = .hours
        let backInHours = try #require(toDays.replacing(back, id: line.id, hourlyRate: hourly, editable: true))
        #expect(backInHours.last?.rate == Money(dollars: 120))
    }

    // MARK: A field keeps up with a change made elsewhere

    /// The unit picker fills the rate in while the cursor may still sit in the rate field; the field
    /// must show it, or leaving the field would commit the old text over it.
    @Test func aFieldRefreshesWhenSomethingElseChangesItsValue() {
        let parse = FieldParser.money
        // Not being typed in: always.
        #expect(CommitField<Money>.refreshesText(text: "$0.00", focused: false, newValue: hourly, parse: parse))
        // Being typed in, and the text is the value (it was committed as it was typed): left as typed.
        #expect(!CommitField<Money>.refreshesText(text: "95", focused: true, newValue: hourly, parse: parse))
        #expect(!CommitField<Money>.refreshesText(text: "$95.00", focused: true, newValue: hourly, parse: parse))
        // Being typed in, but the value is no longer what the text says.
        #expect(CommitField<Money>.refreshesText(text: "$0.00", focused: true, newValue: hourly, parse: parse))
        #expect(CommitField<Money>.refreshesText(text: "", focused: true, newValue: hourly, parse: parse))
    }

    // MARK: The empty-Dashboard texts

    @Test func anEmptyLibraryHasNothingToInvoiceYetAndNothingWaiting() {
        let library = Library()
        #expect(DashboardView.toInvoiceEmptyText(library) == "Nothing to invoice yet.")
        #expect(DashboardView.waitingEmptyText(library) == "Nothing waiting to be paid.")
    }

    @Test func draftsAndSentQuotesAloneStillMeanNothingToInvoiceOrWaiting() throws {
        var library = Library()
        var quote = library.newQuote(on: UIFixture.today)
        quote.addLine(LineItem(title: "Design", rate: Money(dollars: 600)))
        try library.update(quote)
        _ = library.newInvoice(on: UIFixture.today)
        #expect(DashboardView.toInvoiceEmptyText(library) == "Nothing to invoice yet.")
        #expect(DashboardView.waitingEmptyText(library) == "Nothing waiting to be paid.")
        try library.markSent(quote: quote.id)
        #expect(DashboardView.toInvoiceEmptyText(library) == "Nothing to invoice yet.")
    }

    @Test func withDataTheEmptyListsKeepTheirWording() throws {
        var (library, quoteID) = try UIFixture.invoicedLibrary()
        // The deposit is drafted and the balance is not, so there is still something to invoice.
        #expect(Dashboard(library: library, today: UIFixture.today).toInvoice.count == 1)
        try library.completeJob(quote: quoteID, on: UIFixture.today)
        #expect(Dashboard(library: library, today: UIFixture.today).toInvoice.isEmpty)
        #expect(DashboardView.toInvoiceEmptyText(library) == "Every accepted job is fully invoiced.")

        // Sent and paid in full: nothing is waiting, but invoices have gone out.
        for invoice in library.invoices {
            try library.markSent(invoice: invoice.id)
            try library.recordPayment(Payment(date: UIFixture.today, amount: invoice.amount), toInvoice: invoice.id)
        }
        #expect(Dashboard(library: library, today: UIFixture.today).waiting.isEmpty)
        #expect(DashboardView.waitingEmptyText(library) == "Nothing waiting. Every sent invoice is paid.")
    }

    @Test func aVoidedInvoiceIsNotASentOne() throws {
        var (library, _) = try UIFixture.invoicedLibrary()
        let id = library.invoices[0].id
        try library.markSent(invoice: id)
        #expect(!Dashboard(library: library, today: UIFixture.today).waiting.isEmpty)
        try library.voidInvoice(id)
        #expect(DashboardView.waitingEmptyText(library) == "Nothing waiting to be paid.")
    }
}
