import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// Invoice templates on screen: the form in Brand → Documents and New Invoice from a template.
@MainActor
@Suite struct InvoiceTemplateUITests {
    func model() throws -> (AppModel, InvoiceTemplate) {
        let model = try UIFixture.sampleModel()
        let template = InvoiceTemplate(title: "Billing for meeting time",
                                       lines: [LineItem(title: "Meeting time", quantity: 1, unit: .hours, rate: Money(dollars: 95))])
        var brand = model.library.brand
        brand.invoiceTemplates = [template]
        model.updateBrand(brand)
        return (model, template)
    }

    @Test func newInvoiceFromATemplateOpensIt() throws {
        let (model, template) = try model()
        model.newInvoice(from: template)
        let id = try #require(model.openInvoiceID)
        #expect(model.library.invoice(id)?.title == "Billing for meeting time")
        #expect(model.library.invoice(id)?.lines.map(\.title) == ["Meeting time"])
        #expect(model.section == .invoices)
    }

    /// The form fits beside the sample preview in the smallest window (snapshot: brand-documents-templates).
    @Test func theFormDraws() throws {
        let (model, _) = try model()
        let rep = Snapshot.render(BrandView(model: model, tab: .documents).background(Win95.face),
                                  size: CGSize(width: 778, height: 900), name: "brand-documents-templates")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    /// With templates, the toolbar's New Invoice is a menu that looks like the other buttons
    /// (snapshot: toolbar-templates).
    @Test func theToolbarDraws() throws {
        let (model, _) = try model()
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 980, height: 620), name: "toolbar-templates")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
