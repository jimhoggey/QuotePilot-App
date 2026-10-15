import Foundation
import QuotePilotCore
import SwiftUI

extension AppModel {
    /// ⇧⌘N: a one-off invoice, for extra work or a monthly fee.
    public func newInvoice(for clientID: UUID? = nil) {
        var created: UUID?
        guard change("Couldn't start a new invoice", { library in
            created = library.newInvoice(on: today, clientID: clientID).id
        }), let created else { return }
        openInvoice(created)
    }

    public func updateInvoice(_ invoice: Invoice) {
        change("Couldn't save \(invoice.number)") { try $0.update(invoice) }
    }

    /// The editor's view of an invoice: it reads the stored invoice and writes through
    /// `updateInvoice`, so a refused edit shows the stored value again.
    public func invoiceBinding(_ id: UUID) -> Binding<Invoice> {
        Binding(
            get: {
                self.library.invoice(id)
                    ?? Invoice(id: id, number: "", kind: .standalone, issued: self.today, due: self.today)
            },
            set: { self.updateInvoice($0) })
    }

    /// "Draft Invoice Now": the next invoice the quote's plan calls for.
    public func draftInvoiceNow(forQuote id: UUID) {
        var created: UUID?
        guard change("Couldn't draft the invoice", { library in
            created = try library.draftNextInvoice(forQuote: id, on: today).id
        }), let created else { return }
        openInvoice(created)
    }

    /// "Job Complete": records the date and drafts the closing invoice, unless it exists already. Either
    /// way the closing invoice opens, with no message box in between.
    public func completeJob(_ quoteID: UUID) {
        var created: UUID?
        guard change("Couldn't complete the job", { library in
            created = try library.completeJob(quote: quoteID, on: today)?.id
        }) else { return }
        // The one just drafted, or the one the quote already had (the final one for 50/50, else the full one).
        let closing = created ?? library.invoices(forQuote: quoteID)
            .first { $0.kind == .final || $0.kind == .full }?.id
        if let closing { openInvoice(closing) }
    }

    public func voidInvoice(_ id: UUID) {
        guard let invoice = library.invoice(id) else { return }
        confirm(title: "Void Invoice",
                text: "Void \(invoice.number)? It stops counting as owed, and its number stays used.",
                confirm: "Void") {
            self.change("Couldn't void \(invoice.number)") { try $0.voidInvoice(id) }
        }
    }

    public func deleteDraftInvoice(_ id: UUID) {
        guard let invoice = library.invoice(id) else { return }
        guard invoice.stage == .draft else { return show(LibraryError.notDraft, title: "Can't Delete") }
        confirm(title: "Delete Draft",
                text: "Delete draft invoice \(invoice.number)? Its number won't be used again.",
                confirm: "Delete") {
            guard self.change("Couldn't delete \(invoice.number)", { try $0.deleteDraft(invoice: id) }) else { return }
            if self.openInvoiceID == id { self.openInvoiceID = nil }
            if self.selectedInvoiceID == id { self.selectedInvoiceID = nil }
        }
    }

    /// A fresh draft copy of a one-off invoice, for repeat work. Invoices from a quote are drafted from
    /// the quote instead.
    public func duplicateInvoice(_ id: UUID) {
        guard let invoice = library.invoice(id) else { return }
        guard invoice.kind == .standalone else {
            return show(title: "Can't Duplicate",
                        text: "Only one-off invoices can be duplicated. \(invoice.number) comes from a quote, so draft the next one from the quote instead.",
                        kind: .warning)
        }
        var created: UUID?
        guard change("Couldn't duplicate \(invoice.number)", { library in
            created = try library.duplicateInvoice(id, on: today).id
        }), let created else { return }
        openInvoice(created)
    }
}
