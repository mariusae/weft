import Foundation
import GraphKit
import ReflectCore

/// A saved river as its file has it: its cards, a link each a line; those
/// showing only their titles, in its frontmatter `folded:`; and the rows
/// folded in each, under its card — so that a river folded on one device
/// is folded so on every other.
///
///     ---
///     folded:
///       - Beta
///     ---
///     - [[Alpha]]
///       - 4: Projects
///     - [[Beta]]
///
/// A folded row is its place among the card's rows and its text, as
/// `OutlineFolds` keeps it.
///
/// A query river is one with a query: its cards are those it finds, in
/// its order, after those put at its top by hand — the cards before the
/// block — and with those put among them by hand, each at its place, after
/// it. Those taken out of it are `hidden:`; those of what it finds opened
/// out of their peek, `opened:`.
///
///     ---
///     hidden:
///       - Old Notes
///     ---
///     - [[Pinned]]
///
///     ```query
///     sort: -modified
///     ```
///     - [[Kept Here]] @ 1000 2026-11-03T10:00:00.000Z
struct SavedRiver: Equatable {
    var cards: [String]
    var folded: Set<String> = []
    /// Each card's folded rows; a card without, none.
    var rows: [String: [OutlineFolds.Mark]] = [:]
    /// What it finds, for a query river; nil for one of cards alone.
    var query: Query?
    /// Cards put among what it finds by hand, each at its place.
    var placed: [Placed] = []
    /// What it finds, taken out of it.
    var hidden: [String] = []
    /// What it finds, opened out of its peek.
    var opened: Set<String> = []
    /// How it shows among the rivers: an SF Symbol, and a colour's name.
    var icon: String?
    var color: String?
    /// Where it stands among the saved rivers, as they are put in order by
    /// hand: lower first. Nil, after those placed, by name.
    var place: Double?

    struct Placed: Equatable {
        var title: String
        var place: Query.Place
    }

    static let foldedKey = "folded"

    init(cards: [String], folded: Set<String> = [], rows: [String: [OutlineFolds.Mark]] = [:], query: Query? = nil,
         placed: [Placed] = [], hidden: [String] = [], opened: Set<String> = [], icon: String? = nil, color: String? = nil) {
        self.cards = cards
        self.folded = folded
        self.rows = rows
        self.query = query
        self.placed = placed
        self.hidden = hidden
        self.opened = opened
        self.icon = icon
        self.color = color
    }

