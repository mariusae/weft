import AppKit
import SwiftUI
import WeftCore
import WeftUI

/// What a new window opens with: a river — a tab moved out of another
/// window, a saved river recalled — or nothing, with Quick Open showing.
/// Each its own, so each opens a window.
struct RiverSeed: Codable, Hashable {
    var id = UUID()
    var state: River.State?
}

/// A window of the graph, and its rivers — its tabs, in the title bar —
/// kept under the window's name, so a window put back after a restart shows
/// what it did.
struct RiverWindow: View {
    let store: WikiStore
    let seed: RiverSeed?
    @State private var rivers: RiverSet
    /// The window's name, its rivers kept under it; empty for the first.
    @SceneStorage("RiverScene") private var scene = ""
    /// What a window kept before it had tabs of its own: its one river.
    @SceneStorage("River") private var kept: Data?
    /// Whether the seed it was opened with is in it yet.
    @SceneStorage("Seeded") private var seeded = false
    @Environment(\.openWindow) private var openWindow
    /// The windows open: one opened while the first is takes a name of its own.
    @MainActor private static var open: Set<String> = []

    init(store: WikiStore, seed: RiverSeed?) {
        self.store = store
        self.seed = seed
        _rivers = State(initialValue: RiverSet(store: store))
    }

    var body: some View {
        ContentView(moveToWindow: moveToWindow)
            .environment(rivers)
            .environment(rivers.current)
            .focusedSceneValue(\.river, rivers.current)
            .focusedSceneValue(\.rivers, rivers)
            .focusedSceneValue(\.moveTabToWindow, MoveTab(run: moveToWindow))
            .background(WindowReader { window in
                // Rivers are this window's own tabs, in its title bar; not the Mac's.
                window.tabbingMode = .disallowed
                // A snapshot's windows are not put back when Weft opens next.
                if Snapshot.isAsked { window.isRestorable = false }
                // Two fingers swept across the trackpad: the river beside this one.
                TabSwipe.follow(window, rivers: rivers)
                for river in rivers.rivers { river.present = { [weak window, rivers] in
                    rivers.select(river)
                    window?.makeKeyAndOrderFront(nil)
                } }
            })
            .onAppear {
                if seed != nil || Self.open.contains(scene) {
                    if scene.isEmpty || Self.open.contains(scene) { scene = UUID().uuidString }
                }
                Self.open.insert(scene)
                if Snapshot.isAsked { Snapshot.rivers = rivers }
                restore()
            }
            .onDisappear {
                Self.open.remove(scene)
                for river in rivers.rivers { store.release(river) }
            }
            .onChange(of: store.loadedRoot) { restore() }
            // An address opened — `weft://river/…` — comes to a window open,
            // not one opened for it.
            .followingRiverAddresses(rivers)
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }

    /// The window's rivers, once the graph is read: as kept under its name;
    /// what it kept before it had tabs; or what it was opened with.
    private func restore() {
        guard let root = store.loadedRoot else { return }
        rivers.scene = scene
        rivers.load()
        if let kept, let state = try? JSONDecoder().decode(River.State.self, from: kept), state.graph == root.path {
            rivers.start(with: state)
            self.kept = nil
        } else if !seeded, let seed {
            seeded = true
            rivers.start(with: seed.state ?? River.State(graph: root.path, cards: []))
            if seed.state == nil { rivers.current.quickOpenShown = true }
        }
    }

    /// A tab moved to a window of its own.
    private func moveToWindow(_ river: River) {
        guard rivers.rivers.count > 1 else { return }
        let state = river.state
        rivers.close(river)
        openWindow(value: RiverSeed(state: state))
    }
}

/// Moving the window's tab in front to a window of its own: for the menu.
struct MoveTab {
    let run: (River) -> Void
}

extension FocusedValues {
    @Entry var moveTabToWindow: MoveTab?
}

