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

    @Test func quantitiesShowWithoutTrailingZeros() {
        #expect(FieldParser.quantityText(Decimal(string: "1.5")!) == "1.5")
        #expect(FieldParser.quantityText(2) == "2")
    }
}
