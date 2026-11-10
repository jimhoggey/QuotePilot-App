import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// Stands in for Apple Maps: answers every trip with `kilometres`, finds no route when it's nil, or
/// can't be reached when `offline`, and keeps what it was asked. Nothing goes to Apple.
@MainActor
final class FakeDistances: DistanceFinding {
    struct Offline: Error {}
    var kilometres: Decimal?
    var offline = false
    var asked: [String] = []

    init(_ kilometres: Decimal?) { self.kilometres = kilometres }

    func drivingKilometres(from: String, to: String) async throws -> Decimal {
        asked.append("\(from) → \(to)")
        if offline { throw Offline() }
        guard let kilometres else { throw RouteNotFound() }
        return kilometres
    }
}

/// A Travel expense's distance, filled in from Maps once both ends are typed.
@MainActor
@Suite struct TravelDistanceTests {
    func model(_ trip: Trip, maps: FakeDistances) throws -> (AppModel, UUID) {
        let model = try UIFixture.sampleModel()
        model.distances = maps
        model.newExpense()
        let id = try #require(model.selectedExpenseID)
        var expense = try #require(model.library.expense(id))
        expense.category = Expense.travelCategory
        expense.trip = trip
        model.updateExpense(expense)
        return (model, id)
    }

    @Test func bothEndsFillInTheDistance() async throws {
        let maps = FakeDistances(19.9)
        let (model, id) = try model(Trip(from: "Fraser ACT", to: "City ACT", returnTrip: true), maps: maps)
        #expect(await model.fillTripDistance(id))
        #expect(maps.asked == ["Fraser ACT → City ACT"])
        #expect(model.library.expense(id)?.trip?.kilometres == 19.9)
        #expect(model.library.expense(id)?.travel?.businessKilometres == 39.8)
    }

    @Test func aTypedDistanceOrAMissingEndAsksNothing() async throws {
        let maps = FakeDistances(19.9)
        let (typed, typedID) = try model(Trip(from: "Fraser ACT", to: "City ACT", kilometres: 25), maps: maps)
        #expect(await typed.fillTripDistance(typedID))
        #expect(typed.library.expense(typedID)?.trip?.kilometres == 25)
        let (half, halfID) = try model(Trip(from: "Fraser ACT"), maps: maps)
        #expect(await half.fillTripDistance(halfID))
        #expect(maps.asked.isEmpty)
    }

    /// No route asks for the kilometres, and isn't asked about again; Maps out of reach is, next time.
    @Test func noRouteAsksForTheKilometres() async throws {
        let maps = FakeDistances(nil)
        let (model, id) = try model(Trip(from: "Fraser ACT", to: "Atlantis"), maps: maps)
        #expect(await model.fillTripDistance(id) == false)
        #expect(await model.fillTripDistance(id) == false)
        #expect(maps.asked.count == 1, "a route that doesn't exist isn't asked about twice")
        #expect(model.library.expense(id)?.trip?.kilometres == nil)
        #expect(TripFields.note(Trip(), notFound: true) == "Apple Maps couldn't work out that route. Type the kilometres.")

        let offline = FakeDistances(19.9)
        offline.offline = true
        let (away, awayID) = try self.model(Trip(from: "Fraser ACT", to: "City ACT"), maps: offline)
        #expect(await away.fillTripDistance(awayID) == false)
        offline.offline = false
        #expect(await away.fillTripDistance(awayID))
        #expect(away.library.expense(awayID)?.trip?.kilometres == 19.9)
    }

    @Test func theFeeLockAsksNothing() async throws {
        let maps = FakeDistances(19.9)
        let model = try FeeBarTests().lockedModel()
        model.distances = maps
        let id = UUID()
        #expect(await model.fillTripDistance(id))
        #expect(maps.asked.isEmpty)
    }

    @Test func theDistanceFieldTakesKilometresOrBlank() {
        #expect(TripFields.kilometres("") == .some(nil), "blank clears it, so Maps works it out again")
        #expect(TripFields.kilometres("19.9") == .some(19.9))
        #expect(TripFields.kilometres("far") == nil)
    }

    /// The trip shows only on a Travel expense (snapshot: expense-travel).
    @Test func theTripDraws() throws {
        let (model, _) = try model(Trip(from: "Fraser ACT", to: "City ACT", kilometres: 19.9, returnTrip: true),
                                   maps: FakeDistances(nil))
        model.section = .expenses
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 980, height: 720), name: "expense-travel")
        #expect(rep.map(Snapshot.hasContent) == true)
        #expect(TripFields.note(Trip(from: "A", to: "B", kilometres: 19.9, returnTrip: true), notFound: false)
            .hasPrefix("Business kilometres: 39.8."))
    }
}
