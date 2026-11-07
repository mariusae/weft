import ReflectGit2
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
        // History read through libgit2: no account needed.
        store.makeHistory = { root in LibGit2Backend(root: root) }
        return store
    }()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // + held, dictating: written down by ElevenLabs, through the relay,
        // while signed in to GitHub — Apple's, else.
        if SyncRelay.host != nil {
            PhoneDictation.useScribe { @MainActor in
                let account = GitHubGraph.account
                guard account.isSignedIn else { throw GitHubError("Not signed in to GitHub") }
                return try await SyncRelay.scribeToken(accessToken: try await account.validAccessToken())
            }
        }
    }
    @State private var store = WeftApp.store
    @State private var relay = Relay()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if store.onboarded && store.root != nil {
                    WindowRivers()
                        .environment(\.accountSettings, AnyView(AccountSettings(open: { store.open(graph: GitHubGraph.root) })))
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
        .commands { PadCommands(store: store) }
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

/// A window's rivers, its own: on the iPad, a second window shows other
/// cards than the first, each kept under the window's name.
private struct WindowRivers: View {
    @Environment(WikiStore.self) private var store
    @State private var rivers = RiverSet(store: WeftApp.store)
    /// The window's name, kept with it; empty for the first, as the phone's.
    @SceneStorage("riverScene") private var scene = ""
    /// The windows open: a new one, while the first is, takes a name of its own.
    @MainActor private static var open: Set<String> = []

    var body: some View {
        ContentView()
            .environment(rivers)
            .environment(rivers.current)
            .focusedSceneValue(\.river, rivers.current)
            .onAppear {
                if Self.open.contains(scene) { scene = UUID().uuidString }
                Self.open.insert(scene)
                rivers.scene = scene
                rivers.load()
            }
            .onDisappear { Self.open.remove(scene) }
            .onChange(of: store.loadedRoot) { rivers.load() }
            .followingRiverAddresses(rivers)
    }
}

/// With a keyboard on the iPad, the Mac's keys: held ⌘ lists them — acting
/// on the window in front.
private struct PadCommands: Commands {
    @FocusedValue(\.river) private var focused
    let store: WikiStore

    var body: some Commands {
        if let river = focused { keys(river) }
    }

    @CommandsBuilder private func keys(_ river: River) -> some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tiddler") { river.newTiddler() }
                .keyboardShortcut("n")
            Button("Quick Open…") { river.quickOpenShown = true }
                .keyboardShortcut("o")
            Button("Find") { river.find() }
                .keyboardShortcut("f")
            Button("Find Tiddler") { river.searchFocusRequest += 1 }
                .keyboardShortcut("f", modifiers: [.command, .option])
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
            Button("Fold Card") { if let card = river.selected { river.setFolded(card, true) } }
                .keyboardShortcut(.upArrow, modifiers: [.command, .control])
            Button("Unfold Card") { if let card = river.selected { river.setFolded(card, false) } }
                .keyboardShortcut(.downArrow, modifiers: [.command, .control])
            Button("Fold All Cards") { river.foldAll() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .control, .option])
            Button("Unfold All Cards") { river.unfoldAll() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .control, .option])
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

/// Settings' GitHub section: who is signed in, the repositories Weft may
/// see, and signing out — onboarding's own view, a tap away.
private struct AccountSettings: View {
    @Environment(GitHubAccount.self) private var account
    let open: () -> Void

    var body: some View {
        Section {
            NavigationLink {
                GitHubConnect(open: open).navigationTitle("GitHub")
            } label: {
                LabeledContent("GitHub", value: account.user.map { "@" + $0.login } ?? (account.isSignedIn ? "Signed in" : "Signed out"))
            }
        } header: {
            Text("Account")
        } footer: {
            Text("The graph is kept in a GitHub repository and synced with it.")
        }
    }
}
