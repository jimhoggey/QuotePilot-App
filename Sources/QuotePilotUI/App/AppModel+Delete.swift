import Foundation
import QuotePilotCore

/// Delete… on a list row's right-click menu: any quote or invoice, at any stage, for a user who is
/// testing with made-up ones. Delete Draft (the buttons, and a draft quote's row menu) is separate and
/// unchanged.
extension AppModel {
    /// The question Delete… asks about a quote. A quote with invoices says they go with it, and that
    /// any payments recorded on them go too (whether or not there are any, so it never leaves the user
    /// guessing).
    static func deleteQuoteText(_ preview: DeletionPreview) -> String {
        let invoices = preview.invoiceNumbers
        guard !invoices.isEmpty else { return "Delete \(preview.number)? This can't be undone." }
        let many = invoices.count > 1
        return "Delete \(preview.number) and its invoice\(many ? "s" : "") \(invoices.joined(separator: ", "))? "
            + "Any payments recorded on \(many ? "them" : "it") go too. This can't be undone."
    }

    /// The question Delete… asks about an invoice; it mentions the payments only when it has some.
    static func deleteInvoiceText(_ preview: DeletionPreview) -> String {
        "Delete \(preview.number)? " + (preview.hasPayments ? "Its payments go too. " : "") + "This can't be undone."
    }

    /// Delete… on a quote: asks once (Cancel is the default), then removes the quote and its invoices
    /// with their payments. The selection and any editor that showed them are cleared, the list stays
    /// on screen and the status bar says what went. Waits while a message box or dialog is up, like
    /// the menu commands.
    public func deleteQuote(_ id: UUID) {
        whenFree {
            guard let preview = library.deletionPreview(quote: id) else { return }
            confirm(title: "Delete Quote", text: Self.deleteQuoteText(preview), confirm: "Delete") { [weak self] in
                guard let self else { return }
                let invoiceIDs = Set(library.invoices.filter { $0.quoteID == id }.map(\.id))
                // The invoices go only if the question said so: one that turned up since is refused.
                guard change("Couldn't delete \(preview.number)", {
                    try $0.deleteQuote(id, includingInvoices: !preview.invoiceNumbers.isEmpty)
                }) else { return }
                track(.deleted, ["kind": "quote"])
                if openQuoteID == id { openQuoteID = nil }
                if selectedQuoteID == id { selectedQuoteID = nil }
                if let open = openInvoiceID, invoiceIDs.contains(open) { openInvoiceID = nil }
                if let selected = selectedInvoiceID, invoiceIDs.contains(selected) { selectedInvoiceID = nil }
                note("Deleted \(preview.number)")
            }
        }
    }

    /// Delete… on an invoice: as for a quote. A deposit that a live final invoice still subtracts
    /// says so in the one message box instead (the question is never asked only to be refused).
    public func deleteInvoice(_ id: UUID) {
        whenFree {
            guard let preview = library.deletionPreview(invoice: id) else { return }
            if let final = library.finalDeducting(id) {
                return show(LibraryError.depositStillDeducted(final.number), title: "Can't Delete")
            }
            confirm(title: "Delete Invoice", text: Self.deleteInvoiceText(preview), confirm: "Delete") { [weak self] in
                guard let self, change("Couldn't delete \(preview.number)", { try $0.deleteInvoice(id) }) else { return }
                track(.deleted, ["kind": "invoice"])
                if openInvoiceID == id { openInvoiceID = nil }
                if selectedInvoiceID == id { selectedInvoiceID = nil }
                note("Deleted \(preview.number)")
            }
        }
    }
}
