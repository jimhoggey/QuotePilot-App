import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct DayTests {
    @Test func isoRoundTrip() {
        let day = Day(year: 2026, month: 10, day: 5)
        #expect(day.iso == "2026-10-05")
        #expect(Day(iso: "2026-10-05") == day)
        #expect(Day(iso: "2026-02-31") == nil)
        #expect(Day(iso: "nope") == nil)
    }

    @Test func addsDaysAcrossMonthAndYearEnds() {
        #expect(Day(year: 2026, month: 12, day: 25).adding(days: 14) == Day(year: 2027, month: 1, day: 8))
        #expect(Day(year: 2028, month: 2, day: 28).adding(days: 1) == Day(year: 2028, month: 2, day: 29))
    }

    @Test func countsDaysBetween() {
        let start = Day(year: 2026, month: 10, day: 15)
        #expect(Day(year: 2026, month: 11, day: 1).days(since: start) == 17)
        #expect(start.days(since: start) == 0)
    }

    @Test func ordersByDate() {
        #expect(Day(year: 2026, month: 6, day: 30) < Day(year: 2026, month: 7, day: 1))
    }

    @Test func theDayOfAMomentDependsOnTheTimeZone() {
        // 14 Oct 2026 14:30 UTC is already 15 Oct in Brisbane (UTC+10).
        let moment = Date(timeIntervalSince1970: 1_791_988_200)
        #expect(Day(moment, timeZone: .gmt) == Day(year: 2026, month: 10, day: 14))
        #expect(Day(moment, timeZone: TimeZone(identifier: "Australia/Brisbane")!) == Day(year: 2026, month: 10, day: 15))
    }

    @Test func readableFormats() {
        #expect(Day(year: 2026, month: 10, day: 15).long == "15 October 2026")
        #expect(Day(year: 2026, month: 10, day: 15).short == "15 Oct 2026")
    }

    @Test func encodesAsISOText() throws {
        let data = try JSONEncoder().encode([Day(year: 2026, month: 10, day: 15)])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-10-15\"]")
        #expect(try JSONDecoder().decode([Day].self, from: data) == [Day(year: 2026, month: 10, day: 15)])
    }

    @Test func rejectsTextThatIsNotExactlyISO() {
        #expect(Day(iso: "2026-10-15-abc") == nil)
        #expect(Day(iso: "x-2026-10-15") == nil)
        #expect(Day(iso: "-2026-10-15") == nil)
        #expect(Day(iso: "2026-+1-+5") == nil)
        #expect(Day(iso: "1-1-1") == nil)
        #expect(Day(iso: "15-10-26") == nil)
    }

    @Test func rejectsDaysThatDoNotExist() {
        #expect(Day(iso: "2027-02-29") == nil)
        #expect(Day(iso: "2028-02-29") == Day(year: 2028, month: 2, day: 29))
    }

    @Test func knowsWhichDaysExist() {
        #expect(!Day.isValid(year: 2026, month: 2, day: 31))
        #expect(!Day.isValid(year: 2027, month: 2, day: 29))
        #expect(Day.isValid(year: 2028, month: 2, day: 29))
        #expect(!Day.isValid(year: 2100, month: 2, day: 29))   // not a leap year: divisible by 100, not 400
        #expect(Day.isValid(year: 2000, month: 2, day: 29))
        #expect(Day.isValid(year: 2026, month: 4, day: 30))
        #expect(!Day.isValid(year: 2026, month: 4, day: 31))
        #expect(Day.isValid(year: 2026, month: 12, day: 31))
        #expect(!Day.isValid(year: 2026, month: 0, day: 15))
        #expect(!Day.isValid(year: 2026, month: 13, day: 15))
        #expect(!Day.isValid(year: 2026, month: 10, day: 0))
        #expect(!Day.isValid(year: 0, month: 1, day: 1))
        #expect(!Day.isValid(year: 10_000, month: 1, day: 1))
    }

    @Test func buildingADayThatDoesNotExistTraps() async {
        await #expect(processExitsWith: .failure) { _ = Day(year: 2026, month: 2, day: 31) }
        await #expect(processExitsWith: .failure) { _ = Day(year: 2027, month: 2, day: 29) }
        await #expect(processExitsWith: .success) { _ = Day(year: 2028, month: 2, day: 29) }
    }

    @Test func decodingRejectsBadDates() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([Day].self, from: Data("[\"2026-02-31\"]".utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([Day].self, from: Data("[\"15-10-26\"]".utf8))
        }
    }
}
