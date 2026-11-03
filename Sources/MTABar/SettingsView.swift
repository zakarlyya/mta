import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    // Stored `State` instead of `@State`: the Command Line Tools SDK lacks the SwiftUI macro plugin.
    private let queryState = State(initialValue: "")
    private let launchState = State(initialValue: SMAppService.mainApp.status == .enabled)

    private var query: String { queryState.wrappedValue }
    private var results: [Station] { StationSearch.search(query) }

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                if model.watches.isEmpty {
                    Text("Add a station below.")
                        .foregroundStyle(.secondary)
                }
                ForEach($model.watches) { $watch in
                    WatchEditor(watch: $watch, isPinned: watch == model.watches.first)
                }
            } header: {
                Text("Your trains")
            }

            Section {
                Toggle(isOn: $model.useNearest) {
                    Text("Follow my location")
                    Text("Show whichever saved station you’re closest to. If none are nearby, your pinned station is shown.")
                }
                Toggle(isOn: $model.onlyCatchable) {
                    Text("Only show trains I can catch")
                    Text("Uses your walking time to hide trains you’d miss. Trains you can make if you hurry are marked.")
                }
                let usesLocation = model.useNearest || model.onlyCatchable
                if usesLocation, model.locationProvider.isDenied {
                    HStack {
                        Label("Location access is off for MTA Bar", systemImage: "location.slash")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                        }
                    }
                } else if usesLocation, model.locationProvider.location == nil {
                    Text("Finding your location…")
                        .foregroundStyle(.secondary)
                } else if model.useNearest, let primary = model.primary {
                    Label(
                        model.primaryIsNearby ? "Now showing \(primary.station?.name ?? "your nearest station")" : "No saved stations nearby, showing your pinned station",
                        systemImage: model.primaryIsNearby ? "location.fill" : "pin.fill"
                    )
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Location")
            }

            Section("Add a station") {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search", text: queryState.projectedValue, prompt: Text("Station, e.g. union sq or 57th st n"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .onSubmit {
                            if let first = results.first { add(first) }
                        }
                    if !query.isEmpty {
                        Button {
                            queryState.wrappedValue = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !query.trimmingCharacters(in: .whitespaces).isEmpty, results.isEmpty {
                    Text("No stations match")
                        .foregroundStyle(.secondary)
                }
                ForEach(results) { station in
                    StationResultRow(
                        station: station,
                        isSaved: model.watches.contains { $0.stationID == station.id },
                        add: { add(station) }
                    )
                }
            }

            Section {
                Toggle("Launch at login", isOn: launchState.projectedValue)
                    .onChange(of: launchState.wrappedValue) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchState.wrappedValue = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 480, idealHeight: 620)
        .animation(.snappy, value: model.watches)
    }

    private func add(_ station: Station) {
        model.watches.append(Watch(stationID: station.id, direction: .north, routes: station.routes))
        queryState.wrappedValue = ""
    }
}

private struct StationResultRow: View {
    let station: Station
    let isSaved: Bool
    let add: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(station.name)
                Text(station.line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                ForEach(station.routes, id: \.self) { RouteBadge(route: $0, size: 16) }
            }
            Button(isSaved ? "Add again" : "Add", action: add)
                .help(isSaved ? "Already saved. Add again to track the other direction." : "Add this station")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: add)
    }
}

private struct WatchEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var watch: Watch
    let isPinned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(watch.station?.name ?? watch.stationID)
                        .font(.headline)
                    if let station = watch.station {
                        Text(station.line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if watch == model.primary, model.primaryIsNearby {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.secondary)
                        .help("Nearest saved station")
                }
                Spacer()
                if isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Pin") { model.pin(watch) }
                        .controlSize(.small)
                        .help("Show in the menu bar by default")
                }
                Button(role: .destructive) {
                    model.watches.removeAll { $0.id == watch.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            if let station = watch.station {
                Picker("Direction", selection: $watch.direction) {
                    ForEach(Direction.allCases, id: \.self) { direction in
                        Text(station.label(for: direction)).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 6) {
                    ForEach(station.routes, id: \.self) { route in
                        let selected = watch.routes.contains(route)
                        Button {
                            if selected { watch.routes.removeAll { $0 == route } }
                            else { watch.routes.append(route) }
                        } label: {
                            RouteBadge(route: route, size: 24, dimmed: !selected)
                                .animation(.snappy, value: selected)
                        }
                        .buttonStyle(.plain)
                        .help(selected ? "Hide \(RouteStyle.displayName(route)) trains" : "Show \(RouteStyle.displayName(route)) trains")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
