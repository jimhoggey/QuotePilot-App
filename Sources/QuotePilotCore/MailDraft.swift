import Foundation

/// What a Mail draft says: who it's to, the subject and the body, filled in from the brand's email
/// wording. The app adds the PDF; you press Send.
public struct MailDraft: Equatable, Sendable {
    /// The client's email, trimmed. Empty when the client has none yet.
    public var to: String
    public var subject: String
    public var body: String

    public init(to: String, subject: String, body: String) {
        self.to = to
        self.subject = subject
        self.body = body
    }
}

extension Library {
    public func mailDraft(forQuote id: UUID) -> MailDraft? {
        guard let quote = quote(id) else { return nil }
        return mailDraft(brand.emails.quote, client: client(quote.clientID), number: quote.number,
                         amount: quote.totals.total, due: quote.validUntil)
    }

    public func mailDraft(forInvoice id: UUID) -> MailDraft? {
        guard let invoice = invoice(id) else { return nil }
        return mailDraft(brand.emails.invoice, client: client(invoice.clientID), number: invoice.number,
                         amount: invoice.amount, due: invoice.due)
    }

    public func mailDraft(forReceipt id: UUID) -> MailDraft? {
        guard let invoice = invoice(id) else { return nil }
        return mailDraft(brand.emails.receipt, client: client(invoice.clientID), number: invoice.number,
                         amount: invoice.paid, due: invoice.due)
    }

    /// Fills {client}, {contact}, {number}, {amount}, {due} and {business}.
    private func mailDraft(_ template: EmailTemplate, client: Client?, number: String, amount: Money, due: Day) -> MailDraft {
        let filled = template.filled([
            "client": client?.name ?? "",
            "contact": client?.greetingName ?? "there",
            "number": number,
            "amount": amount.formatted(currencyCode: brand.currencyCode),
            "due": due.long,
            "business": brand.businessName,
        ])
        return MailDraft(to: (client?.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                         subject: filled.subject, body: filled.body)
    }
}
