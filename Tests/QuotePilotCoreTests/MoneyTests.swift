import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct MoneyTests {
    @Test func formatsAustralianDollars() {
        #expect(Money(dollars: 1500).formatted() == "$1,500.00")
        #expect(Money(cents: 5).formatted() == "$0.05")
    }

    @Test func multipliesByAQuantityAndRoundsHalfUp() {
        #expect(Money(dollars: 40).times(1.5) == Money(dollars: 60))
        #expect(Money(cents: 333).times(0.5) == Money(cents: 167))   // 166.5 → 167
        #expect(Money(cents: 101).times(0.25) == Money(cents: 25))   // 25.25 → 25
    }

    @Test func percentagesRoundHalfUp() {
        #expect(Money(cents: 150_001).percent(50) == Money(cents: 75_001))  // 75,000.5 → 75,001
        #expect(Money(dollars: 1500).percent(10) == Money(dollars: 150))
    }

    @Test func parsesWhatPeopleType() {
        #expect(Money(parsing: "1500") == Money(dollars: 1500))
        #expect(Money(parsing: "$1,500.50") == Money(cents: 150_050))
        #expect(Money(parsing: "12.345") == Money(cents: 1235))
        #expect(Money(parsing: "") == nil)
        #expect(Money(parsing: "abc") == nil)
    }

    @Test func plainTextForSpreadsheets() {
        #expect(Money(cents: 75_000).plain == "750.00")
        #expect(Money(cents: 5).plain == "0.05")
        #expect(Money(cents: -1250).plain == "-12.50")
    }

    @Test func addsAndSubtracts() {
        var total = Money(dollars: 10)
        total += Money(cents: 50)
        total -= Money(dollars: 1)
        #expect(total == Money(cents: 950))
        #expect(Money(dollars: 1) < Money(dollars: 2))
    }

    @Test func encodesAsWholeCents() throws {
        let data = try JSONEncoder().encode([Money(cents: 1234)])
        #expect(String(decoding: data, as: UTF8.self) == "[1234]")
        #expect(try JSONDecoder().decode([Money].self, from: data) == [Money(cents: 1234)])
    }
}
