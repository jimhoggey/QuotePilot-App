import Foundation
import MapKit

/// Works out the driving distance between two places as typed, such as "Fraser ACT" and "Canberra City".
@MainActor
public protocol DistanceFinding {
    /// One way, in kilometres to one decimal place. Throws when either place or a route can't be found.
    func drivingKilometres(from: String, to: String) async throws -> Decimal
}

/// Apple Maps: built into macOS, no key and nothing to pay. The two places go to Apple, as typing them
/// into the Maps app does. The destination is searched near the start, so "City" means the nearby one.
public struct AppleMapsDistance: DistanceFinding {
    struct NotFound: Error {}

    public init() {}

    public func drivingKilometres(from: String, to: String) async throws -> Decimal {
        let start = try await place(from, near: nil)
        let request = MKDirections.Request()
        request.source = start
        request.destination = try await place(to, near: start.placemark.coordinate)
        request.transportType = .automobile
        guard let route = try await MKDirections(request: request).calculate().routes.first else { throw NotFound() }
        return Decimal(Int((route.distance / 100).rounded())) / 10
    }

    private func place(_ text: String, near point: CLLocationCoordinate2D?) async throws -> MKMapItem {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let point { request.region = MKCoordinateRegion(center: point, latitudinalMeters: 300_000, longitudinalMeters: 300_000) }
        guard let item = try await MKLocalSearch(request: request).start().mapItems.first else { throw NotFound() }
        return item
    }
}
