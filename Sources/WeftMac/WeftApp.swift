import ReflectCore
import SwiftUI
import WeftCore
import WeftGitHub
import WeftUI

@main
struct WeftApp: App {
    @State private var store: WikiStore = {
        let store = WikiStore()
        store.chooseGraph = { [unowned store] in _ = GraphPanel.choose(for: store) }
        // A snapshot looks, and must not commit or push anything.
        if !Snapshot.isAsked {
            store.makeSync = { root in
                // Weft's own clone of a GitHub repository is synced as the
                // phone's is: libgit2, with the GitHub App's token. A folder
                // of the Mac's — Reflect Mac's checkout — through its own
                // `git`, with the Mac's credentials.
                if root.standardizedFileURL == GitHubGraph.root.standardizedFileURL { return GitHubGraph.sync(for: root) }
                return CommandLineGit.open(root).map { WikiSync(git: Git(backend: $0)) }
            }
        }
        return store
    }()
    @State private var relay = Relay()

    private func followRelay() {
        guard store.sync != nil else { return relay.follow(nil) {} }
        relay.follow(store.root) { [store] in store.sync?.sync() }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if store.onboarded && store.root != nil {
                    ContentView()
                        .frame(minWidth: 760, minHeight: 480)
                } else {
                    Onboarding(allowsFolder: true,
                               chooseFolder: { GraphPanel.choose(for: store) },
                               openClone: { store.open(graph: GitHubGraph.root) },
                               finish: { store.finishOnboarding() })
                }
            }
            .environment(store)
            .withGitHubAccount(Snapshot.usesAccount)
            .onAppear {
                store.openInitialGraph()
                Snapshot.takeIfAsked(store: store)
            }
            // Told by the relay of another device's push: sync at once.
            .onChange(of: store.root, initial: true) { followRelay() }
            .onChange(of: Snapshot.usesAccount && GitHubGraph.account.isSignedIn) { followRelay() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                relay.reconnect()
            }
            // Quitting: what is being edited is written first.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                store.saveEditing()
            }
        }
        .defaultSize(width: 1240, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tiddler") { store.newTiddler() }
                    .keyboardShortcut("n")
                    .disabled(store.root == nil)
                Button("Quick Open…") { store.quickOpenShown = true }
                    .keyboardShortcut("o")
                    .disabled(store.root == nil)
                Button("Open Folder…") { store.chooseGraph() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                ConnectMenuItem()
            }
            CommandGroup(after: .textEditing) {
                Button("Find Tiddler") { store.searchFocusRequest += 1 }
                    .keyboardShortcut("f")
            }
            CommandGroup(after: .saveItem) {
                Button("Sync Now") { store.sync?.sync() }
                    .keyboardShortcut("r")
                    .disabled(store.sync == nil)
            }
            CommandMenu("Story") {
                Button("Today") { store.openToday() }
                    .keyboardShortcut("t")
                    .disabled(store.root == nil)
                Button("Close All Cards") { store.closeAll() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }

        Window("GitHub", id: "github") {
            GitHubWindow()
                .environment(store)
                .withGitHubAccount(Snapshot.usesAccount)
        }
        .defaultSize(width: 480, height: 560)
    }
}

/// File ▸ Connect to GitHub…: signing in, and bringing a graph down — or,
/// with a folder open, signing in for instant sync.
private struct GitHubWindow: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            GitHubConnect {
                store.open(graph: GitHubGraph.root)
                dismissWindow(id: "github")
            }
            Text("Signed in, Weft also hears from the sync relay as soon as another device pushes, whichever graph is open.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(14)
        }
    }
}

extension View {
    /// The GitHub account, for the views that sign in — but not in a
    /// snapshot that does not show them: the account reads the keychain,
    /// which may ask the person at the keyboard.
    @ViewBuilder func withGitHubAccount(_ used: Bool) -> some View {
        if used { environment(GitHubGraph.account) } else { self }
    }
}

private struct ConnectMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Connect to GitHub…") { openWindow(id: "github") }
    }
}
