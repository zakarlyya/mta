import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    // Stored `State` instead of `@State`: the Command Line Tools SDK lacks the SwiftUI macro plugin.
    private let queryState = State(initialValue: "")
    private let launchState = State(initialValue: SMAppService.mainApp.status == .enabled)

    private var query: String { queryState.wrappedValue }

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                if model.watches.isEmpty {
                    Text("Add a station below.")
                        .foregroundStyle(.secondary)
                }
                ForEach($model.watches) { $watch in
                    WatchEditor(watch: $watch, isPrimary: watch == model.primary)
                }
            } header: {
                Text("Your trains")
            } footer: {
                Text("The top entry is shown in the menu bar. Click a line to toggle it.")
                    .foregroundStyle(.secondary)
            }

            Section("Add a station") {
                TextField("Search stations", text: queryState.projectedValue)
                ForEach(results) { station in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(station.name)
                            Text("\(station.line) · \(station.borough)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(station.routes, id: \.self) { RouteBadge(route: $0, size: 16) }
                        }
                        Button("Add") {
                            model.watches.append(Watch(stationID: station.id, direction: .north, routes: station.routes))
                            queryState.wrappedValue = ""
                        }
                    }
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
        .frame(width: 460, height: 560)
    }

    private var results: [Station] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return Station.all
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .prefix(25)
            .map { $0 }
    }
}

private struct WatchEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var watch: Watch
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(watch.station?.name ?? watch.stationID)
                    .font(.headline)
                Spacer()
                if isPrimary {
                    Label("Menu bar", systemImage: "menubar.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Show in menu bar") { model.pin(watch) }
                        .controlSize(.small)
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
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
