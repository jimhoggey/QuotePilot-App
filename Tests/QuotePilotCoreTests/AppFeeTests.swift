import Foundation
import Testing
@testable import QuotePilotCore

/// The Quote Pilot fee: a figure only, worked out from the payments recorded each calendar month.
@Suite struct AppFeeTests {
    let today = Fixture.today  // 15 Oct 2026

    /// One sent one-off invoice per payment, so each can be any amount on any day. Made-up amounts.
    func library(payments: [(Day, Money)], fee: AppFee = AppFee()) throws -> Library {
        var library = Library()
        library.brand.appFee = fee
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

    @Test func threePercentOf750Is2250() throws {
        #expect(AppFee(percent: 3).fee(on: Money(dollars: 750)) == Money(dollars: 22, cents: 50))
        let figures = try #require(AppFeeFigures(library: library(payments: [(today, Money(dollars: 750))]), today: today))
        #expect(figures.percent == 3)
        #expect(figures.receivedThisMonth == Money(dollars: 750))
        #expect(figures.feeThisMonth == Money(dollars: 22, cents: 50))
        #expect(figures.receivedLastMonth == .zero)
        #expect(figures.feeLastMonth == .zero)
    }

    @Test func theFeeIsRoundedHalfUpToTheCent() {
        // 2.5% of 20c is half a cent: up to 1c. 3% of 50c is 1.5c: up to 2c.
        #expect(AppFee(percent: 2.5).fee(on: Money(cents: 20)) == Money(cents: 1))
        #expect(AppFee(percent: 3).fee(on: Money(cents: 50)) == Money(cents: 2))
        // 2.5% of $10.10 is 25.25c: down to 25c.
        #expect(AppFee(percent: 2.5).fee(on: Money(dollars: 10, cents: 10)) == Money(cents: 25))
        #expect(AppFee(percent: 2.5).fee(on: Money(dollars: 1_000)) == Money(dollars: 25))
    }

    @Test func zeroAndOneHundredPercent() {
        #expect(AppFee(percent: 0).fee(on: Money(dollars: 750)) == .zero)
        #expect(AppFee(percent: 100).fee(on: Money(dollars: 750)) == Money(dollars: 750))
        #expect(AppFee(percent: 100).fee(on: Money(dollars: 12, cents: 34)) == Money(dollars: 12, cents: 34))
    }

    /// Only payments dated in the calendar month count: 1 Oct and 31 Oct are this month, 30 Sep is
    /// last month, and 31 Aug and 1 Nov are neither.
    @Test func monthBoundaries() throws {
        let library = try library(payments: [
            (Day(year: 2026, month: 8, day: 31), Money(dollars: 1)),
            (Day(year: 2026, month: 9, day: 1), Money(dollars: 10)),
            (Day(year: 2026, month: 9, day: 30), Money(dollars: 20)),
            (Day(year: 2026, month: 10, day: 1), Money(dollars: 100)),
            (Day(year: 2026, month: 10, day: 31), Money(dollars: 200)),
            (Day(year: 2026, month: 11, day: 1), Money(dollars: 1_000)),
        ])
        let figures = try #require(AppFeeFigures(library: library, today: today))
        #expect(figures.receivedThisMonth == Money(dollars: 300))
        #expect(figures.feeThisMonth == Money(dollars: 9))
        #expect(figures.receivedLastMonth == Money(dollars: 30))
        #expect(figures.feeLastMonth == Money(cents: 90))
    }

    /// In January, last month is December of the year before.
    @Test func januarysLastMonthIsTheDecemberBefore() throws {
        let library = try library(payments: [
            (Day(year: 2025, month: 12, day: 31), Money(dollars: 400)),
            (Day(year: 2026, month: 12, day: 15), Money(dollars: 999)),
            (Day(year: 2027, month: 1, day: 1), Money(dollars: 50)),
        ])
        let figures = try #require(AppFeeFigures(library: library, today: Day(year: 2027, month: 1, day: 20)))
        #expect(figures.receivedThisMonth == Money(dollars: 50))
        #expect(figures.receivedLastMonth == Money(dollars: 999))
        #expect(CalendarMonth(year: 2027, month: 1).previous == CalendarMonth(year: 2026, month: 12))
        #expect(CalendarMonth(year: 2026, month: 3).previous == CalendarMonth(year: 2026, month: 2))
    }

    @Test func turnedOffThereAreNoFigures() throws {
        let library = try library(payments: [(today, Money(dollars: 750))], fee: AppFee(calculates: false))
        #expect(AppFeeFigures(library: library, today: today) == nil)
    }

    /// "Received" is the Dashboard's "This month", from the same payments.
    @Test func receivedIsTheDashboardsThisMonth() throws {
        let library = try library(payments: [(today, Money(dollars: 750)), (Day(year: 2026, month: 10, day: 2), Money(dollars: 80)),
                                             (Day(year: 2026, month: 9, day: 2), Money(dollars: 40))])
        let figures = try #require(AppFeeFigures(library: library, today: today))
        #expect(figures.receivedThisMonth == Dashboard(library: library, today: today).receivedThisMonth)
        #expect(figures.receivedThisMonth == Money(dollars: 830))
    }

    // MARK: Storage

    @Test func aNewBrandCalculatesAtThreePercent() {
        #expect(Brand().appFee == AppFee(calculates: true, percent: 3))
    }

    /// A library saved before the fee existed has no "appFee" in its brand: it opens with the fee on, at 3%.
    @Test func anOldLibraryDecodesWithTheDefaultFee() throws {
        let old = #"""
        {
          "format": 1,
          "brand": { "businessName": "Sample Studio", "accentHex": "#0B6B66", "paymentDueDays": 14 },
          "clients": [], "quotes": [], "invoices": [], "activity": [], "usedNumbers": []
        }
        """#
        let library = try Library.makeDecoder().decode(Library.self, from: Data(old.utf8))
        #expect(library.brand.businessName == "Sample Studio")
        #expect(library.brand.appFee == AppFee())
        #expect(library.problems().isEmpty)

        // Half a setting (from a later version, say) fills in the rest.
        let half = #"{ "brand": { "appFee": { "calculates": false } } }"#
        let partial = try Library.makeDecoder().decode(Library.self, from: Data(half.utf8))
        #expect(partial.brand.appFee == AppFee(calculates: false, percent: 3))
    }

    @Test func theFeeRoundTripsThroughJSON() throws {
        var library = Library()
        library.brand.appFee = AppFee(calculates: false, percent: Decimal(string: "2.5")!)
        let decoded = try Library.makeDecoder().decode(Library.self, from: Library.makeEncoder().encode(library))
        #expect(decoded.brand.appFee == library.brand.appFee)
    }

    @Test func aPercentageOutside0To100IsAProblem() {
        var library = Library()
        for fine in [Decimal(0), 3, Decimal(string: "2.5")!, 100] {
            library.brand.appFee.percent = fine
            #expect(library.problems().isEmpty, "\(fine)% is fine")
        }
        for bad in [Decimal(-1), Decimal(string: "100.01")!, 250, Decimal.nan] {
            library.brand.appFee.percent = bad
            #expect(library.problems().count == 1, "\(bad)% is refused")
            #expect(library.problems().first?.hasPrefix("Brand: the Quote Pilot fee is") == true)
        }
    }
}
