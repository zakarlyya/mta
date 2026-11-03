import CoreLocation
import MapKit
import Observation

/// Walking time from the user's location to saved stations, via Apple Maps with a
/// straight-line fallback. Recomputed only after the user moves a meaningful distance.
@MainActor
@Observable
final class WalkEstimator {
    private static let recomputeDistance: CLLocationDistance = 100
    private static let gridDetour = 1.3
    private static let metersPerMinute = 80.0

    private(set) var times: [String: TimeInterval] = [:]
    @ObservationIgnored private var origin: CLLocation?
    @ObservationIgnored private var task: Task<Void, Never>?

    func update(from location: CLLocation, stations: [Station]) {
        if let origin, origin.distance(from: location) < Self.recomputeDistance {
            let missing = stations.filter { times[$0.id] == nil }
            guard !missing.isEmpty else { return }
            compute(from: origin, stations: missing)
        } else {
            origin = location
            compute(from: location, stations: stations)
        }
    }

    func reset() {
        task?.cancel()
        origin = nil
        times = [:]
    }

    private func compute(from location: CLLocation, stations: [Station]) {
        task?.cancel()
        task = Task {
            for station in stations {
                guard !Task.isCancelled else { return }
                let walk = await Self.routedWalk(from: location, to: station.location)
                    ?? Self.straightLineWalk(from: location, to: station.location)
                times[station.id] = walk
            }
        }
    }

    static func straightLineWalk(from a: CLLocation, to b: CLLocation) -> TimeInterval {
        a.distance(from: b) * gridDetour / metersPerMinute * 60
    }

    private static func routedWalk(from a: CLLocation, to b: CLLocation) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = mapItem(a)
        request.destination = mapItem(b)
        request.transportType = .walking
        return try? await MKDirections(request: request).calculateETA().expectedTravelTime
    }

    private static func mapItem(_ location: CLLocation) -> MKMapItem {
        if #available(macOS 26, *) {
            return MKMapItem(location: location, address: nil)
        }
        return MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
    }
}
