import Foundation
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// Clients → Send Statement: one Mail draft with the statement PDF; "Yes, Sent" notes it in Activity.
@MainActor
@Suite struct StatementSendTests {
    @Test func aStatementGoesOutAndActivityKeepsTheRecord() throws {
        let mail = FakeMail()
        let model = try UIFixture.sampleModel(mail: mail)
        let client = try #require(model.library.clients.first {
            !$0.email.isEmpty && !model.library.owingInvoices(forClient: $0.id).isEmpty
        })
        model.go(to: .clients)
        model.send(.statement(client.id))

        let draft = try #require(mail.drafts.first)
        #expect(draft.attachments.count == 1)
        #expect(draft.attachment.lastPathComponent.hasPrefix("Statement "))
        #expect(draft.subject == "Statement from Sample Studio")
        #expect(draft.body.contains("Total owing: "))
        #expect(model.message?.text.hasPrefix("Quote Pilot opened a Mail draft of the statement for \(client.name)") == true)

        model.respond(try #require(model.message?.choices.first { $0.isDefault }))
        #expect(model.library.activity.first?.message.hasPrefix("Sent a statement to \(client.name), ") == true)
        #expect(model.section == .clients, "nothing to close, so the screen stays")
    }
}
