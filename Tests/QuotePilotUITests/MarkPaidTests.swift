import Foundation
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// The Dashboard's Mark Paid: choose invoices waiting to be paid, right-click, and each gets a payment
/// of what it owes, today, by bank transfer, after one question.
@MainActor
@Suite struct MarkPaidTests {
    func invoice(_ model: AppModel, _ number: String) throws -> Invoice {
        try #require(model.library.invoices.first { $0.number == number })
    }

    @Test func itAsksOnceThenPaysEachInFull() throws {
        let model = try UIFixture.sampleModel()
        let care = try invoice(model, "INV-0002"), hosting = try invoice(model, "INV-0003")
        let total = model.money(care.owing + hosting.owing)
        model.markPaid([hosting.id, care.id])
        let box = try #require(model.message)
        #expect(box.title == "Mark Paid")
        #expect(box.text == "Mark INV-0002 and INV-0003 paid? This records \(total) received today by bank transfer.")
        #expect(try invoice(model, "INV-0002").owing == care.owing, "nothing is recorded until you say so")

        model.respond(try #require(box.choices.first { $0.title == "Mark Paid" }))
        for number in ["INV-0002", "INV-0003"] {
            let paid = try invoice(model, number)
            #expect(paid.owing == .zero)
            #expect(paid.payments.last?.date == model.today)
            #expect(paid.payments.last?.method == .bankTransfer)
        }
        #expect(model.statusNote?.text == "Recorded \(total) for INV-0002 and INV-0003")
        #expect(!model.dashboard.waiting.contains { [care.id, hosting.id].contains($0.invoiceID) })
    }

    @Test func cancelRecordsNothingAndOnlyWhatsOwingCounts() throws {
        let model = try UIFixture.sampleModel()
        let paid = try invoice(model, "INV-0001"), care = try invoice(model, "INV-0002")
        model.markPaid([paid.id])
        #expect(model.message == nil, "nothing owing, nothing to ask")
        model.markPaid([paid.id, care.id])
        let box = try #require(model.message)
        #expect(box.text.hasPrefix("Mark INV-0002 paid?"))
        model.respond(try #require(box.choices.first { $0.title == "Cancel" }))
        #expect(try invoice(model, "INV-0002").payments == care.payments)
    }

    @Test func theFeeLockAsksNothing() throws {
        let model = try FeeBarTests().lockedModel()
        model.markPaid(Set(model.library.invoices.map(\.id)))
        #expect(model.message == nil)
    }

    @Test func theMenuSaysHowMany() {
        #expect(DashboardView.markPaidTitle(1) == "Mark Paid")
        #expect(DashboardView.markPaidTitle(3) == "Mark 3 Paid")
    }
}
