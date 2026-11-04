import Foundation
import ReflectCore
import WeftCore

/// What the query's editor is asked for: a new query river, or this one's.
public enum QueryEditorAsk: String, Identifiable, Sendable {
    case new, edit
    public var id: String { rawValue }
}

/// A query river: one whose cards are what a query finds — in its order,
/// by priority then by what it sorts by — after the cards put at its top
/// by hand, and with cards put among them by hand, each keeping its place
/// as others come and go. What is taken out of it stays out. What it finds
/// peeks, but for what is opened out of it.
///
/// What it finds is found again as the graph changes: shown at once while
/// the river is not in front; while it is, waiting to be asked for — the
/// order of what is being read not moving under the reader.
extension River {
    public var isQuery: Bool { query != nil }

    /// Its cards held by hand: at its top, and placed among what it finds.
    var ownCards: [String] { head + placed.keys.sorted() }

    /// Whether a card is one of what it finds, not one held by hand.
    func isFound(_ title: String) -> Bool {
        query != nil && placed[title] == nil && !head.contains(title)
    }

    /// Whether a card is held by hand in a query river: at its top, or placed.
    public func isHeld(_ title: String) -> Bool {
        query != nil && (placed[title] != nil || head.contains(title))
    }

    /// A saved river's query and what is held by hand, taken as it is; nil,
    /// a river of cards alone.
    func take(_ kept: SavedRiver?) {
        finding?.cancel()
        query = kept?.query
        icon = kept?.icon
        color = kept?.color
        guard let kept, kept.query != nil else {
            head = []; placed = [:]; hidden = []; opened = []; stream = []; foundPlaces = [:]
            waiting = nil; updates = 0; changedSince = []
            return
        }
        head = kept.cards
        placed = Dictionary(kept.placed.map { ($0.title, $0.place) }, uniquingKeysWith: { first, _ in first })
        hidden = kept.hidden
        let before = opened
        opened = kept.opened
        for title in before.symmetricDifference(opened) { cardChanged(title) }
    }

    // MARK: Finding

    /// What it finds, in its order, with those placed by hand among them,
    /// those taken out left out, those at its top not again.
    private func found() -> [String] {
        guard let query else { return [] }
        let order = store.riverOrder(query)
        var places: [String: Query.Place] = [:]
        for item in order where places[item.title] == nil { places[item.title] = item.place }
        self.foundPlaces = places
        let skip = Set(head).union(placed.keys).union(hidden)
        let hand = placed.sorted { query.precedes($0.value, $1.value) || (!query.precedes($1.value, $0.value) && $0.key < $1.key) }
        var result: [String] = []
        result.reserveCapacity(order.count + hand.count)
        var next = 0
        for item in order where !skip.contains(item.title) {
            while next < hand.count, query.precedes(hand[next].value, item.place) {
                result.append(hand[next].key)
                next += 1
            }
            result.append(item.title)
        }
        result += hand[next...].map(\.key)
        return result
    }

    /// Finds again what it finds: shown at once — `now`, or the river not
    /// in front — else waiting to be asked for, counted.
    func refind(now: Bool) {
        let fresh = found()
        if now || !isShown {
            stream = fresh
            waiting = nil
            updates = 0
            changedSince = []
            compose()
        } else if fresh != stream {
            waiting = fresh
            let shown = Set(stream).union(fresh)
            updates = max(1, changedSince.filter(shown.contains).count)
        } else {
            waiting = nil
            updates = 0
            changedSince = []
        }
    }

    /// Its cards as shown: its head, then what it finds.
    func compose() {
        let was = holding
        holding = true
        let now = head + stream
        if now != cards { cards = now }
        holding = was
    }

    /// What it finds anew, shown: the pill over the river tapped, or the
    /// river come to the front.
    public func applyUpdates() {
        guard let waiting else { return }
        stream = waiting
        self.waiting = nil
        updates = 0
        changedSince = []
        compose()
    }

    /// Time has passed — the app come back to the front: what it finds by
    /// how lately pages were edited, found again; pages grown too old leave.
    func timePassed() {
        guard query?.editedSinceDaysAgo != nil else { return }
        refind(now: false)
    }

