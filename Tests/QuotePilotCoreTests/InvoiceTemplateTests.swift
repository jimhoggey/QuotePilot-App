import Foundation
import Testing
@testable import QuotePilotCore

/// Brand → Documents' invoice templates: a new invoice from one starts with its title and lines.
@Suite struct InvoiceTemplateTests {
    let day = Day(year: 2026, month: 11, day: 5)
    let meeting = InvoiceTemplate(title: "Billing for meeting time",
                                  lines: [LineItem(title: "Meeting time", quantity: 1, unit: .hours, rate: Money(dollars: 95))])

    @Test func anInvoiceFromATemplateStartsWithItsTitleAndLines() throws {
        var library = Library()
        library.brand.invoiceTemplates = [meeting]
        let invoice = library.newInvoice(on: day, from: meeting)
        #expect(invoice.title == "Billing for meeting time")
        #expect(invoice.lines.map(\.title) == ["Meeting time"])
        #expect(invoice.amount == Money(dollars: 95))
        #expect(invoice.lines[0].id != meeting.lines[0].id, "copies, so the template never changes with the invoice")
        #expect(invoice.due == day.adding(days: library.brand.paymentDueDays))
        #expect(invoice.terms == library.brand.invoiceTerms)
        #expect(library.activity.first?.message == "Started invoice INV-0001 from the template Billing for meeting time")
    }

    @Test func aBlankInvoiceIsUnchanged() {
        var library = Library()
        let invoice = library.newInvoice(on: day)
        #expect(invoice.title.isEmpty && invoice.lines.isEmpty)
        #expect(library.activity.first?.message == "Started invoice INV-0001")
    }

    @Test func aTemplateLineOutOfRangeIsAProblem() {
        var library = Library()
        var broken = meeting
        broken.lines[0].rate = Money(dollars: 999_999_999)
        library.brand.invoiceTemplates = [broken]
        #expect(library.problems().contains { $0.hasPrefix("The template Billing for meeting time line 1 has a rate") })
    }

    /// An untitled template can't be told apart in a menu, so New Invoice leaves it out until it has a title.
    @Test func onlyTitledTemplatesAreOffered() {
        var brand = Brand()
        brand.invoiceTemplates = [InvoiceTemplate(title: "  "), meeting]
        #expect(brand.offeredInvoiceTemplates.map(\.title) == ["Billing for meeting time"])
    }

    /// Libraries from before templates have none.
    @Test func anOlderLibraryHasNoTemplates() throws {
        let brand = try JSONDecoder().decode(Brand.self, from: Data(#"{"businessName":"Sample Studio"}"#.utf8))
        #expect(brand.invoiceTemplates.isEmpty)
        #expect(InvoiceTemplate().shownTitle == "(no title)")
    }
}
