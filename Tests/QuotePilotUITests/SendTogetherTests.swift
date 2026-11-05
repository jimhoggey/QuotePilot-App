import AppKit
import Foundation
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// Send Together: draft invoices for one client, chosen in the Dashboard's Drafts list, go out in one
/// email with a PDF each and a list with the total.
@MainActor
@Suite struct SendTogetherTests {
    /// The sample with two draft invoices for one client: INV-0004 Logo files $220, INV-0005 Website
    /// updates $450.
    func model(mail: FakeMail = FakeMail()) throws -> (AppModel, [UUID]) {
        let model = try UIFixture.sampleModel(mail: mail)
        let client = try #require(model.library.clients.first { !$0.email.isEmpty })
        var ids: [UUID] = []
        for (title, dollars) in [("Logo files", 220), ("Website updates", 450)] {
            _ = model.change("") { library in
                var invoice = library.newInvoice(on: model.today, clientID: client.id)
                invoice.title = title
                invoice.lines = [LineItem(title: title, rate: Money(dollars: dollars))]
                try library.update(invoice)
                ids.append(invoice.id)
            }
        }
        return (model, ids)
    }

    @Test func onlyTwoOrMoreDraftsForOneClientGoTogether() throws {
        let (model, ids) = try model()
        #expect(model.togetherDocument(Set(ids)) == .invoices(ids))
        #expect(model.togetherDocument([ids[0]]) == nil, "one invoice is sent on its own")
        let other = try #require(model.library.clients.first { $0.id != model.library.invoice(ids[0])?.clientID })
        _ = model.change("") { library in
            var invoice = try #require(library.invoice(ids[1]))
            invoice.clientID = other.id
            try library.update(invoice)
        }
        #expect(model.togetherDocument(Set(ids)) == nil, "two clients")
        let sent = try #require(model.library.invoices.first { $0.stage == .sent })
        #expect(model.togetherDocument([ids[0], sent.id]) == nil, "only drafts")
    }

    @Test func oneDraftCarriesEveryPDFAndTheTotal() throws {
        let mail = FakeMail()
        let (model, ids) = try model(mail: mail)
        model.send(.invoices(ids))
        let draft = try #require(mail.drafts.first)
        #expect(mail.drafts.count == 1)
        #expect(draft.attachments.map(\.lastPathComponent).allSatisfy { $0.hasSuffix(".pdf") })
        #expect(draft.attachments.count == 2)
        #expect(draft.attachments.allSatisfy { $0.path.hasPrefix(model.sentFolder.path) })
        #expect(draft.subject == "Invoices from Sample Studio")
        #expect(draft.body.contains("Attached are 2 invoices:"))
        #expect(draft.body.contains("• INV-0004, Logo files, $220.00, due "))
        #expect(draft.body.contains("• INV-0005, Website updates, $450.00, due "))
        #expect(draft.body.contains("Total: $670.00."))
        #expect(model.message?.text.hasPrefix("Quote Pilot opened a Mail draft of invoices INV-0004 and INV-0005") == true)
    }

    @Test func yesMarksEveryInvoiceSentAndNotYetNone() throws {
        let (model, ids) = try model()
        model.send(.invoices(ids))
        model.respond(try #require(model.message?.choices.first { $0.isCancel }))
        #expect(ids.allSatisfy { model.library.invoice($0)?.stage == .draft })

        model.send(.invoices(ids))
        model.respond(try #require(model.message?.choices.first { $0.isDefault }))
        #expect(ids.allSatisfy { model.library.invoice($0)?.stage == .sent })
        #expect(model.dashboard.drafts.filter { ids.contains($0.id) }.isEmpty)
        #expect(model.section == .dashboard)
    }

    @Test func theNamesReadAsAList() {
        #expect(AppModel.list(["INV-0004"]) == "INV-0004")
        #expect(AppModel.list(["INV-0004", "INV-0005"]) == "INV-0004 and INV-0005")
        #expect(AppModel.list(["INV-0004", "INV-0005", "INV-0006"]) == "INV-0004, INV-0005 and INV-0006")
    }

    /// ⌘-click adds or removes a row, ⇧-click takes the range from the anchor, a plain click one row.
    @Test func clicksChooseRowsAsInWindows() {
        let ids = ["a", "b", "c", "d"]
        let click = { (row: String, chosen: Set<String>, modifiers: NSEvent.ModifierFlags) in
            DetailsLayout.chosen(clicking: row, in: ids, chosen: chosen, anchor: "b", modifiers: modifiers)
        }
        #expect(click("c", ["b"], []) == ["c"])
        #expect(click("d", ["b"], .command) == ["b", "d"])
        #expect(click("b", ["b", "d"], .command) == ["d"])
        #expect(click("d", ["a"], .shift) == ["b", "c", "d"])
        #expect(click("a", [], .shift) == ["a", "b"])
    }

    /// Libraries from before Send Together get the standard wording for it.
    @Test func anOlderLibraryGetsTheStandardWording() throws {
        let old = #"{"quote":{"subject":"Q","body":"B"},"invoice":{"subject":"I","body":"B"},"receipt":{"subject":"R","body":"B"}}"#
        let templates = try JSONDecoder().decode(EmailTemplates.self, from: Data(old.utf8))
        #expect(templates.quote.subject == "Q")
        #expect(templates.together == EmailTemplates.standard.together)
    }
}
