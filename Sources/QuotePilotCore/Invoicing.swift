import Foundation

public enum InvoiceStatus: Equatable, Sendable {
    case draft, sent, partPaid, paid, void
    case overdue(daysLate: Int)

    public var label: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .partPaid: return "Part paid"
        case .paid: return "Paid"
        case .void: return "Void"
        case .overdue(let days): return days == 1 ? "Overdue, 1 day" : "Overdue, \(days) days"
        }
    }
}

extension Invoice {
    /// Overdue starts the day after the due date, and only while money is still owing.
    public func status(on today: Day) -> InvoiceStatus {
        switch stage {
        case .draft: return .draft
        case .void: return .void
        case .sent:
            if owing <= .zero { return .paid }
            if today > due { return .overdue(daysLate: today.days(since: due)) }
            return paid > .zero ? .partPaid : .sent
        }
    }
}

extension InvoiceKind {
    public var label: String {
        switch self {
        case .deposit: return "deposit invoice"
        case .final: return "final invoice"
        case .full, .standalone: return "invoice"
        }
    }

    /// The invoice that closes a quote's billing: the final one for 50/50, the full one otherwise.
    /// A quote has at most one, whichever the plan says, and it subtracts every live deposit.
    var isClosing: Bool { self == .final || self == .full }
}

extension LineItem {
    /// The same line with a new identity and no client decision, for copies and invoices.
    var freshCopy: LineItem {
        var copy = self
        copy.id = UUID()
        copy.decision = nil
        return copy
    }
}

extension Library {
    /// A quote's invoices that still count (void ones don't).
    public func invoices(forQuote id: UUID) -> [Invoice] {
        invoices.filter { $0.quoteID == id && $0.stage != .void }
    }

    public func invoicedAmount(forQuote id: UUID) -> Money {
        invoices(forQuote: id).reduce(.zero) { $0 + $1.amount }
    }

    /// The invoice the quote's plan calls for next, or nil when nothing is left to invoice.
    public func nextInvoiceKind(forQuote id: UUID) -> InvoiceKind? {
        guard let found = quote(id), found.stage == .accepted, !found.acceptedLines.isEmpty else { return nil }
        let kinds = invoices(forQuote: id).map(\.kind)
        if kinds.contains(where: \.isClosing) { return nil }
        switch found.plan {
        case .fiftyFifty: return kinds.contains(.deposit) ? .final : .deposit
        case .fullAmount: return .full
        }
    }

    /// "Draft invoice now": the deposit if there isn't one yet, otherwise the closing invoice.
    @discardableResult
    public mutating func draftNextInvoice(forQuote id: UUID, on day: Day) throws -> Invoice {
        let found = try acceptedQuote(id)
        guard let kind = nextInvoiceKind(forQuote: id) else { throw LibraryError.nothingLeftToInvoice }
        return draftInvoice(kind, for: found, on: day)
    }

    /// "Job complete": records the date, then drafts the closing invoice unless it already exists.
    /// For 50/50 without a deposit invoice, the final invoice simply bills the whole accepted total.
    @discardableResult
    public mutating func completeJob(quote id: UUID, on day: Day) throws -> Invoice? {
        let found = try acceptedQuote(id)
        let index = try quoteIndex(id)
        if quotes[index].completedOn == nil {
            quotes[index].completedOn = day
            log("Marked the job for \(found.number) complete", number: found.number)
        }
        let closing: InvoiceKind = found.plan == .fiftyFifty ? .final : .full
        guard !invoices(forQuote: id).contains(where: { $0.kind.isClosing }) else { return nil }
        return draftInvoice(closing, for: found, on: day)
    }

    /// The quote's live closing invoice (the final one for 50/50, the full one otherwise), or nil when
    /// it has none yet or its closing invoice was voided.
    public func closingInvoice(forQuote id: UUID) -> Invoice? {
        invoices(forQuote: id).first { $0.kind.isClosing }
    }

    /// The live closing invoice that still subtracts this deposit, or nil: the invoice isn't a deposit,
    /// no closing invoice has been drafted, or it is void. While one exists the deposit can't be
    /// voided, deleted or have its lines or tax changed, which is what a screen asks before offering
    /// to.
    public func finalDeducting(_ invoiceID: UUID) -> Invoice? {
        invoice(invoiceID).flatMap(liveFinalDeducting)
    }

    /// The live closing (final or full) invoice that still subtracts this deposit, if any. Voiding,
    /// deleting or editing the deposit while one exists would leave that invoice deducting an amount
    /// the deposit no longer has.
    func liveFinalDeducting(_ invoice: Invoice) -> Invoice? {
        guard invoice.kind == .deposit else { return nil }
        return invoices.first {
            $0.quoteID == invoice.quoteID && $0.kind.isClosing && $0.stage != .void
                && $0.deductions.contains { $0.invoiceNumber == invoice.number }
        }
    }

    private func acceptedQuote(_ id: UUID) throws -> Quote {
        guard let found = quote(id) else { throw LibraryError.notFound }
        guard found.stage == .accepted else { throw LibraryError.notAccepted }
        guard !found.acceptedLines.isEmpty else { throw LibraryError.nothingAccepted }
        return found
    }

