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

    /// Send Together: one email to the invoices' client, listing each invoice by number with its title,
    /// amount and due date ("• INV-0004, Website updates, $750.00, due 19 November 2026"), and the total.
    /// The invoices are listed in the order given, the order of their PDFs. Nil when one is missing.
    public func mailDraft(forInvoices ids: [UUID]) -> MailDraft? {
        let found = ids.compactMap(invoice)
        guard found.count == ids.count, let first = found.first else { return nil }
        return mailDraft(brand.emails.together, client: client(first.clientID), [
            "count": String(found.count),
            "list": list(found) { money($0.amount) },
            "amount": money(found.reduce(.zero) { $0 + $1.amount }),
        ])
    }

    /// A statement for the client: each invoice still owing ("• INV-0004, Website updates, $750.00
    /// owing, due 19 November 2026") and the total owing. Nil when nothing is owing.
    public func mailDraft(forStatement clientID: UUID) -> MailDraft? {
        let owing = owingInvoices(forClient: clientID)
        guard !owing.isEmpty else { return nil }
        return mailDraft(brand.emails.statement, client: client(clientID), [
            "count": String(owing.count),
            "list": list(owing) { "\(money($0.owing)) owing" },
            "amount": money(owing.reduce(.zero) { $0 + $1.owing }),
        ])
    }

    /// One line per invoice: its number, title, `amount` and due date.
    private func list(_ invoices: [Invoice], amount: (Invoice) -> String) -> String {
        invoices.map { invoice in
            "• " + [invoice.number, invoice.title.trimmingCharacters(in: .whitespacesAndNewlines), amount(invoice),
                    "due \(invoice.due.long)"].filter { !$0.isEmpty }.joined(separator: ", ")
        }.joined(separator: "\n")
    }

    private func money(_ amount: Money) -> String { amount.formatted(currencyCode: brand.currencyCode) }

    /// Fills {number}, {amount} and {due}, and the rest that every email has.
    private func mailDraft(_ template: EmailTemplate, client: Client?, number: String, amount: Money, due: Day) -> MailDraft {
        mailDraft(template, client: client, ["number": number, "amount": money(amount), "due": due.long])
    }

    /// Fills `values`, and {client}, {contact} and {business}.
    private func mailDraft(_ template: EmailTemplate, client: Client?, _ values: [String: String]) -> MailDraft {
        let filled = template.filled(values.merging([
            "client": client?.name ?? "",
            "contact": client?.greetingName ?? "there",
            "business": brand.businessName,
        ]) { $1 })
        return MailDraft(to: (client?.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                         subject: filled.subject, body: filled.body)
    }
}
