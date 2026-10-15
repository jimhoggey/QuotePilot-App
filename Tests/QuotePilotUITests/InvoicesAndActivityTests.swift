import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct InvoicesAndActivityTests {
    @Test func invoiceRowsShowKindStatusAndWhatsOwing() throws {
        let model = try UIFixture.sampleModel()
        let rows = model.library.invoices.map { InvoiceRow($0, library: model.library, today: model.today) }
        #expect(rows.map(\.number) == ["INV-0001", "INV-0002", "INV-0003"])
        #expect(rows.map(\.kind) == ["Deposit", "One-off", "One-off"])
        #expect(rows.map(\.status) == [.paid, .overdue(daysLate: 5), .partPaid])
        #expect(rows.map(\.owing) == [.zero, Money(dollars: 150), Money(dollars: 135)])
    }

    @Test func aVoidInvoiceOwesNothing() throws {
        var library = try SampleLibrary.make(today: UIFixture.today)
        let care = try #require(library.invoices.first { $0.number == "INV-0002" })
        try library.voidInvoice(care.id)
        let row = InvoiceRow(try #require(library.invoice(care.id)), library: library, today: UIFixture.today)
        #expect(row.status == .void)
        #expect(row.owing == .zero)
    }

    @Test func openingAnActivityEntryOpensItsDocument() throws {
        let model = try UIFixture.sampleModel()
        model.openDocument(number: "INV-0002")
        #expect(model.section == .invoices)
        #expect(model.selectedInvoiceID == model.library.invoices.first { $0.number == "INV-0002" }?.id)
        model.openDocument(number: "Q-0002")
        #expect(model.section == .quotes)
        #expect(model.openQuoteID == model.library.quote(number: "Q-0002")?.id)
    }

    @Test func theInvoicesScreenDraws() throws {
        let model = try UIFixture.sampleModel()
        model.section = .invoices
        model.selectedInvoiceID = model.library.invoices[1].id
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "invoices")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func theListAndPreviewFitAtEveryWindowWidth() {
        // The window's smallest width (980) leaves 778 beside the section tree.
        for width in stride(from: CGFloat(778), through: 2400, by: 1) {
            let layout = InvoicesView.layout(width: width)
            #expect(layout.listMinimum + layout.previewWidth + 24 <= width, "overflows at \(width)")
            #expect(layout.previewWidth >= 220)
            #expect(layout.previewWidth <= 520)
        }
        let smallest = InvoicesView.layout(width: 778)
        #expect(!smallest.showKind)
        let usual = InvoicesView.layout(width: 1038) // the 1240-wide window the app opens at
        #expect(usual.showKind)
        #expect(usual.previewWidth >= 300)
    }

    @Test func theActivityScreenDraws() throws {
        let model = try UIFixture.sampleModel()
        model.section = .activity
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "activity")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
