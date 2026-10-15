import Foundation
import Testing
@testable import QuotePilotCore

/// The remembered hourly rate: the one rule for when a line takes it (`LineItem.withHourlyRate`).
@Suite struct HourlyRateTests {
    let hourly = Money(dollars: 95)

    // MARK: A new line

    @Test func aNewLineInHoursStartsAtTheHourlyRate() {
        let line = LineItem.blank(unit: .hours, hourlyRate: hourly)
        #expect(line.unit == .hours)
        #expect(line.rate == hourly)
        #expect(line.title.isEmpty)
        #expect(line.quantity == 1)
    }

    /// With an hourly rate set, Add Line starts the line in hours at that rate.
    @Test func addLineWithAnHourlyRateStartsInHoursAtThatRate() {
        #expect(LineItem.startingUnit(hourlyRate: hourly) == .hours)
        let line = LineItem.blank(hourlyRate: hourly)
        #expect(line.unit == .hours)
        #expect(line.rate == hourly)
        #expect(line.title.isEmpty)
        #expect(line.detail.isEmpty)
        #expect(line.quantity == 1)
        #expect(line.decision == nil)
    }

    /// With no hourly rate, Add Line is what it always was: a line in units at $0. Blank or $0 on Brand
    /// is no rate at all.
    @Test func addLineWithNoHourlyRateStartsInUnitsAtNothing() {
        for noRate in [Money?.none, .some(.zero)] {
            #expect(LineItem.startingUnit(hourlyRate: noRate) == .units)
            let line = LineItem.blank(hourlyRate: noRate)
            #expect(line == LineItem(id: line.id, title: "", unit: .units, rate: .zero))
        }
    }

    /// Asking for a unit by name still gets that unit; only the hourly rate follows hours.
    @Test func aUnitAskedForByNameIsKept() {
        let inUnits = LineItem.blank(unit: .units, hourlyRate: hourly)
        #expect(inUnits.unit == .units)
        #expect(inUnits.rate == .zero)
        #expect(LineItem.blank(unit: .days, hourlyRate: hourly).unit == .days)
    }

    /// A rate that is typed into the new line afterwards is the line's own, and a unit change keeps it.
    @Test func aTypedRateIsNotOverwrittenOnALineThatStartedInHours() {
        var line = LineItem.blank(hourlyRate: hourly)
        line.rate = Money(dollars: 120)
        #expect(line.withHourlyRate(hourly, after: line).rate == Money(dollars: 120))
        var inUnits = line
        inUnits.unit = .units
        var backInHours = inUnits
        backInHours.unit = .hours
        #expect(backInHours.withHourlyRate(hourly, after: inUnits).rate == Money(dollars: 120))
    }

    @Test func aNewLineInDaysOrUnitsIsLeftAlone() {
        for unit in [Unit.days, .units] {
            #expect(LineItem.blank(unit: unit, hourlyRate: hourly).rate == .zero, "\(unit)")
        }
    }

    // MARK: Switching to hours

    @Test func switchingToHoursAtNothingFillsTheHourlyRateIn() {
        let before = LineItem(title: "Planning", unit: .units, rate: .zero)
        var after = before
        after.unit = .hours
        #expect(after.withHourlyRate(hourly, after: before).rate == hourly)
        // And only the rate changes.
        var expected = after
        expected.rate = hourly
        #expect(after.withHourlyRate(hourly, after: before) == expected)

        // From days, too.
        let inDays = LineItem(title: "Planning", unit: .days, rate: .zero)
        var inHours = inDays
        inHours.unit = .hours
        #expect(inHours.withHourlyRate(hourly, after: inDays).rate == hourly)
    }

    @Test func aRateThatWasTypedIsNeverOverwritten() {
        let before = LineItem(title: "Design", unit: .units, rate: Money(dollars: 600))
        var after = before
        after.unit = .hours
        #expect(after.withHourlyRate(hourly, after: before) == after)
        #expect(after.withHourlyRate(hourly, after: before).rate == Money(dollars: 600))

        // Even a rate of one cent, or a discount, is a rate somebody typed.
        for typed in [Money(cents: 1), Money(dollars: -50)] {
            var line = LineItem.blank(unit: .hours, hourlyRate: nil)
            line.rate = typed
            #expect(line.withHourlyRate(hourly, after: nil).rate == typed)
        }
    }

    @Test func anEditThatLeavesTheUnitInHoursChangesNothing() {
        // A line in hours that was left at $0 stays there: only getting into hours fills the rate in.
        let free = LineItem(title: "Courtesy check", unit: .hours, rate: .zero)
        var renamed = free
        renamed.title = "Courtesy check-in"
        #expect(renamed.withHourlyRate(hourly, after: free) == renamed)
        #expect(renamed.rate == .zero)
    }

    @Test func otherUnitsNeverTakeTheRate() {
        let before = LineItem(title: "Build", unit: .hours, rate: .zero)
        for unit in [Unit.days, .units] {
            var after = before
            after.unit = unit
            #expect(after.withHourlyRate(hourly, after: before) == after, "\(unit)")
        }
    }

    // MARK: Nothing to fill in with

    @Test func withNoHourlyRateNothingChanges() {
        #expect(LineItem.blank(unit: .hours, hourlyRate: nil).rate == .zero)
        let before = LineItem(title: "Planning", unit: .units, rate: .zero)
        var after = before
        after.unit = .hours
        #expect(after.withHourlyRate(nil, after: before) == after)
        // A new line is the same blank line it was before the hourly rate existed.
        let blank = LineItem.blank(hourlyRate: nil)
        #expect(blank == LineItem(id: blank.id, title: "", rate: .zero))
    }

    @Test func anHourlyRateOfNothingFillsInNothing() {
        #expect(LineItem.blank(unit: .hours, hourlyRate: .zero).rate == .zero)
    }

    // MARK: Lines that can't be edited

    /// A quote its invoices lock, or a sent invoice, keeps every line as it is.
    @Test func aLockedQuoteIsUntouched() throws {
        var (library, quoteID) = Fixture.acceptedLibrary()
        library.brand.hourlyRate = hourly
        try library.draftNextInvoice(forQuote: quoteID, on: Fixture.today)
        #expect(!library.invoices(forQuote: quoteID).isEmpty)

        let quote = library.quote(quoteID)!
        let before = quote.lines[1]
        var after = before
        after.unit = .hours
        after.rate = .zero
        #expect(after.withHourlyRate(library.brand.hourlyRate, after: before, editable: false) == after)
        #expect(after.withHourlyRate(library.brand.hourlyRate, after: before, editable: false).rate == .zero)

        let unfilled = LineItem(title: "Late addition", unit: .hours, rate: .zero)
        #expect(unfilled.withHourlyRate(hourly, after: nil, editable: false) == unfilled)
        // Unlocked, the same line does take it.
        #expect(unfilled.withHourlyRate(hourly, after: nil, editable: true).rate == hourly)
    }

    // MARK: The amounts

    @Test func theFilledRateBillsLikeAnyOther() {
        var line = LineItem.blank(unit: .hours, hourlyRate: hourly)
        line.quantity = Decimal(string: "2.5")!
        #expect(line.amount == Money(dollars: 237, cents: 50))
    }
}
