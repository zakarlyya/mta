import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private static let watchesKey = "watches"
    private static let useNearestKey = "useNearest"
    private static let nearbyRadius: CLLocationDistance = 1500
    private static let refreshInterval: Duration = .seconds(30)
    private static let tickInterval: Duration = .seconds(5)

    var watches: [Watch] {
        didSet {
            save()
            if watches != oldValue { Task { await refresh() } }
        }
    }

    private(set) var arrivals: [Watch.ID: [Arrival]] = [:]
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private(set) var now = Date()

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.watchesKey),
           let saved = try? JSONDecoder().decode([Watch].self, from: data) {
            watches = saved
        } else {
            watches = [Watch(stationID: "A49", direction: .north, routes: ["A", "C"])]
        }
        useNearest = UserDefaults.standard.bool(forKey: Self.useNearestKey)
        if useNearest { locationProvider.start() }
        start()
    }

    var useNearest: Bool {
        didSet {
            UserDefaults.standard.set(useNearest, forKey: Self.useNearestKey)
            useNearest ? locationProvider.start() : locationProvider.stop()
        }
    }

    let locationProvider = LocationProvider()

    /// The watch shown in the menu bar: the nearest saved station when location is on and one is
    /// within range, otherwise the pinned (first) watch.
    var primary: Watch? {
        guard useNearest, let location = locationProvider.location else { return watches.first }
        let nearest = watches
            .compactMap { watch in distance(to: watch, from: location).map { (watch, $0) } }
            .min { $0.1 < $1.1 }
        guard let nearest, nearest.1 <= Self.nearbyRadius else { return watches.first }
        return nearest.0
    }

    /// True when the menu bar is following location rather than the pinned watch.
    var primaryIsNearby: Bool { primary.map(isNearby) ?? false }

    func distance(to watch: Watch) -> CLLocationDistance? {
        guard useNearest, let location = locationProvider.location else { return nil }
        return distance(to: watch, from: location)
    }

    private func distance(to watch: Watch, from location: CLLocation) -> CLLocationDistance? {
        watch.station.map { location.distance(from: $0.location) }
    }

    private func isNearby(_ watch: Watch) -> Bool {
        (distance(to: watch) ?? .infinity) <= Self.nearbyRadius
    }

    func upcoming(for watch: Watch) -> [Arrival] {
        (arrivals[watch.id] ?? []).filter { $0.time > now }
    }

    var menuBarTitle: String {
        guard let primary else { return "MTA" }
        guard let next = upcoming(for: primary).first else {
            return lastUpdated == nil ? "…" : "—"
        }
        let route = RouteStyle.displayName(next.route)
        let minutes = Self.minutes(until: next.time, from: now)
        return minutes < 1 ? "\(route) arriving" : "\(route) in \(minutes)m"
    }

    /// Watches ordered with the menu bar one first.
    var displayOrder: [Watch] {
        guard let primary else { return watches }
        return [primary] + watches.filter { $0 != primary }
    }

    var isStale: Bool {
        guard let lastUpdated else { return false }
        return now.timeIntervalSince(lastUpdated) > 120
    }

    static func minutes(until time: Date, from now: Date) -> Int {
        max(0, Int(time.timeIntervalSince(now) / 60))
    }

    func pin(_ watch: Watch) {
        guard let index = watches.firstIndex(of: watch) else { return }
        watches.insert(watches.remove(at: index), at: 0)
    }

    func refresh() async {
        let paths = Set(watches.flatMap { $0.routes.compactMap(GTFSFeed.path(for:)) })
        var snapshots: [String: FeedSnapshot] = [:]
        var failures = 0

        await withTaskGroup(of: (String, FeedSnapshot?).self) { group in
            for path in paths {
                group.addTask { (path, try? await GTFSFeed.fetch(path: path)) }
            }
            for await (path, snapshot) in group {
                if let snapshot { snapshots[path] = snapshot } else { failures += 1 }
            }
        }

        guard paths.isEmpty || !snapshots.isEmpty else {
            errorMessage = "Couldn't reach the MTA feed"
            return
        }

        var result: [Watch.ID: [Arrival]] = [:]
        for watch in watches {
            let routes = Set(watch.routes)
            var list: [Arrival] = []
            for path in Set(watch.routes.compactMap(GTFSFeed.path(for:))) {
                for trip in snapshots[path]?.trips ?? [] {
                    let route = GTFSFeed.normalize(trip.routeID)
                    guard routes.contains(route) else { continue }
                    for stop in trip.stops where stop.stopID == watch.stopID {
                        list.append(Arrival(route: route, time: Date(timeIntervalSince1970: TimeInterval(stop.time))))
                    }
                }
            }
            result[watch.id] = list.sorted { $0.time < $1.time }
        }

        arrivals = result
        lastUpdated = Date()
        now = Date()
        errorMessage = failures > 0 ? "Some feeds failed to load" : nil
    }

    private func start() {
        Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                now = Date()
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(watches) {
            UserDefaults.standard.set(data, forKey: Self.watchesKey)
        }
    }
}
