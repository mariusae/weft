import Foundation
import Observation
import ReflectCore
import WeftCore

/// A river of open cards — a tab's on the Mac, one of the phone's rivers:
/// which cards are open, the one selected, the one the caret is in. Every
/// river shows the one graph the store holds; a page open in two rivers is
/// one draft in both.
///
/// A river is this device's alone until it is saved under a name: then it
/// is a file in the graph's `rivers/` folder, synced, kept as its cards
/// change, and recalled from the list of saved rivers.
@MainActor @Observable
public final class River: Identifiable {
    public let id = UUID()
    let store: WikiStore

    public init(store: WikiStore) {
        self.store = store
    }

    /// The open cards, top to bottom.
    public private(set) var cards: [String] = [] {
        didSet {
            guard cards != oldValue else { return }
            if let name { store.keepSavedRiver(name, cards) }
            onChange()
        }
    }
    /// The saved river this is; nil for one kept on this device only.
    public private(set) var name: String? {
        didSet { if name != oldValue { onChange() } }
    }
    /// Told when its cards or its name change, to keep them.
    @ObservationIgnored public var onChange: () -> Void = {}
    /// Brings the river's window or tab to the front. Set by the app.
    @ObservationIgnored public var present: () -> Void = {}

    /// The card to bring into view, and a count so that asking again does.
    public private(set) var focus: String? {
        didSet {
            guard focus != oldValue else { return }
            for title in [oldValue, focus].compactMap({ $0 }) { cardChanged(title) }
        }
    }
    public private(set) var focusRequest = 0
    /// The card at the top of the river as it is scrolled, as the river says.
    @ObservationIgnored public var cardInView: String?
    /// Cards showing only their titles.
    public var folded: Set<String> = []

    public var search = ""
    public var searchFocusRequest = 0
    /// Whether ⌘O's Quick Open is showing.
    public var quickOpenShown = false

    /// Each card's own word of whether it is selected, written in, or asked
    /// for the caret: a change to one redraws it, not every card.
    @ObservationIgnored private var signals: [String: WikiStore.PageSignal] = [:]

    private func watch(_ title: String) {
        let signal = signals[title] ?? { let made = WikiStore.PageSignal(); signals[title] = made; return made }()
        _ = signal.version
    }

    private func cardChanged(_ title: String) { signals[title]?.version += 1 }

    // MARK: Keeping

    /// What is kept of a river: the graph it is of, its name, its cards.
    public struct State: Codable, Hashable, Sendable {
        public var graph: String
        public var name: String?
        public var cards: [String]

        public init(graph: String, name: String? = nil, cards: [String]) {
            self.graph = graph
            self.name = name
            self.cards = cards
        }
    }

    /// What is kept of it — of the graph read, once it is.
    public var state: State { State(graph: store.loadedRoot?.path ?? "", name: name, cards: cards) }

    /// Shows what was kept: a saved river as its file has it now, which
    /// another device may have changed; one of this device's as it was.
    public func restore(_ state: State) {
        if let saved = state.name, let kept = store.savedRiver(saved), !store.rivers.contains(where: { $0 !== self && $0.name == saved }) {
            name = saved
            cards = kept
        } else {
            name = nil
            cards = state.cards
        }
        folded = []
        focus = nil
    }

    /// The graph changed: nothing of the one before stays open.
    func reset() {
        for title in cards where store.isEditing(title) { store.finishEditing(title, closing: true) }
        name = nil
        cards = []
        folded = []
        focus = nil
        writing = nil
        caretWanted = nil
    }

    /// The display name: its name when saved, else the card at its top.
    public var title: String {
        if let name { return name }
        return cards.first.map(store.shownTitle) ?? "New River"
    }

    // MARK: Opening and closing

