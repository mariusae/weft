import SwiftUI
import WeftCore
import ReflectCore
import WeftGitHub
import WeftUI

@main
struct WeftApp: App {
    @State private var store: WikiStore = {
        let store = WikiStore()
        store.chooseGraph = { [unowned store] in GraphPanel.choose(for: store) }
        // On the Mac, the graph's checkout is synced through its own `git`,
        // with the Mac's credentials, as Reflect Mac does.
        // A snapshot looks, and must not commit or push anything.
        if !Snapshot.isAsked {
            store.makeSync = { root in CommandLineGit.open(root).map { WikiSync(git: Git(backend: $0)) } }
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
            ContentView()
                .environment(store)
                .frame(minWidth: 760, minHeight: 480)
                .onAppear {
                    store.openInitialGraph()
                    Snapshot.takeIfAsked(store: store)
                }
                // Told by the relay of another device's push: sync at once.
                .onChange(of: store.root, initial: true) { followRelay() }
                .onChange(of: GitHubGraph.account.isSignedIn) { followRelay() }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    relay.reconnect()
                }
        }
        .defaultSize(width: 1240, height: 860)

        Window("GitHub Account", id: "github") {
            GitHubAccountView().environment(GitHubGraph.account)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tiddler") { store.newTiddler() }
                    .keyboardShortcut("n")
                    .disabled(store.root == nil)
                Button("Open Graph…") { store.chooseGraph() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .textEditing) {
                Button("Find Tiddler") { store.searchFocusRequest += 1 }
                    .keyboardShortcut("f")
            }
            CommandGroup(after: .saveItem) {
                Button("Sync Now") { store.sync?.sync() }
                    .keyboardShortcut("r")
                    .disabled(store.sync == nil)
                GitHubAccountMenuItem()
            }
            CommandMenu("Story") {
                Button("Today") { store.openToday() }
                    .keyboardShortcut("t")
                    .disabled(store.root == nil)
                Button("Close All Cards") { store.closeAll() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }
    }
}
