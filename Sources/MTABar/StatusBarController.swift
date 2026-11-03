import AppKit
import Observation
import SwiftUI

/// Owns the menu bar item. Uses AppKit directly because SwiftUI's `MenuBarExtra` label
/// renders images as monochrome templates, which would lose the line colors.
@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var badgeCache: [String: NSImage] = [:]

    init(model: AppModel) {
        self.model = model
        super.init()

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(togglePopover)
        }

        let hosting = NSHostingController(
            rootView: MenuView(openSettings: { [weak self] in self?.openSettings() })
                .environment(model)
        )
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true

        observeModel()
    }

    private func observeModel() {
        withObservationTracking {
            updateButton()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeModel() }
        }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let text = model.menuBarText
        if let route = model.menuBarRoute {
            button.image = badge(for: route, alert: model.primaryHasDisruption)
            button.title = " " + text
        } else {
            let symbol = NSImage(systemSymbolName: "tram.fill", accessibilityDescription: "Subway")
            symbol?.isTemplate = true
            button.image = symbol
            button.title = " " + text
        }
        let parts = [
            model.menuBarRoute.map { "\($0) train" },
            text,
            model.primaryHasDisruption ? "service alert" : nil,
        ]
        button.setAccessibilityLabel(parts.compactMap(\.self).joined(separator: ", "))
    }

    private func badge(for route: String, alert: Bool) -> NSImage {
        let key = route + (alert ? "!" : "")
        if let cached = badgeCache[key] { return cached }
        let name = RouteStyle.displayName(route)
        let fill = NSColor(RouteStyle.color(route))
        let textColor = NSColor(RouteStyle.textColor(route))
        let diameter: CGFloat = 16
        let dot: CGFloat = 6.5
        // Extra width/height so the alert dot can overhang the badge's top-right edge.
        let canvas = NSSize(width: diameter + (alert ? 2 : 0), height: diameter + (alert ? 1 : 0))

        let image = NSImage(size: canvas, flipped: false) { _ in
            let rect = NSRect(x: 0, y: 0, width: diameter, height: diameter)
            fill.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let font = NSFont.systemFont(ofSize: name.count > 1 ? 7.5 : 10.5, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let size = name.size(withAttributes: attributes)
            name.draw(
                at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                withAttributes: attributes
            )
            if alert {
                let dotRect = NSRect(x: canvas.width - dot, y: canvas.height - dot, width: dot, height: dot)
                // Punch a transparent ring so the dot reads on any line color (including orange lines).
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: dotRect.insetBy(dx: -1.5, dy: -1.5)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            return true
        }
        image.isTemplate = false
        badgeCache[key] = image
        return image
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView().environment(model))
            hosting.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hosting)
            window.title = "MTA Bar Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
