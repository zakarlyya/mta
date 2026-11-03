import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private static let watchesKey = "watches"
    private static let useNearestKey = "useNearest"
    private static let onlyCatchableKey = "onlyCatchable"
    private static let nearbyRadius: CLLocationDistance = 1500
    private static let refreshInterval: Duration = .seconds(30)
    private static let tickInterval: Duration = .seconds(5)

    /// Time to get from the street to the platform.
    private static let platformBuffer: TimeInterval = 60
    /// Trains this much sooner than the walk are still shown, marked as "hurry".
    private static let hurryGrace: TimeInterval = 120
    /// Beyond this walk the user isn't walking to the station, so nothing is filtered.
    private static let maxWalk: TimeInterval = 25 * 60

    var watches: [Watch] {
        didSet {
            save()
            if watches != oldValue {
                updateWalkTimes()
                Task { await refresh() }
            }
        }
    }

    var useNearest: Bool {
        didSet {
            UserDefaults.standard.set(useNearest, forKey: Self.useNearestKey)
            updateLocationTracking()
        }
    }

    var onlyCatchable: Bool {
        didSet {
            UserDefaults.standard.set(onlyCatchable, forKey: Self.onlyCatchableKey)
            updateLocationTracking()
        }
    }

    let locationProvider = LocationProvider()
    let walkEstimator = WalkEstimator()

    private(set) var arrivals: [Watch.ID: [Arrival]] = [:]
    private(set) var alerts: [ServiceAlert] = []
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
        onlyCatchable = UserDefaults.standard.bool(forKey: Self.onlyCatchableKey)
        locationProvider.onUpdate = { [weak self] _ in self?.updateWalkTimes() }
        updateLocationTracking()
        start()
    }

    // MARK: - Menu bar

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

    /// The route of the next train in the menu bar, drawn as a colored badge.
    var menuBarRoute: String? {
        primary.flatMap { upcoming(for: $0).first?.route }
    }

    var menuBarText: String {
        guard let primary else { return "MTA" }
        guard let next = upcoming(for: primary).first else {
            return lastUpdated == nil ? "…" : "—"
        }
        let minutes = Self.minutes(until: next.time, from: now)
        return minutes < 1 ? "arriving" : "in \(minutes)m"
    }

    /// Whether the menu bar station has an unplanned delay or service change.
    var primaryHasDisruption: Bool {
        primary.map { alerts(for: $0).contains { !$0.isPlanned } } ?? false
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

    // MARK: - Arrivals

    /// Upcoming trains, excluding ones the user can't reach when "only catchable" is on.
    func upcoming(for watch: Watch) -> [Arrival] {
        let cutoff = walkTime(for: watch).map { now.addingTimeInterval($0 - Self.hurryGrace) } ?? now
        return (arrivals[watch.id] ?? []).filter { $0.time > max(now, cutoff) }
    }

    /// Trains that are coming but can't be caught at a normal walking pace.
    func hiddenCount(for watch: Watch) -> Int {
        guard walkTime(for: watch) != nil else { return 0 }
        let all = (arrivals[watch.id] ?? []).filter { $0.time > now }.count
        return all - upcoming(for: watch).count
    }

    /// True for trains that need a hurried walk to catch.
    func isHurry(_ arrival: Arrival, for watch: Watch) -> Bool {
        guard let walk = walkTime(for: watch) else { return false }
        return arrival.time < now.addingTimeInterval(walk)
    }

    /// Door-to-platform time, when filtering applies to this watch.
    func walkTime(for watch: Watch) -> TimeInterval? {
        guard onlyCatchable, locationProvider.location != nil,
              let walk = walkEstimator.times[watch.stationID] else { return nil }
        let total = walk + Self.platformBuffer
        return total <= Self.maxWalk ? total : nil
    }

    // MARK: - Alerts

    /// Active alerts affecting a watch, unplanned first.
    func alerts(for watch: Watch) -> [ServiceAlert] {
        alerts
            .filter { $0.isActive(at: now) && $0.affects(watch) }
            .sorted { !$0.isPlanned && $1.isPlanned }
    }

    // MARK: - Location

    func distance(to watch: Watch) -> CLLocationDistance? {
        guard useNearest || onlyCatchable, let location = locationProvider.location else { return nil }
        return distance(to: watch, from: location)
    }

    private func distance(to watch: Watch, from location: CLLocation) -> CLLocationDistance? {
        watch.station.map { location.distance(from: $0.location) }
    }

    private func isNearby(_ watch: Watch) -> Bool {
        guard useNearest else { return false }
        return (distance(to: watch) ?? .infinity) <= Self.nearbyRadius
    }

    private func updateLocationTracking() {
        if useNearest || onlyCatchable {
            locationProvider.start()
            updateWalkTimes()
        } else {
            locationProvider.stop()
            walkEstimator.reset()
        }
    }

    private func updateWalkTimes() {
        guard onlyCatchable, let location = locationProvider.location else { return }
        let stations = Set(watches.compactMap(\.station))
        walkEstimator.update(from: location, stations: Array(stations))
    }

    // MARK: - Refresh

    func refresh() async {
        let paths = Set(watches.flatMap { $0.routes.compactMap(GTFSFeed.path(for:)) })
        var snapshots: [String: FeedSnapshot] = [:]
        var failures = 0

        async let fetchedAlerts = try? GTFSFeed.fetchAlerts()
        await withTaskGroup(of: (String, FeedSnapshot?).self) { group in
            for path in paths {
                group.addTask { (path, try? await GTFSFeed.fetch(path: path)) }
            }
            for await (path, snapshot) in group {
                if let snapshot { snapshots[path] = snapshot } else { failures += 1 }
            }
        }
        if let latest = await fetchedAlerts { alerts = latest }

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
