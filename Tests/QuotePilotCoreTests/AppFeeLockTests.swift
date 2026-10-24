import Foundation
import Testing
@testable import QuotePilotCore

/// The monthly fee's due dates and lock: each month's fee is due on the 1st of the next, and one
/// still unpaid from the 5th locks the app until it's marked paid. Made-up amounts.
@Suite struct AppFeeLockTests {
    /// One sent one-off invoice per payment, with the fee counting from `start`.
    func library(payments: [(Day, Money)], start: CalendarMonth = CalendarMonth(year: 2026, month: 9),
                 percent: Decimal = 3) throws -> Library {
        var library = Library()
        library.brand.appFee = AppFee(percent: percent, startMonth: start)
        let client = Client(name: "Sample Client Pty Ltd")
        library.addClient(client)
        for (day, amount) in payments {
            var invoice = library.newInvoice(on: day, clientID: client.id)
            invoice.lines = [LineItem(title: "Sample work", rate: amount)]
            try library.update(invoice)
            try library.markSent(invoice: invoice.id)
            try library.recordPayment(Payment(date: day, amount: amount), toInvoice: invoice.id)
        }
        return library
    }

    func day(_ year: Int, _ month: Int, _ day: Int) -> Day { Day(year: year, month: month, day: day) }

    @Test func dueOnTheFirstAndLockedFromTheFifth() {
        let october = CalendarMonth(year: 2026, month: 10)
        #expect(october.feeDue == day(2026, 11, 1))
        #expect(october.feeLocksOn == day(2026, 11, 5))
        // December rolls into the next year; January's previous is the December before.
        let december = CalendarMonth(year: 2026, month: 12)
        #expect(december.next == CalendarMonth(year: 2027, month: 1))
        #expect(december.feeDue == day(2027, 1, 1))
        #expect(december.feeLocksOn == day(2027, 1, 5))
        #expect(CalendarMonth(year: 2027, month: 1).previous == december)
        // February is short, but the fee is due on 1 March either way.
        #expect(CalendarMonth(year: 2028, month: 2).feeLocksOn == day(2028, 3, 5))
    }

    @Test func aClosedMonthIsDueUntilThe4thThenLocks() throws {
        let library = try library(payments: [(day(2026, 10, 20), Money(dollars: 750))])
        let fee = Money(dollars: 22, cents: 50)
        let october = CalendarMonth(year: 2026, month: 10)
        #expect(library.appFeeState(today: day(2026, 10, 31)) == .running(month: october, fee: fee, received: Money(dollars: 750)))
        for date in [day(2026, 11, 1), day(2026, 11, 4)] {
            #expect(library.appFeeState(today: date) == .due(month: october, fee: fee))
        }
        for date in [day(2026, 11, 5), day(2026, 12, 20), day(2027, 3, 1)] {
            #expect(library.appFeeState(today: date) == .locked(month: october, fee: fee))
            #expect(library.appFeeState(today: date)?.isLocked == true)
        }
    }

    @Test func aDecemberFeeLocksInTheNewYear() throws {
        let library = try library(payments: [(day(2026, 12, 31), Money(dollars: 100))])
        let december = CalendarMonth(year: 2026, month: 12)
        #expect(library.appFeeState(today: day(2027, 1, 4)) == .due(month: december, fee: Money(dollars: 3)))
        #expect(library.appFeeState(today: day(2027, 1, 5)) == .locked(month: december, fee: Money(dollars: 3)))
    }

    @Test func aZeroDollarMonthNeedsNothing() throws {
        // Nothing received in October, and 0% of what was received in September.
        var library = try library(payments: [(day(2026, 9, 10), Money(dollars: 500))])
        library.brand.appFee.percent = 0
        let november = CalendarMonth(year: 2026, month: 11)
        #expect(library.unpaidAppFeeMonths(before: november).isEmpty)
        #expect(library.appFeeState(today: day(2026, 11, 20)) == .running(month: november, fee: .zero, received: .zero))
        // 3% of 10c is 0.3c, which rounds to nothing.
        let tiny = try self.library(payments: [(day(2026, 10, 1), Money(cents: 10))])
        #expect(tiny.appFeeState(today: day(2026, 11, 20))?.isLocked == false)
    }

    @Test func onlyMonthsFromTheStartMonthCount() throws {
        let library = try library(payments: [(day(2026, 9, 10), Money(dollars: 500)), (day(2026, 10, 10), Money(dollars: 200))],
                                  start: CalendarMonth(year: 2026, month: 10))
        #expect(library.unpaidAppFeeMonths(before: CalendarMonth(year: 2026, month: 12)) == [CalendarMonth(year: 2026, month: 10)])
        #expect(library.appFeeState(today: day(2026, 11, 10)) == .locked(month: CalendarMonth(year: 2026, month: 10), fee: Money(dollars: 6)))
        // Started this month: nothing earlier is owed.
        let fresh = try self.library(payments: [(day(2026, 10, 10), Money(dollars: 200))], start: CalendarMonth(year: 2026, month: 11))
        #expect(fresh.appFeeState(today: day(2026, 11, 10)) == .running(month: CalendarMonth(year: 2026, month: 11), fee: .zero, received: .zero))
    }

