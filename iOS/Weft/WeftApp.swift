import SwiftUI
import WeftCore
import WeftGitHub
import WeftUI

/// Weft on the iPhone and the iPad: the graph cloned from GitHub, shown as
/// the Mac shows it — the sidebar beside the river on the iPad, before it
/// on the iPhone.
@main
struct WeftApp: App {
    @State private var store: WikiStore = {
        let store = WikiStore()
        store.makeSync = { root in GitHubGraph.sync(for: root) }
        return store
    }()
    @State private var connecting = false

    var body: some Scene {
        WindowGroup {
            Group {
                if store.root == nil {
                    ConnectView { repository in
                        try await GitHubGraph.clone(repository)
                        store.open(graph: GitHubGraph.root)
                    }
                } else {
                    ContentView()
                }
            }
            .environment(store)
            .environment(GitHubGraph.account)
            .onAppear(perform: openGraph)
        }
    }

    /// The graph given with `-GraphPath` (for trying the app out), else the clone.
    private func openGraph() {
        guard store.root == nil else { return }
        store.openInitialGraph()
        if store.root == nil, GitHubGraph.exists { store.open(graph: GitHubGraph.root) }
    }
}
