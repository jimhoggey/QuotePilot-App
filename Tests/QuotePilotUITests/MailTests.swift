import Foundation
import PDFKit
import SwiftUI
import Testing
import QuotePilotCore
import QuotePilotPDF
@testable import QuotePilotUI

@MainActor
@Suite struct MailTests {
    /// The sample business's draft quote Q-0004, for Example Bakery (alex@example.com).
    func draftQuote(_ model: AppModel) throws -> UUID {
        try #require(model.library.quote(number: "Q-0004")?.id)
    }

    @Test func sendingAQuoteOpensADraftWithItsPDF() throws {
        let mail = FakeMail()
        let model = try UIFixture.sampleModel(mail: mail)
        let id = try draftQuote(model)
        model.send(.quote(id))
        let draft = try #require(mail.drafts.first)
        #expect(draft.to == "alex@example.com")
        #expect(draft.subject == "Quote Q-0004 from Sample Studio")
        #expect(draft.body.hasPrefix("Hi Alex,"))
        #expect(draft.attachment.path.hasPrefix(model.sentFolder.path))
        #expect(draft.attachment.deletingLastPathComponent().lastPathComponent == "2026")
        let data = try Data(contentsOf: draft.attachment)
        #expect(DocumentRenderer.hasForm(data, quoteNumber: "Q-0004"))
        #expect(model.message?.title == "Did You Send It?")
        #expect(model.library.quote(id)?.stage == .draft)
        #expect(model.library.activity.first?.message.hasPrefix("Opened a Mail draft of quote Q-0004") == true)
    }

    @Test func yesMarksItSent() throws {
        let model = try UIFixture.sampleModel()
        let id = try draftQuote(model)
        model.send(.quote(id))
        let box = try #require(model.message)
        model.respond(try #require(box.choices.first { $0.isDefault }))
        #expect(model.library.quote(id)?.stage == .sent)
        #expect(model.library.quote(id)?.sentAt != nil)
    }

    @Test func notYetChangesNothing() throws {
        let model = try UIFixture.sampleModel()
        let id = try draftQuote(model)
        let before = try #require(model.library.quote(id))
        model.send(.quote(id))
        let box = try #require(model.message)
        model.respond(try #require(box.choices.first { $0.isCancel }))
        #expect(model.library.quote(id) == before)
    }

    @Test func aMissingEmailIsAskedForFirst() throws {
        let mail = FakeMail()
        var library = try SampleLibrary.make(today: UIFixture.today, now: UIFixture.today.date())
        let bakery = try #require(library.clients.firstIndex { $0.name == "Example Bakery" })
        library.clients[bakery].email = ""
        let model = try UIFixture.model(library, mail: mail)
        let id = try draftQuote(model)
        model.send(.quote(id))
        #expect(mail.drafts.isEmpty)
        guard case .emailPrompt(let clientID, let document) = model.dialog else {
            Issue.record("Expected the email prompt")
            return
        }
        #expect(!AppModel.looksLikeEmail("not an email"))
        model.saveEmailAndSend("orders@example.com", clientID: clientID, document: document)
        #expect(model.dialog == nil)
        #expect(model.library.client(clientID)?.email == "orders@example.com")
        #expect(mail.drafts.first?.to == "orders@example.com")
    }

    @Test func whenMailIsntAvailableThePDFAndMessageAreSetAside() throws {
        let mail = FakeMail()
        mail.available = false
        let model = try UIFixture.sampleModel(mail: mail)
        model.send(.quote(try draftQuote(model)))
        let aside = try #require(mail.setAside.first)
        #expect(aside.message.contains("Subject: Quote Q-0004 from Sample Studio"))
        #expect(aside.message.contains("To: alex@example.com"))
        #expect(model.message?.text.contains("clipboard") == true)
    }

    @Test func receiptsNeedAPaymentAndVoidInvoicesCantBeSent() throws {
        let mail = FakeMail()
        var library = try SampleLibrary.make(today: UIFixture.today, now: UIFixture.today.date())
        let care = try #require(library.invoices.first { $0.number == "INV-0002" })
        let model = try UIFixture.model(library, mail: mail)
        model.send(.receipt(care.id))
        #expect(mail.drafts.isEmpty)
        #expect(model.message?.text == LibraryError.noPayments.message)

        try library.voidInvoice(care.id)
        let voided = try UIFixture.model(library, mail: mail)
        voided.send(.invoice(care.id))
        #expect(mail.drafts.isEmpty)
        #expect(voided.message?.text == LibraryError.isVoid.message)
    }

    @Test func theEmailPromptDraws() throws {
        let model = try UIFixture.sampleModel()
        let client = try #require(model.library.clients.first)
        model.dialog = .emailPrompt(clientID: client.id, document: .quote(model.library.quotes[3].id))
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "email-prompt")
        #expect(rep.map(Snapshot.hasContent) == true)    }

    @Test func anOpenDialogBlocksMenuCommands() throws {
        let model = try UIFixture.sampleModel()
        model.dialog = .emailPrompt(clientID: model.library.clients[0].id, document: .quote(model.library.quotes[3].id))
        var beeps = 0
        model.beep = { beeps += 1 }
        var ran = false
        model.whenFree { ran = true }
        #expect(!ran)
        #expect(beeps == 1)
    }
}