    init(text: String) {
        var body = Substring(text)
        if text.hasPrefix("---\n"), let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) {
            let raw = String(text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound])
            let front = Frontmatter(raw: raw)
            folded = Set(front.list(Self.foldedKey))
            hidden = front.list("hidden")
            opened = Set(front.list("opened"))
            icon = front.scalar("icon")
            color = front.scalar("color")
            place = front.scalar("place").flatMap(Double.init)
            body = text[end.upperBound...]
        }
        var cards: [String] = []
        var queryLines: [String]?
        var inQuery = false
        for line in body.split(separator: "\n", omittingEmptySubsequences: true) {
            // The query, in its block; what follows it, placed among what it finds.
            if line.hasPrefix("```") {
                if line.trimmingCharacters(in: .whitespaces) == "```query", queryLines == nil {
                    queryLines = []
                    inQuery = true
                } else if inQuery {
                    inQuery = false
                }
                continue
            }
            if inQuery {
                queryLines?.append(String(line))
                continue
            }
            if queryLines != nil, !line.hasPrefix(" "), !line.hasPrefix("\t"), let placed = Self.placed(line) {
                self.placed.append(placed)
                continue
            }
            let words = line.drop { $0 == " " || $0 == "\t" }
            if words.startIndex != line.startIndex {
                // Indented: a row folded in the card above.
                guard let card = cards.last, words.hasPrefix("- "), let colon = words.firstIndex(of: ":"),
                      let index = Int(words[words.index(words.startIndex, offsetBy: 2)..<colon]) else { continue }
                var text = words[words.index(after: colon)...]
                if text.first == " " { text = text.dropFirst() }
                rows[card, default: []].append(OutlineFolds.Mark(index: index, text: Self.unescape(text)))
            } else if let start = words.range(of: "[["), let end = words.range(of: "]]", range: start.upperBound..<words.endIndex) {
                let title = String(words[start.upperBound..<end.lowerBound])
                if !title.isEmpty { cards.append(title) }
            }
        }
        self.cards = cards
        query = queryLines.map { Query(text: $0.joined(separator: "\n")) }
    }

    /// A card placed among what it finds: `- [[Title]] @ rank key`.
    private static func placed(_ line: Substring) -> Placed? {
        guard line.hasPrefix("- [["), let close = line.range(of: "]] @ ") else { return nil }
        let title = String(line[line.index(line.startIndex, offsetBy: 4)..<close.lowerBound])
        let rest = line[close.upperBound...]
        let space = rest.firstIndex(of: " ") ?? rest.endIndex
        guard !title.isEmpty, let rank = Int(rest[..<space]) else { return nil }
        let key = space < rest.endIndex ? String(rest[rest.index(after: space)...]) : ""
        return Placed(title: title, place: Query.Place(rank: rank, key: key))
    }

    /// Every card it holds by hand: at its top, and placed among what it finds.
    var ownCards: [String] { cards + placed.map(\.title) }

    var text: String {
        var front = ""
        func list(_ key: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            front += "\(key):\n" + items.map { "  - \(NoteCover.quoted($0))\n" }.joined()
        }
        list(Self.foldedKey, ownCards.filter(folded.contains))
        list("opened", opened.sorted())
        list("hidden", hidden)
        if let icon { front += "icon: \(NoteCover.quoted(icon))\n" }
        if let color { front += "color: \(NoteCover.quoted(color))\n" }
        if let place { front += "place: \(Self.number(place))\n" }
        var text = front.isEmpty ? "" : "---\n" + front + "---\n"
        func card(_ card: String, _ line: String) {
            text += line + "\n"
            for mark in rows[card] ?? [] { text += "  - \(mark.index): \(Self.escape(mark.text))\n" }
        }
        for title in cards { card(title, "- [[\(title)]]") }
        if let query {
            text += (cards.isEmpty ? "" : "\n") + "```query\n" + (query.text.isEmpty ? "" : query.text + "\n") + "```\n"
            for placed in placed { card(placed.title, "- [[\(placed.title)]] @ \(placed.place.rank) \(placed.place.key)") }
        }
        return text
    }

    /// A page renamed: its card, and what is folded of it, under the new title.
    func renaming(_ title: String, to new: String) -> SavedRiver {
        var river = self
        river.cards = cards.map { $0 == title ? new : $0 }
        river.placed = placed.map { $0.title == title ? Placed(title: new, place: $0.place) : $0 }
        river.hidden = hidden.map { $0 == title ? new : $0 }
        if river.opened.remove(title) != nil { river.opened.insert(new) }
        if river.folded.remove(title) != nil { river.folded.insert(new) }
        if let marks = river.rows.removeValue(forKey: title) { river.rows[new] = marks }
        return river
    }

    /// A page gone: its card, and what was folded of it.
    func removing(_ title: String) -> SavedRiver {
        var river = self
        river.cards.removeAll { $0 == title }
        river.placed.removeAll { $0.title == title }
        river.hidden.removeAll { $0 == title }
        river.opened.remove(title)
        river.folded.remove(title)
        river.rows[title] = nil
        return river
    }

    /// A place as few figures as say it: `3`, `2.5`.
    static func number(_ place: Double) -> String {
        place == place.rounded() && abs(place) < 1e15 ? String(Int(place)) : String(place)
    }

    /// A row's text on one line: its breaks and backslashes escaped.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func unescape(_ text: Substring) -> String {
        var result = ""
        var escaped = false
        for character in text {
            if escaped {
                result.append(character == "n" ? "\n" : character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }
}