    private mutating func draftInvoice(_ kind: InvoiceKind, for quote: Quote, on day: Day) -> Invoice {
        var invoice = Invoice(number: takeNumber(.invoice), clientID: quote.clientID, quoteID: quote.id,
                              kind: kind, title: quote.title, issued: day,
                              due: day.adding(days: brand.paymentDueDays), taxed: quote.taxed,
                              lines: quote.acceptedLines.map(\.freshCopy), terms: brand.invoiceTerms)
        if kind == .deposit {
            invoice.depositPercent = quote.plan.depositPercent ?? 50
        }
        if kind.isClosing {
            invoice.deductions = invoices(forQuote: quote.id)
                .filter { $0.kind == .deposit }
                .map { Deduction(label: "Less deposit", invoiceNumber: $0.number, amount: $0.amount) }
        }
        invoices.append(invoice)
        log("Drafted \(kind.label) \(invoice.number) for \(invoice.amount.formatted()) from quote \(quote.number)",
            number: invoice.number)
        return invoice
    }

    // MARK: Sending and payments

    public mutating func markSent(invoice id: UUID, at time: Date = Date()) throws {
        let index = try invoiceIndex(id)
        guard invoices[index].stage != .void else { throw LibraryError.isVoid }
        invoices[index].stage = .sent
        invoices[index].sentAt = time
        log("Marked invoice \(invoices[index].number) as sent", number: invoices[index].number, at: time)
    }

    public mutating func recordPayment(_ payment: Payment, toInvoice id: UUID) throws {
        let index = try invoiceIndex(id)
        switch invoices[index].stage {
        case .void: throw LibraryError.isVoid
        case .draft: throw LibraryError.notSent
        case .sent: break
        }
        guard payment.amount > .zero else { throw LibraryError.paymentNotPositive }
        let owing = invoices[index].owing
        guard payment.amount <= owing else { throw LibraryError.paymentMoreThanOwing(owing) }
        invoices[index].payments.append(payment)
        // A receipt already sent covers the payments up to then, not this one: Send Receipt… is offered again.
        invoices[index].receiptSentAt = nil
        let number = invoices[index].number
        log("Recorded \(payment.amount.formatted()) paid on \(payment.date.long) by \(payment.method.label.lowercased()) for \(number)",
            number: number)
    }

    public mutating func removePayment(_ paymentID: UUID, fromInvoice id: UUID) throws {
        let index = try invoiceIndex(id)
        guard let position = invoices[index].payments.firstIndex(where: { $0.id == paymentID }) else {
            throw LibraryError.notFound
        }
        let removed = invoices[index].payments.remove(at: position)
        // No payments left means no receipt stands either.
        if invoices[index].payments.isEmpty { invoices[index].receiptSentAt = nil }
        let number = invoices[index].number
        log("Removed the \(removed.amount.formatted()) payment of \(removed.date.long) from \(number)", number: number)
    }

    /// Cancels a sent invoice and keeps its number used. Drafts are deleted instead; an invoice
    /// with payments must have them removed first.
    public mutating func voidInvoice(_ id: UUID) throws {
        let index = try invoiceIndex(id)
        switch invoices[index].stage {
        case .void: throw LibraryError.isVoid
        case .draft: throw LibraryError.notSent
        case .sent: break
        }
        guard invoices[index].payments.isEmpty else { throw LibraryError.hasPayments }
        if let final = liveFinalDeducting(invoices[index]) { throw LibraryError.deductedByFinal(final.number) }
        invoices[index].stage = .void
        log("Voided invoice \(invoices[index].number)", number: invoices[index].number)
    }

    public mutating func markReceiptSent(invoice id: UUID, at time: Date = Date()) throws {
        let index = try invoiceIndex(id)
        guard !invoices[index].payments.isEmpty else { throw LibraryError.noPayments }
        invoices[index].receiptSentAt = time
        log("Marked the receipt for \(invoices[index].number) as sent", number: invoices[index].number, at: time)
    }

    // MARK: Copies

    /// A fresh draft dated `day`: for repeat work such as a monthly fee.
    @discardableResult
    public mutating func duplicateInvoice(_ id: UUID, on day: Day) throws -> Invoice {
        guard let original = invoice(id) else { throw LibraryError.notFound }
        let copy = Invoice(number: takeNumber(.invoice), clientID: original.clientID, kind: .standalone,
                           title: original.title, issued: day, due: day.adding(days: brand.paymentDueDays),
                           taxed: original.taxed, lines: original.lines.map(\.freshCopy), terms: original.terms)
        invoices.append(copy)
        log("Copied invoice \(original.number) to \(copy.number)", number: copy.number)
        return copy
    }

    @discardableResult
    public mutating func duplicateQuote(_ id: UUID, on day: Day) throws -> Quote {
        guard let original = quote(id) else { throw LibraryError.notFound }
        var copy = Quote(number: takeNumber(.quote), clientID: original.clientID, title: original.title,
                         issued: day, validUntil: day.adding(days: brand.quoteValidDays), plan: original.plan,
                         taxed: original.taxed, summary: original.summary, terms: original.terms)
        for line in original.lines {
            copy.addLine(line.freshCopy)
        }
        quotes.append(copy)
        log("Copied quote \(original.number) to \(copy.number)", number: copy.number)
        return copy
    }
}
