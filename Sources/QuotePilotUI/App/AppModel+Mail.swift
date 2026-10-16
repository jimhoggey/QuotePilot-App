import Foundation
import QuotePilotCore
import QuotePilotPDF

extension AppModel {
    /// What ⌘S sends: the open quote on Quotes, the open or selected invoice on Invoices. A void
    /// invoice no longer counts, and a quote or invoice with no client has nobody to write to, so
    /// nothing is sent for either: the menu item, ⌘S and the toolbar's Send are greyed out, and the
    /// editor's button too. (`send` still says "No Client" if it is reached some other way.)
    public var sendableDocument: MailDocument? {
        switch section {
        case .quotes:
            guard let id = openQuoteID ?? selectedQuoteID, library.quote(id)?.clientID != nil else { return nil }
            return .quote(id)
        case .invoices:
            guard let id = editingInvoiceID ?? selectedInvoiceID, let invoice = library.invoice(id),
                  invoice.stage != .void, invoice.clientID != nil else { return nil }
            return .invoice(id)
        default: return nil
        }
    }

    /// Saves the PDF to the sent folder, opens a Mail draft, then asks "Did you send it?". Yes marks
    /// the document Sent; Not Yet changes nothing.
    public func send(_ document: MailDocument) {
        guard loadState == .ready else { return }
        // What can't be sent says so before anything is written.
        switch document {
        case .quote:
            break
        case .invoice(let id):
            if library.invoice(id)?.stage == .void { return show(LibraryError.isVoid, title: "Can't Send") }
        case .receipt(let id):
            if library.invoice(id)?.payments.isEmpty ?? true { return show(LibraryError.noPayments, title: "Can't Send") }
        }
        guard let parts = mailParts(document) else { return }
        let (number, what, draft, content) = (parts.number, parts.what, parts.draft, parts.content)
        guard let clientID = parts.clientID else {
            return show(title: "No Client", text: "\(what.capitalizedFirst) \(number) has no client yet. Choose one first.", kind: .warning)
        }
        guard !draft.to.isEmpty else {
            dialog = .emailPrompt(clientID: clientID, document: document)
            return
        }
        let data = pdf(content)
        if case .quote = document, !DocumentRenderer.hasForm(data, quoteNumber: number) {
            return show(title: "Quote Not Sent",
                        text: "Quote Pilot couldn't add the tick boxes to \(number)'s PDF, so it isn't safe to send. Nothing was changed.",
                        kind: .warning)
        }
        let url = SentArchive.freshURL(for: content.fileName, year: today.year, in: sentFolder)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            return show(error, title: "Couldn't save the PDF to send")
        }

        let question: String
        if mail.compose(to: draft.to, subject: draft.subject, body: draft.body, attachment: url) {
            change("Couldn't note the Mail draft") { $0.log("Opened a Mail draft of \(what) \(number) to \(draft.to)", number: number) }
            question = "Quote Pilot opened a Mail draft of \(what) \(number) to \(draft.to). Did you send it?"
        } else {
            mail.setAside(message: "To: \(draft.to)\nSubject: \(draft.subject)\n\n\(draft.body)", attachment: url)
            change("Couldn't note the Mail problem") {
                $0.log("Mail couldn't open a draft of \(what) \(number); the PDF and message were set aside", number: number)
            }
            question = "Mail couldn't open a draft. The PDF is shown in Finder and the message is on the clipboard, ready to paste into any email app. Did you send \(what) \(number)?"
        }
        message = MessageBox(kind: .question, title: "Did You Send It?", text: question, choices: [
            MessageBox.Choice("Yes, Sent", isDefault: true) { self.markSent(document) },
            MessageBox.Choice("Not Yet", isCancel: true),
        ])
    }

    /// Saves the client's email, then carries on sending.
    public func saveEmailAndSend(_ email: String, clientID: UUID, document: MailDocument) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppModel.looksLikeEmail(trimmed), var client = library.client(clientID) else {
            return show(title: "Email Address", text: "That doesn't look like an email address.", kind: .warning)
        }
        client.email = trimmed
        updateClient(client)
        guard library.client(clientID)?.email == trimmed else { return }
        dialog = nil
        send(document)
    }

    /// One "@", something before it, and a dot after it, with no spaces.
    public static func looksLikeEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasSuffix(".")
            && !text.contains(where: \.isWhitespace)
    }

    /// "Yes, Sent". A quote or an invoice that is now sent has nothing left to change on its page, so
    /// its editor closes and the Dashboard shows, with a note in the status bar. A receipt leaves you
    /// where you are with its note. When the save fails, the message box says so and nothing moves.
    private func markSent(_ document: MailDocument) {
        switch document {
        case .quote(let id):
            guard change("Couldn't mark it sent", { try $0.markSent(quote: id, at: now()) }),
                  let number = library.quote(id)?.number else { return }
            openQuoteID = nil
            go(to: .dashboard)
            note("\(number) marked as sent")
        case .invoice(let id):
            guard change("Couldn't mark it sent", { try $0.markSent(invoice: id, at: now()) }),
                  let number = library.invoice(id)?.number else { return }
            openInvoiceID = nil
            go(to: .dashboard)
            note("\(number) marked as sent")
        case .receipt(let id):
            guard change("Couldn't mark it sent", { try $0.markReceiptSent(invoice: id, at: now()) }),
                  let number = library.invoice(id)?.number else { return }
            note("Receipt for \(number) marked as sent")
        }
    }

    /// The number, a word for it, its client, the Mail wording and the PDF content.
    private func mailParts(_ document: MailDocument)
        -> (number: String, what: String, clientID: UUID?, draft: MailDraft, content: DocumentContent)? {
        switch document {
        case .quote(let id):
            guard let quote = library.quote(id), let draft = library.mailDraft(forQuote: id),
                  let content = quoteContent(id) else { return nil }
            return (quote.number, "quote", quote.clientID, draft, content)
        case .invoice(let id):
            guard let invoice = library.invoice(id), let draft = library.mailDraft(forInvoice: id),
                  let content = invoiceContent(id) else { return nil }
            return (invoice.number, "invoice", invoice.clientID, draft, content)
        case .receipt(let id):
            guard let invoice = library.invoice(id), let draft = library.mailDraft(forReceipt: id) else { return nil }
            let content = DocumentContent.receipt(invoice, client: library.client(invoice.clientID), brand: library.brand)
            return (invoice.number, "the receipt for", invoice.clientID, draft, content)
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
