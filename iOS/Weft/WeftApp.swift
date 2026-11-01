import SwiftUI
import WeftCore
import WeftGitHub
import WeftUI

/// Weft on the iPhone and the iPad: the graph cloned from GitHub, shown as
/// the Mac shows it — the sidebar beside the river on the iPad, before it
/// on the iPhone.
@main
struct WeftApp: App {
    /// One store, for the window and for silent pushes that come without one.
    static let store: WikiStore = {
        let store = WikiStore()
        store.makeSync = { root in GitHubGraph.sync(for: root) }
        return store
    }()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = WeftApp.store
    /// The rivers open, one shown at a time.
    @State private var rivers = RiverSet(store: WeftApp.store)
    @State private var relay = Relay()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if store.onboarded && store.root != nil {
                    ContentView()
                        .environment(rivers)
                        .environment(rivers.current)
                } else {
                    Onboarding(allowsFolder: false,
                               openClone: { store.open(graph: GitHubGraph.root) },
                               finish: { store.finishOnboarding() })
                }
            }
            .environment(store)
            .environment(GitHubGraph.account)
            .onAppear(perform: openGraph)
            .onChange(of: store.loadedRoot, initial: true) { rivers.load() }
            // While open, told by the relay of another device's push.
            .onChange(of: store.root, initial: true) { follow() }
            .onChange(of: GitHubGraph.account.isSignedIn) { follow() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { relay.reconnect() }
            }
        }
        .commands { PadCommands(river: rivers.current, store: store) }
    }

    private func follow() {
        Push.shared.register()
        relay.follow(store.sync == nil ? nil : store.root) { store.syncNow(announcing: false) }
    }

    /// The graph given with `-GraphPath` (for trying the app out), else the clone.
    private func openGraph() {
        guard store.root == nil else { return }
        store.openInitialGraph()
        if store.root == nil, store.onboarded, GitHubGraph.exists { store.open(graph: GitHubGraph.root) }
    }
}

/// With a keyboard on the iPad, the Mac's keys: held ⌘ lists them.
private struct PadCommands: Commands {
    let river: River
    let store: WikiStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tiddler") { river.newTiddler() }
                .keyboardShortcut("n")
            Button("Quick Open…") { river.quickOpenShown = true }
                .keyboardShortcut("o")
            Button("Find Tiddler") { river.searchFocusRequest += 1 }
                .keyboardShortcut("f")
            Button("Sync Now") { store.syncNow() }
                .keyboardShortcut("r")
                .disabled(store.sync == nil)
        }
        CommandMenu("Story") {
            Button("Today") { river.openToday() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Switch Between Outline and Text") { river.toggleEditorMode() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Close All Cards") { river.closeAll() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Divider()
            Button("Back") { river.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { river.goForward() }
                .keyboardShortcut("]")
            Button("Previous Day") { river.stepDay(-1) }
                .keyboardShortcut("[", modifiers: [.command, .option])
            Button("Next Day") { river.stepDay(1) }
                .keyboardShortcut("]", modifiers: [.command, .option])
            Divider()
            Button("Previous Card") { river.step(-1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Next Card") { river.step(1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }
    }
}
