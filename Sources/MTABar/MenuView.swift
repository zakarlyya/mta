import SwiftUI

struct MenuView: View {
    @Environment(AppModel.self) private var model
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.watches.isEmpty {
                EmptyState(openSettings: openSettings)
            } else {
                ForEach(model.displayOrder) { watch in
                    WatchCard(watch: watch, isPrimary: watch == model.primary)
                }
            }

            Divider()
                .padding(.top, 2)

            HStack(spacing: 4) {
                StatusLine()
                Spacer()
                IconButton(systemImage: "arrow.clockwise", help: "Refresh") {
                    Task { await model.refresh() }
                }
                IconButton(systemImage: "gearshape", help: "Settings", action: openSettings)
                IconButton(systemImage: "power", help: "Quit MTA Bar") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .animation(.snappy, value: model.displayOrder)
    }
}

private struct WatchCard: View {
    @Environment(AppModel.self) private var model
    let watch: Watch
    let isPrimary: Bool

    var body: some View {
        let upcoming = Array(model.upcoming(for: watch).prefix(3))

        VStack(alignment: .leading, spacing: 10) {
            header

            if let next = upcoming.first {
                HStack(alignment: .center, spacing: 10) {
                    RouteBadge(route: next.route, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(countdown(next))
                            .lineLimit(1)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                        HStack(spacing: 4) {
                            Text(next.time, format: .dateTime.hour().minute())
                                .foregroundStyle(.secondary)
                            if model.isHurry(next, for: watch) {
                                HurryLabel()
                            }
                        }
                        .font(.caption)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 4)
                    if upcoming.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(upcoming.dropFirst(), id: \.self) { arrival in
                                ArrivalChip(arrival: arrival, hurry: model.isHurry(arrival, for: watch))
                            }
                        }
                    }
                }
            } else {
                Text(model.lastUpdated == nil ? "Loading…" : "No upcoming trains")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            }

            let hidden = model.hiddenCount(for: watch)
            if hidden > 0 {
                Text(hidden == 1 ? "1 earlier train hidden, too soon to catch" : "\(hidden) earlier trains hidden, too soon to catch")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            let alerts = model.alerts(for: watch)
            if !alerts.isEmpty {
                AlertList(alerts: alerts)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.primary.opacity(isPrimary ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isPrimary ? 0.5 : 0), lineWidth: 1)
        )
        .animation(.snappy, value: model.now)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(watch.station?.name ?? watch.stationID)
                    .font(.headline)
                if let station = watch.station {
                    Text("to \(station.label(for: watch.direction))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let walk = model.walkTime(for: watch) {
                Label("\(max(1, Int((walk / 60).rounded()))) min walk", systemImage: "figure.walk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Estimated walk to the platform")
            } else if let distance = model.distance(to: watch) {
                Text(Measurement(value: distance, unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .road))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isPrimary {
                Image(systemName: model.primaryIsNearby ? "location.fill" : "pin.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .help(model.primaryIsNearby ? "Nearest saved station, shown in the menu bar" : "Pinned, shown in the menu bar")
            }
        }
    }

    private func countdown(_ arrival: Arrival) -> String {
        let minutes = AppModel.minutes(until: arrival.time, from: model.now)
        return minutes < 1 ? "Arriving" : "in \(minutes) min"
    }
}

private struct ArrivalChip: View {
    @Environment(AppModel.self) private var model
    let arrival: Arrival
    let hurry: Bool

    var body: some View {
        HStack(spacing: 3) {
            RouteBadge(route: arrival.route, size: 14)
            Text("\(AppModel.minutes(until: arrival.time, from: model.now))m")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
            if hurry {
                Image(systemName: "figure.run")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(.primary.opacity(0.08)))
        .help(arrival.time.formatted(date: .omitted, time: .shortened) + (hurry ? " · hurry to catch it" : ""))
    }
}

private struct HurryLabel: View {
    var body: some View {
        Label("hurry", systemImage: "figure.run")
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.orange)
            .help("You'll need to hurry to catch this train")
    }
}

private struct AlertList: View {
    // Stored `State` instead of `@State`: the Command Line Tools SDK lacks the SwiftUI macro plugin.
    private let expanded = State(initialValue: Set<String>())
    private let showAll = State(initialValue: false)
    private static let collapsedCount = 2

    let alerts: [ServiceAlert]

    init(alerts: [ServiceAlert]) {
        self.alerts = alerts
    }

    var body: some View {
        let visible = showAll.wrappedValue ? alerts : Array(alerts.prefix(Self.collapsedCount))

        VStack(alignment: .leading, spacing: 6) {
            Divider()
            ForEach(visible) { alert in
                AlertRow(alert: alert, isExpanded: expanded.wrappedValue.contains(alert.id)) {
                    withAnimation(.snappy) {
                        if expanded.wrappedValue.contains(alert.id) {
                            expanded.wrappedValue.remove(alert.id)
                        } else {
                            expanded.wrappedValue.insert(alert.id)
                        }
                    }
                }
            }
            if alerts.count > Self.collapsedCount {
                Button(showAll.wrappedValue ? "Show fewer" : "\(alerts.count - Self.collapsedCount) more") {
                    withAnimation(.snappy) { showAll.wrappedValue.toggle() }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AlertRow: View {
    let alert: ServiceAlert
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: alert.isPlanned ? "calendar" : "exclamationmark.triangle.fill")
                    .foregroundStyle(alert.isPlanned ? Color.secondary : Color.orange)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 3) {
                    if !alert.type.isEmpty {
                        Text(alert.type.replacingOccurrences(of: "Planned - ", with: ""))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(alert.isPlanned ? Color.secondary : Color.orange)
                    }
                    Text(alert.header.replacing(/\[([A-Z0-9]+)\]/) { String($0.1) })
                        .font(.caption)
                        .lineLimit(isExpanded ? nil : 2)
                    if isExpanded, !alert.details.isEmpty {
                        Text(alert.details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(10)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Show less" : "Show details")
    }
}

private struct StatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var color: Color {
        if model.errorMessage != nil || model.isStale { return .orange }
        return model.lastUpdated == nil ? .secondary : .green
    }

    private var text: String {
        if let error = model.errorMessage { return error }
        guard let updated = model.lastUpdated else { return "Loading…" }
        let seconds = Int(model.now.timeIntervalSince(updated))
        if seconds < 10 { return "Live · updated just now" }
        if seconds < 60 { return "Live · updated \(seconds)s ago" }
        return "Updated \(seconds / 60)m ago"
    }
}

private struct EmptyState: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tram.fill")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No stations yet")
                .font(.headline)
            Button("Add a station", action: openSettings)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

private struct IconButton: View {
    // Stored `State` instead of `@State`: the Command Line Tools SDK lacks the SwiftUI macro plugin.
    private let hovering = State(initialValue: false)
    let systemImage: String
    let help: String
    let action: () -> Void

    init(systemImage: String, help: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.primary.opacity(hovering.wrappedValue ? 0.1 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .onHover { hovering.wrappedValue = $0 }
    }
}
