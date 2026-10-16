import Foundation

/// What deleting one quote or invoice would remove, for the question that asks first.
public struct DeletionPreview: Equatable, Sendable {
    /// The number of the quote or invoice being deleted.
    public var number: String
    /// The invoices that go with a quote, void ones too, in number order. Always empty for an invoice.
    public var invoiceNumbers: [String]
    /// Whether the invoice being deleted, or any invoice that goes with the quote, has payments recorded.
    public var hasPayments: Bool

    public init(number: String, invoiceNumbers: [String], hasPayments: Bool) {
        self.number = number
        self.invoiceNumbers = invoiceNumbers
        self.hasPayments = hasPayments
    }
}

extension Library {
    /// Every invoice written from a quote, whatever its stage (a void one still names the quote), in
    /// number order ("INV-0009" before "INV-0010").
    func invoices(ofQuote id: UUID) -> [Invoice] {
        invoices
            .filter { $0.quoteID == id }
            .sorted { $0.number.compare($1.number, options: .numeric) == .orderedAscending }
    }

    /// What `deleteQuote(_:includingInvoices:)` would remove, or nil when there is no such quote.
    public func deletionPreview(quote id: UUID) -> DeletionPreview? {
        guard let quote = quote(id) else { return nil }
        let doomed = invoices(ofQuote: id)
        return DeletionPreview(number: quote.number, invoiceNumbers: doomed.map(\.number),
                               hasPayments: doomed.contains { !$0.payments.isEmpty })
    }

    /// What `deleteInvoice(_:)` would remove, or nil when there is no such invoice.
    public func deletionPreview(invoice id: UUID) -> DeletionPreview? {
        guard let invoice = invoice(id) else { return nil }
        return DeletionPreview(number: invoice.number, invoiceNumbers: [], hasPayments: !invoice.payments.isEmpty)
    }

    /// Deletes a quote at any stage: a draft, a sent quote waiting on the client, an accepted one or a
    /// declined one. The quote's invoices (every stage, with their payments) go with it, so no invoice
    /// is left pointing at a quote that isn't there; a quote that has some is refused unless the
    /// caller says they go too (`includingInvoices`), and then nothing changes. The quote's number
    /// and its invoices' numbers stay used, so none is ever issued again. One Activity entry says what
    /// went.
    public mutating func deleteQuote(_ id: UUID, includingInvoices: Bool) throws {
        let index = try quoteIndex(id)
        let quote = quotes[index]
        let doomed = invoices(ofQuote: id)
        if !doomed.isEmpty, !includingInvoices {
            throw LibraryError.quoteHasInvoices(quote: quote.number, invoices: doomed.map(\.number))
        }
        // A library saved before the used-numbers list existed knows its numbers only from its
        // documents, so they are listed before the documents go.
        keepUsed([quote.number] + doomed.map(\.number))
        let gone = Set(doomed.map(\.id))
        invoices.removeAll { gone.contains($0.id) }
        quotes.remove(at: index)
        var message = "Deleted quote \(quote.number) (\(quote.stage.rawValue))"
        if !doomed.isEmpty {
            message += " and invoice\(doomed.count == 1 ? "" : "s") \(doomed.map(\.number).joined(separator: ", "))"
        }
        log(message, number: quote.number)
    }

    /// Deletes one invoice at any stage, with its payments. Its number stays used. A deposit that a
    /// live final invoice still subtracts is refused (the final goes first, or the final would deduct
    /// an amount that no longer exists); a void final deducts nothing. One Activity entry says what
    /// went.
    public mutating func deleteInvoice(_ id: UUID) throws {
        let index = try invoiceIndex(id)
        if let final = liveFinalDeducting(invoices[index]) {
            throw LibraryError.depositStillDeducted(final.number)
        }
        keepUsed([invoices[index].number])
        let invoice = invoices.remove(at: index)
        log("Deleted invoice \(invoice.number) (\(invoice.stage.rawValue))", number: invoice.number)
    }
}
