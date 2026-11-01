import AppKit
import SwiftUI
import WeftCore
import WeftUI

/// What a new window — a new tab — opens with: a saved river recalled, or
/// nothing, with Quick Open showing. Each its own, so each opens a window.
struct RiverSeed: Codable, Hashable {
    var id = UUID()
    var state: River.State?
}

/// A window of the graph — a tab, with others — and its river: kept with
/// the window, so a window put back after a restart shows what it did.
struct RiverWindow: View {
    let store: WikiStore
    let seed: RiverSeed?
    @State private var river: River
    @SceneStorage("River") private var kept: Data?
    /// Whether what it shows is the graph's — put back, or begun — and so
    /// worth keeping: not before, or the empty river shown meanwhile would
    /// be kept in place of what was.
    @State private var restored = false
    @Environment(\.openWindow) private var openWindow

    init(store: WikiStore, seed: RiverSeed?) {
        self.store = store
        self.seed = seed
        _river = State(initialValue: River(store: store))
    }

    var body: some View {
        ContentView()
            .environment(river)
            .focusedSceneValue(\.river, river)
            .background(WindowReader { window in
                // Weft's windows are tabs of one, whatever the Mac's
                // setting: a new one joins the window it was opened from.
                window.tabbingMode = .preferred
                window.tabbingIdentifier = "WeftRiver"
                joinTabs(window)
                // A snapshot's windows are not put back when Weft opens next.
                if Snapshot.isAsked { window.isRestorable = false }
                river.present = { [weak window] in window?.makeKeyAndOrderFront(nil) }
            })
            .onAppear {
                let first = store.rivers.isEmpty
                store.adopt(river)
                river.openNew = { state in openWindow(value: RiverSeed(state: state)) }
                restore(first: first)
            }
            .onDisappear { store.release(river) }
            .onChange(of: store.loadedRoot) { _, root in
                if root == nil { restored = false } else { restore(first: store.rivers.count <= 1) }
            }
            .onChange(of: river.state) { _, state in
                guard restored, !state.graph.isEmpty else { return }
                kept = try? JSONEncoder().encode(state)
                if state.name == nil { store.lastRiver = state.cards }
            }
    }

    /// What the window shows, once the graph is read: what it kept; else
    /// what it was opened with; else, the first window, the cards open last
    /// — and any other, nothing yet, Quick Open showing.
    private func restore(first: Bool) {
        guard let root = store.loadedRoot else { return }
        defer { restored = true }
        if let kept, let state = try? JSONDecoder().decode(River.State.self, from: kept), state.graph == root.path {
            river.restore(state)
        } else if let state = seed?.state {
            river.restore(state)
        } else if first, seed == nil {
            river.restore(River.State(graph: root.path, cards: store.lastRiver ?? store.defaultCards()))
        } else {
            river.restore(River.State(graph: root.path, cards: []))
            river.quickOpenShown = true
        }
    }
}

/// Puts a window opened beside others among their tabs — the tabs of the
/// window in front — unless it is among them already.
@MainActor private func joinTabs(_ window: NSWindow) {
    DispatchQueue.main.async {
        guard window.tabbedWindows == nil || window.tabbedWindows?.count == 1 else { return }
        let others = NSApp.windows.filter { $0 !== window && $0.isVisible && $0.tabbingIdentifier == window.tabbingIdentifier }
        guard let host = [NSApp.keyWindow, NSApp.mainWindow].compactMap({ $0 }).first(where: others.contains) ?? others.first else { return }
        host.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
    }
}

/// The window a view is in, once it is in one.
private struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> Reader {
        let view = Reader()
        view.found = found
        return view
    }

    func updateNSView(_ view: Reader, context: Context) {}

    final class Reader: NSView {
        var found: (NSWindow) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found(window) }
        }
    }
}

/// The menus' river commands, for the river of the window in front.
struct RiverCommands: Commands {
    let store: WikiStore
    @FocusedValue(\.river) private var river
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tiddler") { river?.newTiddler() }
                .keyboardShortcut("n")
                .disabled(river == nil || store.root == nil)
            Button("New Tab") { openWindow(value: RiverSeed()) }
                .keyboardShortcut("t")
                .disabled(store.root == nil)
            Button("Quick Open…") { river?.quickOpenShown = true }
                .keyboardShortcut("o")
                .disabled(river == nil || store.root == nil)
            Button("Open Folder…") { store.chooseGraph() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            ConnectMenuItem()
        }
        CommandGroup(after: .textEditing) {
            Button("Find Tiddler") { river?.searchFocusRequest += 1 }
                .keyboardShortcut("f")
        }
        CommandGroup(after: .saveItem) {
            Button("Sync Now") { store.syncNow() }
                .keyboardShortcut("r")
                .disabled(store.sync == nil)
        }
        CommandMenu("Story") {
            Button("Today") { river?.openToday() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(river == nil || store.root == nil)
            Button("Write in Selected Card") { river?.toggleEditing() }
                .disabled(river?.cards.isEmpty ?? true)
            Button("Switch Between Outline and Text") { river?.toggleEditorMode() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(river?.cards.isEmpty ?? true)
            Button("Close All Cards") { river?.closeAll() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Divider()
            Button("Back") { river?.goBack() }
                .keyboardShortcut("[")
                .disabled(!(river?.canGoBack ?? false))
            Button("Forward") { river?.goForward() }
                .keyboardShortcut("]")
                .disabled(!(river?.canGoForward ?? false))
            Button("Previous Day") { river?.stepDay(-1) }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(river == nil || store.root == nil)
            Button("Next Day") { river?.stepDay(1) }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(river == nil || store.root == nil)
            Divider()
            Button("Previous Card") { river?.step(-1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(river?.cards.isEmpty ?? true)
            Button("Next Card") { river?.step(1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(river?.cards.isEmpty ?? true)
            Divider()
            Button(river?.name == nil ? "Save River…" : "Rename River…") {
                guard let river else { return }
                river.naming = river.name.map { .rename($0) } ?? .save
            }
            .disabled(river == nil || store.root == nil)
            Button("Saved Rivers…") { river?.riversShown = true }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(river == nil || store.root == nil)
        }
    }
}

struct ConnectMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Connect to GitHub…") { openWindow(id: "github") }
    }
}
