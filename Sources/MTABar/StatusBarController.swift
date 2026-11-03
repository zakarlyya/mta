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
            button.image = badge(for: route)
            button.title = " " + text
        } else {
            let symbol = NSImage(systemSymbolName: "tram.fill", accessibilityDescription: "Subway")
            symbol?.isTemplate = true
            button.image = symbol
            button.title = " " + text
        }
        button.setAccessibilityLabel([model.menuBarRoute.map { "\($0) train" }, text].compactMap(\.self).joined(separator: " "))
    }

    private func badge(for route: String) -> NSImage {
        if let cached = badgeCache[route] { return cached }
        let name = RouteStyle.displayName(route)
        let fill = NSColor(RouteStyle.color(route))
        let textColor = NSColor(RouteStyle.textColor(route))
        let diameter: CGFloat = 16

        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let font = NSFont.systemFont(ofSize: name.count > 1 ? 7.5 : 10.5, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let size = name.size(withAttributes: attributes)
            name.draw(
                at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = false
        badgeCache[route] = image
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