    /// A page changed: what it finds is found again, a moment later — once
    /// for a run of changes, as typing saves.
    func pageChanged(_ title: String) {
        guard query != nil else { return }
        // The card being written in moving is no news.
        if title != writing { changedSince.insert(title) }
        finding?.cancel()
        finding = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            refind(now: false)
        }
    }

    // MARK: What is done to it

    /// Where a card is in the order: placed by hand, or as last found.
    private func place(of title: String) -> Query.Place? {
        if let place = placed[title] { return place }
        if let place = foundPlaces[title] { return place }
        guard let query else { return nil }
        return store.riverPlace(query, of: title)
    }

    /// A card opened in it: brought into view where it is; else put at its
    /// top — or, opened from a card among what it finds, just after that
    /// one, keeping its place there.
    func openFound(_ title: String, from source: String?) {
        guard let query else { return }
        if cards.contains(title) {
            if isFound(title), !opened.contains(title) { setOpened(opened.union([title])) }
            return
        }
        hidden.removeAll { $0 == title }
        if let source, let index = cards.firstIndex(of: source) {
            if index < head.count {
                head.insert(title, at: index + 1)
            } else {
                let below = cards.indices.contains(index + 1) ? cards[index + 1] : nil
                placed[title] = query.place(between: place(of: source), and: below.flatMap(place(of:)))
                stream.insert(title, at: index + 1 - head.count)
            }
        } else {
            head.insert(title, at: 0)
        }
        compose()
        keep()
    }

    /// A card dragged before or after another: among those at the top, one
    /// of them; among what it finds, placed there — between the two it
    /// was let go between, as the order goes.
    func moveFound(_ title: String, to target: String, after: Bool) {
        guard let query else { return }
        let others = cards.filter { $0 != title }
        guard let at = others.firstIndex(of: target).map({ after ? $0 + 1 : $0 }) else { return }
        let headCount = head.filter { $0 != title }.count
        head.removeAll { $0 == title }
        placed[title] = nil
        stream.removeAll { $0 == title }
        if at <= headCount {
            head.insert(title, at: at)
        } else {
            let above = others[at - 1]
            let below = others.indices.contains(at) ? others[at] : nil
            placed[title] = query.place(between: place(of: above), and: below.flatMap(place(of:)))
            stream.insert(title, at: min(at - headCount, stream.count))
        }
        hidden.removeAll { $0 == title }
        compose()
        keep()
        select(title)
    }

    /// What it holds and hides, as it was: to undo with.
    private struct Held {
        var head: [String], placed: [String: Query.Place], hidden: [String], opened: Set<String>, stream: [String]
    }

    private var held: Held { Held(head: head, placed: placed, hidden: hidden, opened: opened, stream: stream) }

    private func hold(_ was: Held) {
        head = was.head; placed = was.placed; hidden = was.hidden; stream = was.stream
        setOpened(was.opened)
        compose()
        keep()
    }

    /// A card closed: out of the river — and, being one it finds, kept out.
    func closeFound(_ title: String) {
        let was = held
        head.removeAll { $0 == title }
        placed[title] = nil
        if foundPlaces[title] != nil, !hidden.contains(title) { hidden.append(title) }
        stream.removeAll { $0 == title }
        if opened.contains(title) { setOpened(opened.subtracting([title])) }
        folded.remove(title)
        store.cardClosed(title)
        compose()
        keep()
        store.undoable("Remove “\(store.shownTitle(title))”") { [weak self] in self?.hold(was) }
    }

    /// The cards held by hand let go — all, or all but one — what it finds left.
    func closeOwn(keeping kept: String?) {
        let was = held
        head = head.filter { $0 == kept }
        placed = placed.filter { $0.key == kept }
        refind(now: true)
        keep()
        store.undoable(kept == nil ? "Close All Cards" : "Close Other Cards") { [weak self] in self?.hold(was) }
    }

    /// A card found put at the top, to stay there.
    public func keepAtTop(_ title: String) {
        guard query != nil else { return }
        placed[title] = nil
        stream.removeAll { $0 == title }
        head.removeAll { $0 == title }
        head.insert(title, at: 0)
        compose()
        keep()
        bringIntoView(title)
    }

    /// A card held by hand let go: back where the query puts it — or, one
    /// it does not find, out of the river.
    public func releaseToQuery(_ title: String) {
        guard query != nil else { return }
        head.removeAll { $0 == title }
        placed[title] = nil
        refind(now: true)
        keep()
    }

    /// A card taken out of it, back in.
    public func restoreHidden(_ title: String) {
        hidden.removeAll { $0 == title }
        refind(now: true)
        keep()
    }

    /// The cards taken out of it, and those held by hand.
    public var hiddenCards: [String] { hidden }
    public var heldCards: [String] { head + stream.filter { placed[$0] != nil } }

    /// What it finds opened out of its peek, and those told so.
    func setOpened(_ now: Set<String>) {
        let changed = opened.symmetricDifference(now)
        guard !changed.isEmpty else { return }
        opened = now
        for title in changed { cardChanged(title) }
        foldsVersion += 1
        keep()
        onChange()
    }

    /// A page renamed: under its new title wherever it was held or hidden.
    func renameFound(_ title: String, to new: String) {
        head = head.map { $0 == title ? new : $0 }
        if let place = placed.removeValue(forKey: title) { placed[new] = place }
        hidden = hidden.map { $0 == title ? new : $0 }
        if opened.remove(title) != nil { opened.insert(new) }
        stream = stream.map { $0 == title ? new : $0 }
        if let place = foundPlaces.removeValue(forKey: title) { foundPlaces[new] = place }
        if let waiting { self.waiting = waiting.map { $0 == title ? new : $0 } }
    }

    /// A page gone: nowhere in it.
    func removeFound(_ title: String) {
        head.removeAll { $0 == title }
        placed[title] = nil
        hidden.removeAll { $0 == title }
        opened.remove(title)
        stream.removeAll { $0 == title }
        waiting?.removeAll { $0 == title }
        compose()
        keep()
    }

    // MARK: Its query

    /// The river made one of what a query finds — its cards so far at its
    /// top — or given another query, icon or colour; with none, a river of
    /// its cards alone again.
    public func setQuery(_ new: Query?, icon: String?, color: String?) {
        let was = query
        self.icon = icon
        self.color = color
        if let new {
            if was == nil {
                head = cards
                placed = [:]
                hidden = []
                opened = []
            }
            query = new
            refind(now: true)
        } else if was != nil {
            let all = cards
            take(nil)
            cards = all
        }
        keep()
        onChange()
    }

    /// What a query would find, as many as there are: for its editor.
    public func count(_ query: Query) -> Int { store.riverOrder(query).count }
}
