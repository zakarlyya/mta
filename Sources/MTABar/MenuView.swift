import SwiftUI

struct MenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.watches.isEmpty {
                Text("No trains configured")
                    .foregroundStyle(.secondary)
            }

            ForEach(model.watches) { watch in
                WatchSection(watch: watch, isPrimary: watch == model.primary)
            }

            Divider()

            HStack {
                status
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                Button {
                    openWindow(id: "settings")
                    NSApp.activate()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
    }

    @ViewBuilder
    private var status: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else if let updated = model.lastUpdated {
            Text("Updated \(Int(model.now.timeIntervalSince(updated)))s ago")
                .foregroundStyle(.secondary)
        } else {
            Text("Loading…")
                .foregroundStyle(.secondary)
        }
    }
}

private struct WatchSection: View {
    @Environment(AppModel.self) private var model
    let watch: Watch
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(watch.title)
                    .font(.headline)
                if isPrimary {
                    Image(systemName: model.primaryIsNearby ? "location.fill" : "menubar.rectangle")
                        .foregroundStyle(.secondary)
                        .help(model.primaryIsNearby ? "Nearest saved station, shown in the menu bar" : "Shown in the menu bar")
                }
                Spacer()
                if let distance = model.distance(to: watch) {
                    Text(Measurement(value: distance, unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .road))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            let upcoming = Array(model.upcoming(for: watch).prefix(3))
            if upcoming.isEmpty {
                Text(model.lastUpdated == nil ? "Loading…" : "No upcoming trains")
                    .foregroundStyle(.secondary)
            }
            ForEach(upcoming, id: \.self) { arrival in
                HStack {
                    RouteBadge(route: arrival.route)
                    Text(AppModel.countdown(to: arrival.time, from: model.now))
                        .monospacedDigit()
                        .fontWeight(.medium)
                    Spacer()
                    Text(arrival.time, format: .dateTime.hour().minute())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}
