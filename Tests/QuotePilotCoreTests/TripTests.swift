import Foundation
import Testing
@testable import QuotePilotCore

/// A Travel expense's trip: the distance it counts, and how the money records show it.
@Suite struct TripTests {
    let day = Day(year: 2026, month: 11, day: 10)

    func travel(_ trip: Trip, category: String = Expense.travelCategory, description: String = "Client meeting") -> Expense {
        var expense = Expense(date: day, supplier: "Own car", description: description, category: category)
        expense.trip = trip
        return expense
    }

    @Test func aReturnTripCountsTwice() {
        let one = Trip(from: "Fraser ACT", to: "City ACT", kilometres: 19.9)
        var back = one
        back.returnTrip = true
        #expect(one.businessKilometres == 19.9 && back.businessKilometres == 39.8)
        #expect(one.summary == "Fraser ACT → City ACT, 19.9 km")
        #expect(back.summary == "Fraser ACT → City ACT, 39.8 km return")
        #expect(Trip(from: "Fraser ACT").summary == "Fraser ACT")
    }

    @Test func onlyATravelExpenseHasATrip() {
        let trip = Trip(from: "Fraser ACT", to: "City ACT", kilometres: 19.9)
        #expect(travel(trip).travel == trip)
        #expect(travel(trip, category: "Equipment").travel == nil)
    }

    @Test func theMoneyRecordsShowTheTripAndTheYearsKilometres() throws {
        var library = Library()
        try library.addExpense(travel(Trip(from: "Fraser ACT", to: "City ACT", kilometres: 19.9, returnTrip: true)))
        try library.addExpense(travel(Trip(from: "City ACT", to: "Belconnen ACT", kilometres: 10), description: ""))
        try library.addExpense(travel(Trip(from: "Nowhere", to: "Counted", kilometres: 500), category: "Equipment"))
        let year = FinancialYear(containing: day)
        let record = library.moneyRecordCSV(for: year)
        #expect(record.contains("Client meeting (Fraser ACT → City ACT, 39.8 km return)"))
        #expect(record.contains("City ACT → Belconnen ACT, 10 km"))
        #expect(library.summaryCSV(for: year, today: day).contains("Business kilometres (travel expenses),49.8"))
        #expect(!Library().summaryCSV(for: year, today: day).contains("Business kilometres"), "no trips, no row")
    }

    /// Expenses saved before trips have none.
    @Test func anOlderExpenseHasNoTrip() throws {
        var library = Library()
        try library.addExpense(Expense(date: day, supplier: "Officeworks"))
        let read = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        #expect(read.expenses.first?.trip == nil)
    }
}