/// The menus' river commands, for the river of the window in front.
struct RiverCommands: Commands {
    let store: WikiStore
    @FocusedValue(\.river) private var river
    @FocusedValue(\.rivers) private var rivers
    @FocusedValue(\.moveTabToWindow) private var moveTab
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tiddler") { river?.newTiddler() }
                .keyboardShortcut("n")
                .disabled(river == nil || store.root == nil)
            Button("New To-Do") { river?.newTodo() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(river == nil || store.root == nil)
            Button("New Titled Tiddler") { river?.newTitledTiddler() }
                .keyboardShortcut("n", modifiers: [.command, .control])
                .disabled(river == nil || store.root == nil)
            Button("New Tiddler from Pasteboard") { river?.newTiddlerFromPasteboard() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(river == nil || store.root == nil)
            Button("New Tab") { rivers?.add() }
                .keyboardShortcut("t")
                .disabled(rivers == nil || store.root == nil)
            Button("Reopen Closed Tab") { rivers?.reopenClosed() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(rivers?.canReopen != true || store.root == nil)
            Button("New Window") { openWindow(value: RiverSeed()) }
                .keyboardShortcut("n", modifiers: [.command, .shift, .option])
                .disabled(store.root == nil)
            Button("Quick Open…") { river?.quickOpenShown = true }
                .keyboardShortcut("o")
                .disabled(river == nil || store.root == nil)
            Button("Recently Deleted…") { river?.deletedShown = true }
                .disabled(river == nil || store.root == nil)
            Button("Open Folder…") { store.chooseGraph() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            ConnectMenuItem()
        }
        CommandGroup(after: .textEditing) {
            Button("Find") { river?.find() }
                .keyboardShortcut("f")
            Button("Find Tiddler") { river?.searchFocusRequest += 1 }
                .keyboardShortcut("f", modifiers: [.command, .option])
        }
        // ⌘W closes the tab in front, as Safari's does; the last, the window.
        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") {
                if let rivers, rivers.rivers.count > 1 { withAnimation(.snappy(duration: 0.2)) { rivers.close(rivers.current) } } else { NSApp.keyWindow?.performClose(nil) }
            }
            .keyboardShortcut("w")
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .option])
        }
        CommandGroup(before: .windowList) {
            Button("Show Previous Tab") { rivers?.step(-1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled((rivers?.rivers.count ?? 0) < 2)
            Button("Show Next Tab") { rivers?.step(1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled((rivers?.rivers.count ?? 0) < 2)
            Button("Move Tab to New Window") { if let river = rivers?.current { moveTab?.run(river) } }
                .disabled((rivers?.rivers.count ?? 0) < 2)
            ForEach(1...9, id: \.self) { number in
                Button("Show Tab \(number)") {
                    guard let rivers else { return }
                    // ⌘9, as in Safari: the last.
                    let index = number == 9 ? rivers.rivers.count - 1 : number - 1
                    if rivers.rivers.indices.contains(index) { rivers.select(rivers.rivers[index]) }
                }
                .keyboardShortcut(KeyEquivalent(Character(String(number))))
                .disabled((rivers?.rivers.count ?? 0) < (number == 9 ? 2 : number))
            }
            Divider()
        }
        CommandGroup(after: .saveItem) {
            Button("Sync Now") { store.syncNow() }
                .keyboardShortcut("r")
                .disabled(store.sync == nil)
        }
        // As Prism's: the row, or line, the caret is on made one to check
        // off, then checked, then a plain item again — the outline's own
        // command, or the text editor's.
        CommandMenu("Format") {
            Button("Checklist Item") { NSApp.sendAction(Selector(("cycleChecklist:")), to: nil, from: nil) }
                .keyboardShortcut(.return, modifiers: .command)
                // Quick Open's ⌘↩ while it shows: a new tab.
                .disabled(river?.isWritingAny != true || river?.quickOpenShown == true)
            Button("Task") { NSApp.sendAction(Selector(("cycleTask:")), to: nil, from: nil) }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(river?.isWritingAny != true || river?.quickOpenShown == true)
        }
        CommandMenu("Story") {
            Button("Today") { river?.openToday() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(river == nil || store.root == nil)
            // In the words being written: by their first line, if untitled.
            Button("Title Tiddler") { if !NSApp.sendAction(Selector(("titlePage:")), to: nil, from: nil) { river?.titleCard() } }
                .keyboardShortcut("t", modifiers: [.command, .control])
                .disabled(river?.cards.isEmpty ?? true)
            Button("Write in Selected Card") { river?.toggleEditing() }
                .disabled(river?.cards.isEmpty ?? true)
            Button("Switch Between Outline and Text") { river?.toggleEditorMode() }
                .disabled(river?.cards.isEmpty ?? true)
            Button("Close All Cards") { river?.closeAll() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Divider()
            Button("Fold Card") { if let river, let card = river.selected { withAnimation(.snappy(duration: 0.22)) { river.setFolded(card, true) } } }
                .keyboardShortcut(.upArrow, modifiers: [.command, .control])
                .disabled(river?.selected == nil)
            Button("Unfold Card") { if let river, let card = river.selected { withAnimation(.snappy(duration: 0.22)) { river.setFolded(card, false) } } }
                .keyboardShortcut(.downArrow, modifiers: [.command, .control])
                .disabled(river?.selected == nil)
            Button("Fold or Unfold Card") {
                if let river, let card = river.selected { withAnimation(.snappy(duration: 0.22)) { river.toggleFold(card) } }
            }
            .keyboardShortcut(".", modifiers: [.command, .control])
            .disabled(river?.selected == nil)
            Button("Fold All Cards") { withAnimation(.snappy) { river?.foldAll() } }
                .keyboardShortcut(.upArrow, modifiers: [.command, .control, .option])
                .disabled(river?.cards.isEmpty ?? true)
            Button("Unfold All Cards") { withAnimation(.snappy) { river?.unfoldAll() } }
                .keyboardShortcut(.downArrow, modifiers: [.command, .control, .option])
                .disabled(river?.cards.isEmpty ?? true)
            Divider()
            // The selected card, as its menu and swipes have it.
            let card = river?.selected
            let task = card.flatMap { store.taskState($0) }
            Button(task == .todo ? "Mark Done" : task == .done ? "Mark Not Done" : "Make a To-Do") {
                guard let card else { return }
                withAnimation(.snappy(duration: 0.2)) { store.setTaskState(card, task == .todo ? .done : .todo) }
            }
            .keyboardShortcut("k", modifiers: [.command, .control])
            .disabled(card == nil || card.map { store.kind($0) == .day } ?? true)
            Button(card.map { store.isInInbox($0) } == true ? "Done with It" : "Add to Inbox") {
                guard let card else { return }
                store.setInbox(card, !store.isInInbox(card))
            }
            .keyboardShortcut("i", modifiers: [.command, .control])
            .disabled(card.map { store.tiddler($0) == nil } ?? true)
            Button(card.map { store.isPinned($0) } == true ? "Unpin" : "Pin") {
                guard let card else { return }
                store.setPinned(card, !store.isPinned(card))
            }
            .keyboardShortcut("p", modifiers: [.command, .control])
            .disabled(card.map { store.tiddler($0) == nil } ?? true)
            Button("Read") { if let card { river?.reading = card } }
                .keyboardShortcut("r", modifiers: [.command, .control])
                .disabled(card.map { !store.canRead($0) } ?? true)
            Button("Close Card") { if let card { withAnimation { river?.close(card) } } }
                .keyboardShortcut("w", modifiers: [.command, .control])
                .disabled(card == nil)
            Button("Delete Tiddler") { if let card { withAnimation { store.delete(card) } } }
                .keyboardShortcut(.delete, modifiers: [.command, .control])
                .disabled(card.map { store.tiddler($0) == nil || store.isShadow($0) } ?? true)
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
            Button("Choose River Icon…") { river?.choosingIcon = true }
                .disabled(river?.name == nil)
            Button("Saved Rivers…") { river?.riversShown = true }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(river == nil || store.root == nil)
            Divider()
            Button("New Query River…") { river?.queryEditor = .new }
                .disabled(river == nil || store.root == nil)
            Button(river?.isQuery == true ? "Edit River Query…" : "Fill River from Query…") { river?.queryEditor = .edit }
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

/// Two fingers swept left or right across the trackpad, as Safari goes back
/// and forward: the river beside the one shown — fingers to the left, the
/// next; to the right, the one before. Only a sweep clearly across, and far
/// enough, once for each; a scroll down the river is left alone.
@MainActor
enum TabSwipe {
    private final class Gesture {
        weak var rivers: RiverSet?
        var across: CGFloat = 0
        var down: CGFloat = 0
        var done = false
        init(rivers: RiverSet) { self.rivers = rivers }
    }

    private static var gestures: [ObjectIdentifier: Gesture] = [:]
    private static var monitor: Any?

    static func follow(_ window: NSWindow, rivers: RiverSet) {
        let key = ObjectIdentifier(window)
        if let known = gestures[key] { known.rivers = rivers; return }
        gestures[key] = Gesture(rivers: rivers)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { handle(event) }
            return event
        }
    }

    private static func handle(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty, let window = event.window,
              let gesture = gestures[ObjectIdentifier(window)], let rivers = gesture.rivers else { return }
        if event.phase.contains(.began) {
            gesture.across = 0
            gesture.down = 0
            gesture.done = false
        }
        guard event.phase.contains(.changed) || event.phase.contains(.began), !gesture.done else { return }
        // Which way the fingers went, whichever way scrolling goes.
        let fingers = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        gesture.across += fingers
        gesture.down += abs(event.scrollingDeltaY)
        guard abs(gesture.across) > 110, abs(gesture.across) > gesture.down * 2.5 else { return }
        gesture.done = true
        let by = gesture.across > 0 ? -1 : 1
        let index = rivers.currentIndex + by
        guard rivers.rivers.indices.contains(index) else { return }
        withAnimation(.snappy(duration: 0.2)) { rivers.step(by) }
    }
}
