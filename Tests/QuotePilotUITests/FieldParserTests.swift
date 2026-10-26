import Foundation
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@Suite struct FieldParserTests {
    @Test func moneyTakesWhatPeopleType() {
        #expect(FieldParser.money("1500") == Money(dollars: 1500))
        #expect(FieldParser.money("$1,500.50") == Money(dollars: 1500, cents: 50))
        #expect(FieldParser.money(" 90 ") == Money(dollars: 90))
        #expect(FieldParser.money("-20") == Money(dollars: -20))
    }

    @Test func moneyRefusesHalfTypedAndNonsense() {
        for text in ["", "$", "abc", "1.2.3", "$-", "12abc"] {
            #expect(FieldParser.money(text) == nil, "\(text)")
        }
    }

    /// Two lines with a huge rate would add past Int.max cents and trap, on every launch after the
    /// save. So an amount is held to $10,000,000 either way.
    @Test func moneyStopsAtTenMillionDollars() {
        #expect(FieldParser.money("10000000") == Money(dollars: 10_000_000))
        #expect(FieldParser.money("-10000000") == Money(dollars: -10_000_000))
        for text in ["10000000.01", "-10000000.01", "50000000000000000", "-50000000000000000",
                     "92233720368547758.07", "-92233720368547758.08"] {
            #expect(FieldParser.money(text) == nil, "\(text)")
        }
    }

    /// The hourly rate is a line's rate with no discounts: $0 up to $10,000,000, or blank for none.
    @Test func anHourlyRateIsZeroUpToTenMillionOrBlank() {
        #expect(FieldParser.amountOrBlank("95") == Money(dollars: 95))
        #expect(FieldParser.amountOrBlank("$1,250.50") == Money(dollars: 1250, cents: 50))
        #expect(FieldParser.amountOrBlank("0") == .zero)
        #expect(FieldParser.amountOrBlank("") == .zero)
        #expect(FieldParser.amountOrBlank("  ") == .zero)
        #expect(FieldParser.amountOrBlank("10000000") == Money(dollars: 10_000_000))
        for text in ["abc", "-20", "-0.01", "$", "1.2.3", "10000000.01", "50000000000000000"] {
            #expect(FieldParser.amountOrBlank(text) == nil, "\(text)")
        }
    }

    @Test func quantityTakesUpToTwoDecimalPlaces() {
        #expect(FieldParser.quantity("1") == 1)
        #expect(FieldParser.quantity("1.5") == Decimal(string: "1.5"))
        #expect(FieldParser.quantity("0.25") == Decimal(string: "0.25"))
        #expect(FieldParser.quantity("0") == 0)
    }

    @Test func quantityRefusesHalfTypedAndNonsense() {
        for text in ["", "1.", ".5", "-1", "1.234", "1e3", "abc", "1,5", "100001"] {
            #expect(FieldParser.quantity(text) == nil, "\(text)")
        }
    }

    @Test func daysAreWholeNumbersUpToAYear() {
        #expect(FieldParser.days("14") == 14)
        #expect(FieldParser.days("0") == 0)
        for text in ["", "-1", "1.5", "366", "two"] {
            #expect(FieldParser.days(text) == nil, "\(text)")
        }
    }

    @Test func coloursAreSixHexDigits() {
        #expect(FieldParser.hex("0b6b66") == "#0B6B66")
        #expect(FieldParser.hex("#C00000") == "#C00000")
        for text in ["", "#12345", "zzzzzz", "#1234567", "##0B6B66"] {
            #expect(FieldParser.hex(text) == nil, "\(text)")
        }
    }

    /// Fullwidth digits and letters count as hex digits to Character, but not in a colour.
    @Test func coloursRefuseFullwidthDigits() {
        #expect(FieldParser.hex("\u{FF10}B6B66") == nil)
        #expect(FieldParser.hex("#\u{FF21}\u{FF22}\u{FF23}\u{FF24}\u{FF25}\u{FF26}") == nil)
    }

    @Test func quantitiesShowWithoutTrailingZeros() {
        #expect(FieldParser.quantityText(Decimal(string: "1.5")!) == "1.5")
        #expect(FieldParser.quantityText(2) == "2")
    }
}
