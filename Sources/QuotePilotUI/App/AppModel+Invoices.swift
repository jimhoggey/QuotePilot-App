import Foundation
import QuotePilotCore
import SwiftUI

/// What the invoice editor's New payment area holds while you type.
public struct PaymentEntry: Equatable {
    public var invoiceID: UUID
    public var date: Day
    /// As typed; read with `FieldParser.money` when you press Record Payment.
    public var amount: String
    public var method: PaymentMethod
    public var note: String
}

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

    /// The invoice the editor shows: the open one, as long as it is still in the library. An id that
    /// no longer matches an invoice (a restored backup) shows the list instead, and saving and sending
    /// go on using the list's selection.
    var editingInvoiceID: UUID? {
        openInvoiceID.flatMap { library.invoice($0) }?.id
    }

    /// What the invoice editor offers for one invoice, and what it says about the rest.
    func invoiceRules(_ id: UUID) -> InvoiceRules? {
        library.invoice(id).map { InvoiceRules(invoice: $0, finalDeducting: library.finalDeducting(id)) }
    }

    /// A deposit invoice's banner line: what the deposit is out of the job, what's paid, and when the
    /// rest is billed. "Deposit for Q-0008: $750.00 of $1,500.00 paid. The remaining $750.00 will be
    /// invoiced when the job is complete." Nil for any other invoice.
    func depositNote(_ id: UUID) -> String? {
        guard let invoice = library.invoice(id), invoice.kind == .deposit,
              let quoteID = invoice.quoteID, let quote = library.quote(quoteID) else { return nil }
        let total = invoice.lineTotals.total
        let deposit = invoice.amount
        let balance = total - deposit
        var first = "Deposit for \(quote.number): \(money(deposit)) of \(money(total))"
        if invoice.paid >= deposit && deposit > .zero {
            first += " paid."
        } else if invoice.paid > .zero {
            first += ", \(money(invoice.paid)) paid so far."
        } else {
            first += "."
        }
        let second: String
        if let closing = library.closingInvoice(forQuote: quoteID) {
            second = "The remaining \(money(balance)) is on \(closing.number)."
        } else if quote.completedOn != nil {
            second = "The job is complete, so the remaining \(money(balance)) will be invoiced next."
        } else {
            second = "The remaining \(money(balance)) will be invoiced when the job is complete."
        }
        return first + " " + second
    }

    /// Under a deposit invoice's readout: what's left to pay on the whole job. Nil for any other
    /// invoice, for a void deposit, and once nothing is left, so the readout only shows above $0.
    func leftToPayOnJob(_ id: UUID) -> Money? {
        guard let invoice = library.invoice(id), invoice.kind == .deposit, invoice.stage != .void,
              let quoteID = invoice.quoteID, let left = library.leftToPay(onQuote: quoteID),
              left > .zero else { return nil }
        return left
    }

    /// "Draft Invoice Now": the next invoice the quote's plan calls for.
    public func draftInvoiceNow(forQuote id: UUID) {
        var created: UUID?
        guard change("Couldn't draft the invoice", { library in
            created = try library.draftNextInvoice(forQuote: id, on: today).id
        }), let created else { return }
        openInvoice(created)
    }

    /// Whether a quote's billing details are locked: it has invoices that still count, so Core
    /// (`Library.update(_ quote:)`) refuses a new client, plan or GST setting and any line added,
    /// removed or changed in amount. The quote editor greys those controls out and says so
    /// (`billingLockedNote`) instead of offering what would only end in an error box. Voiding its
    /// invoices unlocks it again.
    public func billingLocked(forQuote id: UUID) -> Bool {
        !library.invoices(forQuote: id).isEmpty
    }

    /// The sentence the quote editor shows while `billingLocked(forQuote:)`.
    public static let billingLockedNote = "This quote has invoices, so its client, lines and payment plan are locked. Its title, dates, work summary and terms can still change."

    /// Whether "Job Complete" is on offer for a quote: it is accepted and the job isn't marked complete
    /// yet. It doesn't depend on whether an invoice is left to draft, because the job is finished
    /// whether or not the closing invoice already exists (Draft Invoice Now may have drafted it).
    public func canCompleteJob(_ quoteID: UUID) -> Bool {
        guard let quote = library.quote(quoteID) else { return false }
        return quote.stage == .accepted && !quote.acceptedLines.isEmpty && quote.completedOn == nil
    }

    /// "Job Complete": records the date and drafts the closing invoice, unless it exists already. Either
    /// way the closing invoice opens, with no message box in between.
    public func completeJob(_ quoteID: UUID) {
        var created: UUID?
        guard change("Couldn't complete the job", { library in
            created = try library.completeJob(quote: quoteID, on: today)?.id
        }) else { return }
        // The one just drafted, or the one the quote already had.
        if let closing = created ?? library.closingInvoice(forQuote: quoteID)?.id { openInvoice(closing) }
    }

    /// Asks before voiding, once. An invoice that can't be voided says why instead, in that one box:
    /// the question is never asked only to be refused.
    public func voidInvoice(_ id: UUID) {
        guard let invoice = library.invoice(id) else { return }
        switch invoice.stage {
        case .draft: return show(LibraryError.notSent, title: "Can't Void")
        case .void: return show(LibraryError.isVoid, title: "Can't Void")
        case .sent: break
        }
        if !invoice.payments.isEmpty { return show(LibraryError.hasPayments, title: "Can't Void") }
        if let final = library.finalDeducting(id) {
            return show(LibraryError.deductedByFinal(final.number), title: "Can't Void")
        }
        confirm(title: "Void Invoice",
                text: "Void \(invoice.number)? It stops counting as owed, and its number stays used.",
                confirm: "Void") {
            self.change("Couldn't void \(invoice.number)") { try $0.voidInvoice(id) }
        }
    }

    public func deleteDraftInvoice(_ id: UUID) {
        guard let invoice = library.invoice(id) else { return }
        guard invoice.stage == .draft else { return show(LibraryError.notDraft, title: "Can't Delete") }
        if let final = library.finalDeducting(id) {
            return show(LibraryError.deductedByFinal(final.number), title: "Can't Delete")
        }
        confirm(title: "Delete Draft",
                text: "Delete draft invoice \(invoice.number)? Its number won't be used again.",
                confirm: "Delete") {
            guard self.change("Couldn't delete \(invoice.number)", { try $0.deleteDraft(invoice: id) }) else { return }
            if self.openInvoiceID == id { self.openInvoiceID = nil }
            if self.selectedInvoiceID == id { self.selectedInvoiceID = nil }
        }
    }

    // MARK: Payments

    /// A new payment as the editor's New payment area starts it: today, what's owing, a bank transfer
    /// and no note. Nil when the invoice can't take a payment: it isn't sent, it is void, or it is
    /// paid in full.
    public func newPaymentEntry(for invoiceID: UUID) -> PaymentEntry? {
        guard let invoice = library.invoice(invoiceID), invoice.stage == .sent, invoice.owing > .zero else { return nil }
        return PaymentEntry(invoiceID: invoiceID, date: today, amount: money(invoice.owing),
                            method: .bankTransfer, note: "")
    }

    /// Records the New payment area's payment. A refused amount shows why in a box, and the area keeps
    /// what was typed. A recorded one shows no box: the figures on screen change, and the status bar
    /// says what was recorded.
    @discardableResult
    public func recordPayment(_ entry: PaymentEntry) -> Bool {
        guard let amount = FieldParser.money(entry.amount) else {
            show(title: "Amount", text: "Type the amount paid, like 540 or $540.00.", kind: .warning)
            return false
        }
        let payment = Payment(date: entry.date, amount: amount, method: entry.method,
                              note: entry.note.trimmingCharacters(in: .whitespacesAndNewlines))
        guard change("Couldn't record the payment", { try $0.recordPayment(payment, toInvoice: entry.invoiceID) }),
              let invoice = library.invoice(entry.invoiceID)
        else { return false }
        note("Recorded \(money(amount)) for \(invoice.number)")
        return true
    }

    /// Asks first: removing a payment is a change to what the client owes.
    public func removePayment(_ paymentID: UUID, from invoiceID: UUID) {
        guard let invoice = library.invoice(invoiceID),
              let payment = invoice.payments.first(where: { $0.id == paymentID }) else { return }
        confirm(title: "Remove Payment",
                text: "Remove the \(money(payment.amount)) payment of \(payment.date.long) from \(invoice.number)?",
                confirm: "Remove") {
            self.change("Couldn't remove the payment") { try $0.removePayment(paymentID, fromInvoice: invoiceID) }
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

/// What the invoice editor lets you do with one invoice, and the sentence it puts on screen to say why
/// the rest is off. These follow core's own rules (`Library.update(_ invoice:)`, `voidInvoice`,
/// `deleteDraft(invoice:)`), so the editor never offers what core would refuse.
struct InvoiceRules: Equatable {
    struct Note: Equatable {
        var text: String
        /// Bright yellow rather than pale: for an invoice that no longer counts.
        var warning: Bool
    }

    let invoice: Invoice
    /// The live final invoice that still deducts this one, when this is a deposit.
    let finalDeducting: Invoice?

    var isDeducted: Bool { finalDeducting != nil }

    /// Title, dates and client: a draft's, whatever it deducts.
    var canEditDetails: Bool { invoice.stage == .draft }

    /// Lines, GST and terms. A deposit the final invoice deducts keeps what it bills, or the final
    /// would deduct a different amount than the deposit asks for.
    var canEditAmounts: Bool { invoice.stage == .draft && !isDeducted }

    var canVoid: Bool { invoice.stage == .sent && invoice.payments.isEmpty && !isDeducted }

    var canDelete: Bool { invoice.stage == .draft && !isDeducted }

    /// A draft's number. A deposit the final invoice deducts keeps its number, as the final names it.
    var canRenumber: Bool { invoice.stage == .draft && !isDeducted }

    /// What has to happen to the final invoice before this deposit can change, as a sentence: void or
    /// delete it, or, when it has payments (a sent invoice with payments can be neither), remove them
    /// and then void it.
    var finalFirst: String? {
        guard let final = finalDeducting else { return nil }
        return final.payments.isEmpty ? "Void or delete \(final.number) first." : "Remove \(final.number)'s payments, then void it."
    }

    /// The Void… and Delete Draft tooltips while the final invoice deducts this deposit.
    var deductedHelp: String? {
        guard let final = finalDeducting, let first = finalFirst else { return nil }
        return "Final invoice \(final.number) deducts this deposit. \(first)"
    }

    /// The one sentence about this invoice's state, or none for an ordinary draft.
    var note: Note? {
        switch invoice.stage {
        case .void:
            return Note(text: "This invoice is void. It no longer counts as owed, and its number stays used.", warning: true)
        case .draft:
            guard let final = finalDeducting, let first = finalFirst else { return nil }
            return Note(text: "Final invoice \(final.number) deducts this deposit, so its lines, GST and terms can't be changed. \(first)",
                        warning: false)
        case .sent:
            // Payments come first: they are what stops it being voided, and a deduction only matters after.
            if !invoice.payments.isEmpty {
                return Note(text: "This invoice has been sent and has payments recorded, so it can't be changed or voided. Remove the payments first if you need to void it.",
                            warning: false)
            }
            if let final = finalDeducting {
                let first = final.payments.isEmpty ? "void or delete \(final.number)" : "remove \(final.number)'s payments and void \(final.number)"
                return Note(text: "This invoice has been sent, so it can't be changed. Final invoice \(final.number) deducts it, so \(first) before voiding this one.",
                            warning: false)
            }
            return Note(text: "This invoice has been sent, so it can't be changed. If something's wrong, void it and draft a new one.",
                        warning: false)
        }
    }
}