    @Test func theOldestUnpaidMonthComesFirst() throws {
        let library = try library(payments: [(day(2026, 9, 10), Money(dollars: 100)), (day(2026, 10, 10), Money(dollars: 200))])
        #expect(library.unpaidAppFeeMonths(before: CalendarMonth(year: 2026, month: 11))
                == [CalendarMonth(year: 2026, month: 9), CalendarMonth(year: 2026, month: 10)])
        #expect(library.appFeeState(today: day(2026, 11, 2)) == .locked(month: CalendarMonth(year: 2026, month: 9), fee: Money(dollars: 3)))
    }

    @Test func markingItPaidClearsItAndSaysSoInActivity() throws {
        var library = try library(payments: [(day(2026, 10, 20), Money(dollars: 750))])
        let october = CalendarMonth(year: 2026, month: 10)
        #expect(library.appFeeState(today: day(2026, 11, 6))?.monthToPay == october)
        library.markAppFeePaid(october, on: day(2026, 11, 6))
        #expect(library.brand.appFee.paidMonths["2026-10"] == AppFeePaid(on: day(2026, 11, 6), amount: Money(dollars: 22, cents: 50)))
        #expect(library.appFeeState(today: day(2026, 11, 6)) == .running(month: CalendarMonth(year: 2026, month: 11), fee: .zero, received: .zero))
        #expect(library.activity.first?.message == "Marked the October 2026 Quote Pilot fee as paid ($22.50)")
    }

    @Test func turningTheFeeOffRemovesTheBarAndTheLock() throws {
        var library = try library(payments: [(day(2026, 10, 20), Money(dollars: 750))])
        #expect(library.appFeeState(today: day(2026, 11, 6))?.isLocked == true)
        library.brand.appFee.calculates = false
        #expect(library.appFeeState(today: day(2026, 11, 6)) == nil)
    }

    @Test func monthsAreStoredAsYearDashMonth() throws {
        #expect(CalendarMonth(year: 2026, month: 3).key == "2026-03")
        #expect(CalendarMonth(key: "2026-10") == CalendarMonth(year: 2026, month: 10))
        for bad in ["2026-13", "2026-00", "26-10", "2026-1", "2026/10", "", "0000-01"] {
            #expect(CalendarMonth(key: bad) == nil, "\"\(bad)\"")
        }
        #expect(CalendarMonth(year: 2026, month: 10).label == "October 2026")
        let data = try Library.makeEncoder().encode(AppFee(startMonth: CalendarMonth(year: 2026, month: 10),
                                                           paidMonths: ["2026-10": AppFeePaid(on: day(2026, 11, 2), amount: Money(cents: 2250))]))
        let back = try Library.makeDecoder().decode(AppFee.self, from: data)
        #expect(back.startMonth == CalendarMonth(year: 2026, month: 10))
        #expect(back.paidMonths["2026-10"]?.amount == Money(cents: 2250))
        #expect(String(decoding: data, as: UTF8.self).contains("\"startMonth\" : \"2026-10\""))
    }

    /// A library saved before the start month and paid months existed counts from the month it's
    /// opened in, with nothing paid: no earlier month is suddenly owed.
    @Test func anOldLibraryCountsFromThisMonth() throws {
        let json = #"{"brand": {"appFee": {"calculates": true, "percent": 3}}}"#
        let library = try Library.makeDecoder().decode(Library.self, from: Data(json.utf8))
        #expect(library.brand.appFee.startMonth == CalendarMonth.thisMonth())
        #expect(library.brand.appFee.paidMonths.isEmpty)
        #expect(library.brand.appFee.percent == 3)
    }

    @Test func aDamagedMonthDoesNotLoad() {
        let json = #"{"brand": {"appFee": {"calculates": true, "percent": 3, "startMonth": "2026-13"}}}"#
        #expect(throws: DecodingError.self) { try Library.makeDecoder().decode(Library.self, from: Data(json.utf8)) }
    }

    @Test func problemsCapAPaidFee() {
        var library = Library()
        library.brand.appFee.paidMonths["2026-10"] = AppFeePaid(on: day(2026, 11, 2), amount: Money(cents: Int.max))
        #expect(library.problems().contains { $0.contains("Quote Pilot fee paid for 2026-10") })
        library.brand.appFee.paidMonths["2026-10"] = AppFeePaid(on: day(2026, 11, 2), amount: Money(dollars: 22))
        #expect(library.problems().isEmpty)
    }
}
