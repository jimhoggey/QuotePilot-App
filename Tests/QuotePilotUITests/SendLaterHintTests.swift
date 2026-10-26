import Foundation
import QuotePilotCore
import Testing
@testable import QuotePilotUI

/// Out of hours, "Did You Send It?" points at Mail's Send Later; in hours it says nothing more.
@MainActor
@Suite struct SendLaterHintTests {
    func time(_ day: Day, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute))!
    }

    @Test func workingHoursAreWeekdaysEightToFive() {
        let thursday = Day(year: 2026, month: 10, day: 15)
        #expect(!AppModel.isOutsideWorkingHours(time(thursday, 8)))
        #expect(!AppModel.isOutsideWorkingHours(time(thursday, 16, 59)))
        #expect(AppModel.isOutsideWorkingHours(time(thursday, 7, 59)))
        #expect(AppModel.isOutsideWorkingHours(time(thursday, 17)))
        #expect(AppModel.isOutsideWorkingHours(time(thursday, 21)))
        #expect(AppModel.isOutsideWorkingHours(time(Day(year: 2026, month: 10, day: 17), 11)), "a Saturday")
    }

    /// The sample business's first sent invoice with a payment, sent as a receipt at `hour`.
    func receiptQuestion(at hour: Int) throws -> String? {
        let library = try SampleLibrary.make(today: UIFixture.today, now: UIFixture.today.date())
        let store = LibraryStore(folder: UIFixture.makeFolder())
        try store.save(library)
        let at = time(UIFixture.today, hour)
        let model = AppModel(store: store, now: { at }, mail: FakeMail(), sentFolder: UIFixture.makeFolder())
        model.updates = UpdateFixture.offline()
        let invoice = try #require(model.library.invoices.first {
            !$0.payments.isEmpty && model.library.client($0.clientID ?? UUID())?.email.isEmpty == false
        })
        model.send(.receipt(invoice.id))
        return model.message?.text
    }

    @Test func outOfHoursTheQuestionPointsAtSendLater() throws {
        let evening = try #require(try receiptQuestion(at: 19))
        #expect(evening.hasSuffix("Did you send it? " + AppModel.sendLaterHint))
        let midday = try #require(try receiptQuestion(at: 12))
        #expect(midday.hasSuffix("Did you send it?"))
    }
}
