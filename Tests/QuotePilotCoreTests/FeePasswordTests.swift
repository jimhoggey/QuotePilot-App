import Foundation
import Testing
@testable import QuotePilotCore

/// The password on the Quote Pilot fee's settings, and the fee's rows following its tick. Made-up data.
@Suite struct FeePasswordTests {
    @Test func onlyTheChosenPasswordOpensIt() throws {
        let lock = AppFeeLock(password: "Sample pass 1")
        #expect(lock.opens(with: "Sample pass 1"))
        #expect(!lock.opens(with: "sample pass 1"))
        #expect(!lock.opens(with: ""))
        #expect(!lock.hash.contains("Sample"), "only a fingerprint is kept")
        #expect(AppFeeLock(password: "Sample pass 1").hash != lock.hash, "each lock has its own salt")
    }

    /// The lock is saved with the library; one saved before it existed opens with none.
    @Test func theLockIsSavedAndOldLibrariesHaveNone() throws {
        var fee = AppFee()
        fee.lock = AppFeeLock(password: "Sample pass 1")
        let saved = try JSONDecoder().decode(AppFee.self, from: JSONEncoder().encode(fee))
        #expect(saved.lock?.opens(with: "Sample pass 1") == true)

        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fee)) as? [String: Any] ?? [:]
        json["lock"] = nil
        let old = try JSONDecoder().decode(AppFee.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.lock == nil)
    }

    /// With the fee turned off, Quote Pilot is no expense: no rows, nothing in the pie or the money
    /// record. Turned back on, the months marked paid count again.
    @Test func turningTheFeeOffLeavesItsRowsOut() throws {
        var library = Library()
        let paidOn = Day(year: 2026, month: 11, day: 2)
        library.brand.appFee.paidMonths["2026-10"] = AppFeePaid(on: paidOn, amount: Money(cents: 2790))
        let year = FinancialYear(containing: paidOn)
        #expect(library.feeExpenses.count == 1)
        #expect(library.profit(in: year).expenses == Money(cents: 2790))

        library.brand.appFee.calculates = false
        #expect(library.feeExpenses.isEmpty)
        #expect(library.feePaid(forExpense: Library.feeExpenseID(CalendarMonth(year: 2026, month: 10))) == nil)
        #expect(library.profit(in: year).expenses == .zero)
        #expect(!library.moneyRecordCSV(for: year).contains("Quote Pilot fee paid"))

        library.brand.appFee.calculates = true
        #expect(library.feeExpenses.count == 1, "kept, and back")
    }
}
