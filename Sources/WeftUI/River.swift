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
    public internal(set) var cards: [String] = [] {
        didSet {
            guard cards != oldValue else { return }
            keep()
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
    /// Cards showing only their titles: each told of its own.
    @ObservationIgnored public internal(set) var folded: Set<String> = [] {
        didSet {
            let changed = folded.symmetricDifference(oldValue)
            for title in changed { cardChanged(title) }
            // Kept with the river, as its cards are.
            if !changed.isEmpty { foldsVersion += 1; keep(); onChange() }
        }
    }
    /// The rows folded in each card, as it was left in this river — a card
    /// closed and opened again comes back folded so. A card it has none
    /// for opens as the page was folded last on this device.
    @ObservationIgnored var rows: [String: [OutlineFolds.Mark]] = [:]
    /// Set while what was kept is put back: nothing written of it meanwhile.
    @ObservationIgnored var holding = false

    // MARK: A query river's

    /// What a query river finds; nil for a river of cards alone.
    public internal(set) var query: Query?
    /// How it shows among the rivers: an SF Symbol, and a colour's name.
    public internal(set) var icon: String?
    public internal(set) var color: String?
    /// Its cards put at its top by hand, in order.
    var head: [String] = []
    /// Cards put among what it finds by hand, each at its place.
    var placed: [String: Query.Place] = [:]
    /// What it finds, taken out of it.
    var hidden: [String] = []
    /// What it finds, opened out of its peek.
    @ObservationIgnored var opened: Set<String> = []
    /// What it finds as shown — with those placed among them — after its
    /// head: its order kept while the river is in front.
    @ObservationIgnored var stream: [String] = []
    /// Where each page it found was, in its order, as last found.
    @ObservationIgnored var foundPlaces: [String: Query.Place] = [:]
    /// What it finds now, when that is not what shows, waiting to be shown.
    @ObservationIgnored var waiting: [String]?
    /// How many pages changed in what it finds, waiting to be shown.
    public internal(set) var updates = 0
    @ObservationIgnored var changedSince: Set<String> = []
    @ObservationIgnored var finding: Task<Void, Never>?
    /// Whether the river is the one in front in its window: then what it
    /// finds anew waits to be asked for, not moving what is read.
    @ObservationIgnored public var isShown = false {
        didSet { if isShown, !oldValue { applyUpdates() } }
    }
    /// The query's editor, asked for: for a new query river, or this one.
    public var queryEditor: QueryEditorAsk?

    /// A saved river's file, as the river stands: written whenever its
    /// cards change, or what is folded of them.
    func keep() {
        guard !holding, let name else { return }
        store.keepSavedRiver(name, saved)
    }

    /// What its saved file has of it: its cards, and what is folded of them.
    var saved: SavedRiver {
        guard let query else {
            return SavedRiver(cards: cards, folded: folded.intersection(cards),
                              rows: rows.filter { cards.contains($0.key) && !$0.value.isEmpty })
        }
        let own = ownCards
        let hand = placed.sorted { query.precedes($0.value, $1.value) || (!query.precedes($1.value, $0.value) && $0.key < $1.key) }
        return SavedRiver(cards: head, folded: folded.intersection(own),
                          rows: rows.filter { own.contains($0.key) && !$0.value.isEmpty },
                          query: query, placed: hand.map { SavedRiver.Placed(title: $0.key, place: $0.value) },
                          hidden: hidden, opened: opened, icon: icon, color: color)
    }

    /// The rows folded in a card, as this river has them.
    public func rowFolds(of title: String) -> [OutlineFolds.Mark] {
        watch(title)
        return rows[title] ?? store.folds(of: title)
    }

    /// A card's rows folded or unfolded: kept with the river — and, for the
    /// pages opened next, on this device.
    public func setRowFolds(_ marks: [OutlineFolds.Mark], of title: String) {
        store.setFolds(marks, of: title)
        guard rows[title] != marks else { return }
        rows[title] = marks
        guard cards.contains(title) else { return }
        keep()
        onChange()
    }

    public func isFolded(_ title: String) -> Bool {
        watch(title)
        // What a query river finds peeks, but for what is opened out of it.
        if isFound(title) { return !opened.contains(title) }
        return folded.contains(title)
    }

    public var search = ""
    public var searchFocusRequest = 0
    /// Whether ⌘O's Quick Open is showing.
    public var quickOpenShown = false {
        didSet { if quickOpenShown { quickOpenAsked += 1 } }
    }
    /// Bumped each time Quick Open is asked for, shown already or not: its
    /// field takes the keys again.
    public private(set) var quickOpenAsked = 0
    /// The card whose pages are being read, beside the river or over it.
    public var reading: String?
    /// Whether the pages deleted lately are showing, to bring back.
    public var deletedShown = false

    /// Each card's own word of whether it is selected, written in, or asked
    /// for the caret: a change to one redraws it, not every card.
    @ObservationIgnored private var signals: [String: WikiStore.PageSignal] = [:]

    private func watch(_ title: String) {
        let signal = signals[title] ?? { let made = WikiStore.PageSignal(); signals[title] = made; return made }()
        _ = signal.version
    }

    func cardChanged(_ title: String) { signals[title]?.version += 1 }

    // MARK: Keeping

    /// What is kept of a river: the graph it is of, its name, its cards.
    public struct State: Codable, Hashable, Sendable {
        public var graph: String
        public var name: String?
        public var cards: [String]
        /// The cards showing only their titles; none, in what was kept before.
        public var folded: [String]?
        /// The rows folded in each card; none, in what was kept before.
        public var rows: [String: [OutlineFolds.Mark]]?

        public init(graph: String, name: String? = nil, cards: [String], folded: [String]? = nil,
                    rows: [String: [OutlineFolds.Mark]]? = nil) {
            self.graph = graph
            self.name = name
            self.cards = cards
            self.folded = folded
            self.rows = rows
        }
    }

    /// What is kept of it — of the graph read, once it is.
    public var state: State {
        // A query river's cards are what it finds, and its file has it: its own alone, here.
        let cards = query == nil ? cards : head
        let kept = rows.filter { cards.contains($0.key) }
        return State(graph: store.loadedRoot?.path ?? "", name: name, cards: cards, folded: folded.isEmpty ? nil : cards.filter(folded.contains),
                     rows: kept.isEmpty ? nil : kept)
    }

    /// Shows what was kept: a saved river as its file has it now, which
    /// another device may have changed — folded as it says; one of this
    /// device's as it was.
    public func restore(_ state: State) {
        holding = true
        if let saved = state.name, let kept = store.savedRiver(saved), !store.rivers.contains(where: { $0 !== self && $0.name == saved }) {
            name = saved
            take(kept)
            cards = kept.query == nil ? kept.cards : cards
            folded = kept.folded.intersection(kept.ownCards)
            rows = Dictionary(uniqueKeysWithValues: kept.ownCards.map { ($0, kept.rows[$0] ?? []) })
            if query != nil { refind(now: true) }
        } else {
            name = nil
            take(nil)
            cards = state.cards
            folded = Set(state.folded ?? []).intersection(cards)
            rows = state.rows ?? [:]
        }
        holding = false
        for title in cards { cardChanged(title) }
        focus = nil
    }

    /// The graph changed: nothing of the one before stays open.
    func reset() {
        for title in cards where store.isEditing(title) { store.finishEditing(title, closing: true) }
        name = nil
        take(nil)
        cards = []
        folded = []
        rows = [:]
        focus = nil
        writing = nil
        caretWanted = nil
        backward = []
        forward = []
        historyVersion += 1
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
        // A link to a saved river brings the river back.
        if let name = RiverLink.name(title) { return follow(river: name) }
        // A page opened by an alias, or in other case, is opened by its title.
        let title = store.canonicalTitle(title)
        if query != nil {
            openFound(title, from: source)
        } else if !cards.contains(title) {
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
        // Where the river was, kept to go back to — unless going there.
        if !traveling, let from = focus ?? cardInView, from != title, cards.contains(from) {
            if backward.last != from { backward.append(from) }
            if backward.count > 50 { backward.removeFirst() }
            forward = []
            historyVersion += 1
        }
        focus = title
        focusRequest += 1
    }

    public func openToday() {
        open(Day.today.description)
    }

    /// A day card's neighbour, opened just after it: the day before or after.
    public func openDay(beside title: String, by: Int) {
        guard let day = Day(title) else { return }
        open(day.adding(by).description, from: title)
    }

    /// ⌥⌘[, ⌥⌘]: the day before or after the selected day's card — or
    /// today's, when no day is selected.
    public func stepDay(_ by: Int) {
        if let focus, Day(focus) != nil, cards.contains(focus) {
            openDay(beside: focus, by: by)
        } else {
            open(Day.today.adding(by).description)
        }
    }

    // MARK: Back and forward

    /// The cards the river was at before each jump to another — a link
    /// followed, a card opened or stepped to — and those gone back from.
    @ObservationIgnored private var backward: [String] = []
    @ObservationIgnored private var forward: [String] = []
    @ObservationIgnored private var traveling = false
    /// Bumped when either changes: for what says whether there is a way back.
    public private(set) var historyVersion = 0

    public var canGoBack: Bool { _ = historyVersion; return !backward.isEmpty }
    public var canGoForward: Bool { _ = historyVersion; return !forward.isEmpty }

    /// Where going back would go, the nearest first, each once: for the
    /// list the back button holds.
    public var places: [String] {
        _ = historyVersion
        var seen = Set<String>()
        return backward.reversed().filter { seen.insert($0).inserted }.prefix(12).map { $0 }
    }

    /// ⌘[: back to the card the river was at — opened again if it was closed.
    public func goBack() {
        guard let place = backward.popLast() else { return }
        if let here = focus ?? cardInView, here != place { forward.append(here) }
        travel(to: place)
    }

    /// ⌘]: forward again.
    public func goForward() {
        guard let place = forward.popLast() else { return }
        if let here = focus ?? cardInView, here != place { backward.append(here) }
        travel(to: place)
    }

    /// Back to one of the places, those after it left to go forward to.
    public func goBack(to place: String) {
        guard let index = backward.lastIndex(of: place) else { return }
        while backward.count > index + 1 { forward.append(backward.removeLast()) }
        goBack()
    }

    private func travel(to place: String) {
        historyVersion += 1
        traveling = true
        open(place)
        traveling = false
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
        if query != nil { return moveFound(title, to: target, after: after) }
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
        if query != nil { return closeFound(title) }
        let was = (cards: cards, folded: folded)
        shut(title)
        offerReopening(was, "Close “\(store.shownTitle(title))”")
    }

    private func shut(_ title: String) {
        cards.removeAll { $0 == title }
        folded.remove(title)
        caretParts[title] = nil
        if writing == title { writing = nil }
        store.cardClosed(title)
    }

    public func closeOthers(_ title: String) {
        if query != nil { return closeOwn(keeping: title) }
        let was = (cards: cards, folded: folded)
        for other in cards where other != title { shut(other) }
        offerReopening(was, "Close Other Cards")
    }

    public func closeAll() {
        if query != nil { return closeOwn(keeping: nil) }
        let was = (cards: cards, folded: folded)
        for title in cards { shut(title) }
        offerReopening(was, "Close All Cards")
    }

    /// Cards closed, to undo: back where they were, those opened since kept.
    private func offerReopening(_ was: (cards: [String], folded: Set<String>), _ name: String) {
        guard was.cards != cards else { return }
        store.undoable(name) { [weak self] in
            guard let self else { return }
            let now = cards
            let gone = Set(was.cards).subtracting(now)
            cards = was.cards.filter { gone.contains($0) || now.contains($0) } + now.filter { !was.cards.contains($0) }
            folded.formUnion(was.folded.intersection(gone))
        }
    }

    /// A card brought back where it was: a page's deletion, undone.
    func reopen(_ title: String, at index: Int) {
        guard !cards.contains(title) else { return }
        if query != nil { return openFound(title, from: nil) }
        cards.insert(title, at: min(index, cards.count))
    }

    /// Bumped when any card folds or unfolds: for what says whether all are.
    public internal(set) var foldsVersion = 0

    /// The card the keys act on: the one selected, else the one at the top
    /// of the river as it is scrolled.
    public var selected: String? {
        if let focus, cards.contains(focus) { return focus }
        return cardInView.flatMap { cards.contains($0) ? $0 : nil }
    }

    /// Whether every card shows only its title.
    public var allFolded: Bool {
        _ = foldsVersion
        if query != nil { return !cards.isEmpty && opened.isEmpty && ownCards.allSatisfy(folded.contains) }
        return !cards.isEmpty && cards.allSatisfy(folded.contains)
    }

    /// Every card down to its title — a river at a glance — or all opened again.
    public func foldAll() {
        if query != nil { setOpened([]) }
        folded = Set(query == nil ? cards : ownCards)
    }
    public func unfoldAll() {
        if query != nil { setOpened(Set(stream).subtracting(placed.keys)) }
        folded = []
    }

    public func setFolded(_ title: String, _ fold: Bool) {
        if isFound(title) {
            var now = opened
            if fold { now.remove(title) } else { now.insert(title) }
            return setOpened(now)
        }
        if fold { folded.insert(title) } else { folded.remove(title) }
    }

    public func toggleFold(_ title: String) {
        setFolded(title, !isFolded(title))
    }

    /// A page took another title: its card does too.
    func renamed(_ title: String, to new: String) {
        if let marks = rows.removeValue(forKey: title) { rows[new] = marks }
        if query != nil { renameFound(title, to: new) }
        guard let index = cards.firstIndex(of: title) else { return }
        holding = true
        cards[index] = new
        if folded.remove(title) != nil { folded.insert(new) }
        holding = false
        keep()
        if focus == title { focus = new }
        if writing == title { writing = new }
        if let parts = caretParts.removeValue(forKey: title) { caretParts[new] = parts }
        backward = backward.map { $0 == title ? new : $0 }
        forward = forward.map { $0 == title ? new : $0 }
    }

    /// A page is gone: its card goes too.
    func removed(_ title: String) {
        if query != nil { removeFound(title) }
        cards.removeAll { $0 == title }
        folded.remove(title)
        if writing == title { writing = nil }
    }

    /// A sync brought in another device's saved river of this name: its
    /// cards, and what is folded of them — the cards open refolded.
    func savedChanged(_ kept: SavedRiver) {
        holding = true
        take(kept)
        if query != nil {
            refind(now: !isShown)
        } else if kept.cards != cards {
            cards = kept.cards
        }
        let shut = kept.folded.intersection(kept.ownCards)
        if shut != folded { folded = shut }
        for card in kept.ownCards where rows[card] != (kept.rows[card] ?? []) {
            rows[card] = kept.rows[card] ?? []
            cardChanged(card)
        }
        holding = false
    }

    // MARK: The caret

    /// The card the caret is in.
    @ObservationIgnored private(set) var writing: String? {
        didSet { if (writing != nil) != isWritingAny { isWritingAny = writing != nil } }
    }
    /// Whether the caret is in any card: what is over the keys is the editor's.
    public private(set) var isWritingAny = false
    @ObservationIgnored private var leaving: [String: Task<Void, Never>] = [:]
    /// The parts of each card the caret is in, as each says: the caret
    /// going from one to another — from a new tiddler's title to its body —
    /// may be told of in either order, and the card is not left while any
    /// part has it.
    @ObservationIgnored private var caretParts: [String: Set<CaretPart>] = [:]

    /// A part of a card the caret can be in.
    public enum CaretPart: Hashable { case title, body, fields }
    /// The card asked to take the caret, and whether in its title — taken
    /// by the card's editor once it is there to take it.
    @ObservationIgnored private var caretWanted: (title: String, inTitle: Bool)?

    public func isWriting(_ title: String) -> Bool {
        watch(title)
        return writing == title
    }

    /// The caret came into a card: in its body, its title, or its fields.
    public func caretEntered(_ title: String, in part: CaretPart) {
        caretParts[title, default: []].insert(part)
        leaving[title]?.cancel()
        leaving[title] = nil
        guard writing != title else { return }
        let before = writing
        writing = title
        if let before { cardChanged(before) }
        cardChanged(title)
        select(title)
    }

    /// The caret left part of a card — or, `part` nil, the card is done with
    /// unless the caret is in it: unless it is in another part, or comes back
    /// into one in a moment, the card is done with, unless another river is
    /// writing in it.
    public func caretLeft(_ title: String, from part: CaretPart? = nil) {
        if let part {
            caretParts[title]?.remove(part)
            if caretParts[title]?.isEmpty == true { caretParts[title] = nil }
        }
        // Still in another part: told late that it left this one.
        guard caretParts[title] == nil else { return }
        leaving[title]?.cancel()
        leaving[title] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.25))
            guard !Task.isCancelled, let self, caretParts[title] == nil else { return }
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

    /// ⌘F: words found in the card being written in — or, with none,
    /// pages, in the sidebar's search.
    public func find() {
        if writing != nil { Platform.findInCard() } else { searchFocusRequest += 1 }
    }

    /// A card's words searched: the caret put in it, then its find bar.
    public func find(in title: String) {
        if writing != title { edit(title) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Platform.findInCard() }
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
    /// `tag`, when there is one, and given its fields, its title typed
    /// first; else untitled, what it says typed at once, to be named later
    /// if ever.
    public func newTiddler(taggedWith tag: String? = nil) {
        guard let title = store.makeTiddler(taggedWith: tag, untitled: tag == nil) else { return }
        edit(title, inTitle: tag != nil)
    }

    /// The card ⌃⌘T titles: the one being written in, else the one
    /// selected — any but a day's or a week's, or one of Weft's own.
    public var titleableCard: String? {
        guard let title = writing ?? focus, cards.contains(title), Day(title) == nil, Week(title) == nil,
              !store.isShadow(title) else { return nil }
        return title
    }

    /// Titles a card: an untitled one by its first line, the caret staying
    /// where it is — one saying nothing yet, or titled already, in its
    /// title, to be typed.
    public func titleCard() {
        guard let title = titleableCard else { return }
        let current = store.draftHead(title) ?? store.tiddler(title)
        if let current, Untitled.isName(current.title), WikiStore.titledByFirstLine(current) != nil {
            titleByFirstLine(title)
        } else {
            edit(title, inTitle: true)
        }
    }

    /// An untitled card titled by its first line, that line taken out of
    /// what it says: written at once, when the caret is not in it.
    public func titleByFirstLine(_ title: String) {
        change(title, settling: true) { tiddler in
            if let titled = WikiStore.titledByFirstLine(tiddler) { tiddler = titled }
        }
        store.noteReplaced(title)
    }

    /// A new tiddler with a title, typed first.
    public func newTitledTiddler() {
        guard let title = store.makeTiddler() else { return }
        edit(title, inTitle: true)
    }

    /// A new tiddler of what the pasteboard holds, its title selected to
    /// be typed over — and, should a better one come while it still has the
    /// one it was given, given that.
    public func newTiddlerFromPasteboard() {
        guard let content = PastedTiddler.read(), let made = PastedTiddler.draft(of: content),
              let title = store.makeTiddler(named: made.title, text: made.text) else { return }
        edit(title, inTitle: true)
        let asked = Date()
        Task {
            // Only soon after: later — the first picture read on a Mac takes
            // its model a while to make ready — the title is the person's.
            guard let better = await PastedTiddler.better(for: content), Date().timeIntervalSince(asked) < 8, better.title != made.title,
                  store.isEditing(title), store.draftHead(title)?.title == title, !store.exists(better.title) else { return }
            store.change(title) {
                $0.title = better.title
                // What it says, too, while it says what it was made saying.
                if let text = better.text, $0.text == made.text { $0.text = text }
            }
            // Still being named: the new name selected, to be typed over in turn.
            if caretParts[title]?.contains(.title) == true { edit(title, inTitle: true) }
        }
    }

    // MARK: Saving

    /// Saves the river under a name: a file in the graph, synced, kept as
    /// its cards change. Renames it, when it is saved already.
    public func save(as name: String) {
        if let before = self.name {
            guard let new = store.renameSavedRiver(before, to: name) else { return }
            self.name = new
        } else {
            guard let new = store.addSavedRiver(name, saved) else { return }
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

    /// A link to a saved river followed: the river brought back — to the
    /// front where it shows, else beside this one.
    public func follow(river name: String) {
        guard let saved = store.savedRiverName(name) else {
            store.error = "No saved river is called “\(name)”. Save a river under that name, and the link leads to it."
            return
        }
        recall(saved)
    }

    /// What a river dragged into a card writes there: a link to it, saved;
    /// else its cards' links, a row each.
    public var dropped: String {
        if let name { return RiverLink.link(name) }
        return cards.map { "- [[\($0)]]" }.joined(separator: "\n")
    }

    /// No longer a saved river — its file deleted — but still open, here alone.
    func forget() { name = nil }

    /// Its saved river renamed elsewhere — from the list.
    func named(_ name: String) { self.name = name }
}
