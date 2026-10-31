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
    @State private var relay = Relay()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if store.onboarded && store.root != nil {
                    ContentView()
                } else {
                    Onboarding(allowsFolder: false,
                               openClone: { store.open(graph: GitHubGraph.root) },
                               finish: { store.finishOnboarding() })
                }
            }
            .environment(store)
            .environment(GitHubGraph.account)
            .onAppear(perform: openGraph)
            // While open, told by the relay of another device's push.
            .onChange(of: store.root, initial: true) { follow() }
            .onChange(of: GitHubGraph.account.isSignedIn) { follow() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { relay.reconnect() }
            }
        }
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