    /// Opens a card, or brings it into view when it is open already. A card
    /// opened from another goes just after it, as in TiddlyWiki; otherwise
    /// at the top.
    public func open(_ title: String, from source: String? = nil) {
        // A page opened by an alias, or in other case, is opened by its title.
        let title = store.canonicalTitle(title)
        if !cards.contains(title) {
            if let source, let index = cards.firstIndex(of: source) {
                cards.insert(title, at: index + 1)
            } else {
                cards.insert(title, at: 0)
            }
        }
        folded.remove(title)
        bringIntoView(title)
    }

    public func bringIntoView(_ title: String) {
        focus = title
        focusRequest += 1
    }

    public func openToday() {
        open(Day.today.description)
    }

    public func openConflicts() {
        for title in store.conflicted().reversed() { open(title) }
    }

    /// ⌥⌘↑, ⌥⌘↓: the card before or after the one selected — or the one in
    /// view — selected and brought into view.
    public func step(_ by: Int) {
        guard !cards.isEmpty else { return }
        let from = focus.flatMap { cards.firstIndex(of: $0) } ?? cardInView.flatMap { cards.firstIndex(of: $0) }
        let index = from.map { min(max($0 + by, 0), cards.count - 1) } ?? 0
        bringIntoView(cards[index])
    }

    public func isSelected(_ title: String) -> Bool {
        watch(title)
        return focus == title
    }

    /// A card dragged to just before or after another, and selected; one
    /// dragged from another river is opened here, there.
    public func move(_ title: String, to target: String, after: Bool) {
        let title = store.canonicalTitle(title)
        guard title != target else { return }
        var moved = cards.filter { $0 != title }
        guard let index = moved.firstIndex(of: target) else { return }
        moved.insert(title, at: after ? index + 1 : index)
        cards = moved
        select(title)
    }

    /// Makes a card the one ⌘↩ and the outline go to, without moving the river.
    public func select(_ title: String) {
        if focus != title { focus = title }
    }

    public func close(_ title: String) {
        cards.removeAll { $0 == title }
        folded.remove(title)
        if writing == title { writing = nil }
        store.cardClosed(title)
    }

    public func closeOthers(_ title: String) {
        for other in cards where other != title { close(other) }
    }

    public func closeAll() {
        for title in cards { close(title) }
    }

    public func toggleFold(_ title: String) {
        if folded.contains(title) { folded.remove(title) } else { folded.insert(title) }
    }

    /// A page took another title: its card does too.
    func renamed(_ title: String, to new: String) {
        guard let index = cards.firstIndex(of: title) else { return }
        cards[index] = new
        if folded.remove(title) != nil { folded.insert(new) }
        if focus == title { focus = new }
        if writing == title { writing = new }
    }

    /// A page is gone: its card goes too.
    func removed(_ title: String) {
        cards.removeAll { $0 == title }
        folded.remove(title)
        if writing == title { writing = nil }
    }

    /// A sync brought in another device's saved river of this name.
    func savedChanged(_ kept: [String]) {
        if kept != cards { cards = kept }
    }

    // MARK: The caret

    /// The card the caret is in.
    @ObservationIgnored private(set) var writing: String? {
        didSet { if (writing != nil) != isWritingAny { isWritingAny = writing != nil } }
    }
    /// Whether the caret is in any card: what is over the keys is the editor's.
    public private(set) var isWritingAny = false
    @ObservationIgnored private var leaving: [String: Task<Void, Never>] = [:]
    /// The card asked to take the caret, and whether in its title — taken
    /// by the card's editor once it is there to take it.
    @ObservationIgnored private var caretWanted: (title: String, inTitle: Bool)?

    public func isWriting(_ title: String) -> Bool {
        watch(title)
        return writing == title
    }

    /// The caret came into a card: in its body, or its title.
    public func caretEntered(_ title: String) {
        leaving[title]?.cancel()
        leaving[title] = nil
        guard writing != title else { return }
        let before = writing
        writing = title
        if let before { cardChanged(before) }
        cardChanged(title)
        select(title)
    }

