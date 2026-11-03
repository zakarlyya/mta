import SwiftUI

@main
struct MTABarApp: App {
    // Stored `State` instead of `@State`: the Command Line Tools SDK lacks the SwiftUI macro plugin.
    private let state = State(initialValue: AppModel())
    private var model: AppModel { state.wrappedValue }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("MTA Bar Settings", id: "settings") {
            SettingsView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Text(model.menuBarTitle)
            .monospacedDigit()
    }
}
