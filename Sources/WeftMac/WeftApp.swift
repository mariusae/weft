import SwiftUI
import WeftCore
import ReflectCore
import WeftUI

@main
struct WeftApp: App {
    @State private var store: WikiStore = {
        let store = WikiStore()
        store.chooseGraph = { [unowned store] in GraphPanel.choose(for: store) }
        // On the Mac, the graph's checkout is synced through its own `git`,
        // with the Mac's credentials, as Reflect Mac does.
        store.makeSync = { root in CommandLineGit.open(root).map { WikiSync(git: Git(backend: $0)) } }
        return store
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 760, minHeight: 480)
                .onAppear {
                    store.openInitialGraph()
                    Snapshot.takeIfAsked(store: store)
                }
        }
        .defaultSize(width: 1240, height: 860)
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
            }
            CommandMenu("Story") {
                Button("Close All Cards") { store.closeAll() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }
    }
}