    /// The caret left part of a card: unless it comes back into another part
    /// in a moment — from the title to the body — the card is done with,
    /// unless another river is writing in it.
    public func caretLeft(_ title: String) {
        leaving[title]?.cancel()
        leaving[title] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.25))
            guard !Task.isCancelled, let self else { return }
            leaving[title] = nil
            if writing == title {
                writing = nil
                cardChanged(title)
            }
            guard !store.rivers.contains(where: { $0.writing == title }) else { return }
            store.finishEditing(title)
        }
    }

    public enum CaretPlace { case body, title }

    /// Where a card has been asked to put the caret, until it has.
    public func wantsCaret(_ title: String) -> CaretPlace? {
        watch(title)
        guard let wanted = caretWanted, wanted.title == title else { return nil }
        return wanted.inTitle ? .title : .body
    }

    /// The caret put where it was asked for.
    public func caretTaken(_ title: String) {
        guard caretWanted?.title == title else { return }
        caretWanted = nil
        cardChanged(title)
    }

    /// Changes what a card says, as the store does.
    /// `settling`: a change made all at once — a tag, a field — after which
    /// the card is done with, unless the caret is writing in it.
    public func change(_ title: String, settling: Bool = false, _ change: (inout Tiddler) -> Void) {
        store.change(title, change)
        if settling, writing != title { caretLeft(title) }
    }

    /// Opens a card and puts the caret in it — in its title, `inTitle`.
    public func edit(_ title: String, inTitle: Bool = false) {
        open(title)
        let title = store.canonicalTitle(title)
        if let before = caretWanted?.title, before != title { cardChanged(before) }
        caretWanted = (title, inTitle)
        cardChanged(title)
    }

    /// ⌘↩ on the Mac: the card being written in, or else the selected
    /// one, edited as text if an outline, as an outline if text — the
    /// caret, if it was in it, in the other editor.
    public func toggleEditorMode() {
        guard let title = writing ?? focus, cards.contains(title) else { return }
        let wasWriting = writing == title
        store.setEditorMode(store.editorMode(title) == .outline ? .text : .outline, for: title)
        if wasWriting { DispatchQueue.main.async { self.edit(title) } }
    }

    /// The caret into the selected card, or out of the one it is in.
    public func toggleEditing() {
        guard let title = focus, cards.contains(title) else { return }
        if writing == title {
            Platform.endEditing()
        } else {
            edit(title)
        }
    }

    /// A new tiddler, at the top of the river, being edited — tagged with
    /// `tag`, when there is one, and given its fields.
    public func newTiddler(taggedWith tag: String? = nil) {
        guard let title = store.makeTiddler(taggedWith: tag) else { return }
        edit(title, inTitle: true)
    }

    // MARK: Saving

    /// Saves the river under a name: a file in the graph, synced, kept as
    /// its cards change. Renames it, when it is saved already.
    public func save(as name: String) {
        if let before = self.name {
            guard let new = store.renameSavedRiver(before, to: name) else { return }
            self.name = new
        } else {
            guard let new = store.addSavedRiver(name, cards) else { return }
            self.name = new
        }
    }

    /// What a name is being asked for: to save this river, or to rename or
    /// duplicate a saved one.
    public enum Naming: Equatable, Sendable {
        case save, rename(String), clone(String)
    }

    public var naming: Naming?
    /// Whether the saved rivers are showing: the Mac's popover, the phone's sheet.
    public var riversShown = false
    /// Opens a river beside this one: a new tab on the Mac, another of the
    /// phone's rivers. Set by the app.
    @ObservationIgnored public var openNew: (State) -> Void = { _ in }

    /// Brings back a saved river: the one showing it to the front, when one
    /// does; else here, when nothing is open here; else beside this one.
    public func recall(_ saved: String) {
        if let showing = store.river(named: saved) { return showing.present() }
        let state = State(graph: store.root?.path ?? "", name: saved, cards: [])
        if cards.isEmpty { restore(state) } else { openNew(state) }
    }

    /// No longer a saved river — its file deleted — but still open, here alone.
    func forget() { name = nil }

    /// Its saved river renamed elsewhere — from the list.
    func named(_ name: String) { self.name = name }
}
