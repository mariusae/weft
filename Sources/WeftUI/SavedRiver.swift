import Foundation
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
struct SavedRiver: Equatable {
    var cards: [String]
    var folded: Set<String> = []
    /// Each card's folded rows; a card without, none.
    var rows: [String: [OutlineFolds.Mark]] = [:]

    static let foldedKey = "folded"

    init(cards: [String], folded: Set<String> = [], rows: [String: [OutlineFolds.Mark]] = [:]) {
        self.cards = cards
        self.folded = folded
        self.rows = rows
    }

    init(text: String) {
        var body = Substring(text)
        if text.hasPrefix("---\n"), let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) {
            let raw = String(text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound])
            folded = Set(Frontmatter(raw: raw).list(Self.foldedKey))
            body = text[end.upperBound...]
        }
        var cards: [String] = []
        for line in body.split(separator: "\n", omittingEmptySubsequences: true) {
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
    }

    var text: String {
        var text = ""
        let shut = cards.filter(folded.contains)
        if !shut.isEmpty {
            text += "---\n\(Self.foldedKey):\n" + shut.map { "  - \(NoteCover.quoted($0))\n" }.joined() + "---\n"
        }
        for card in cards {
            text += "- [[\(card)]]\n"
            for mark in rows[card] ?? [] { text += "  - \(mark.index): \(Self.escape(mark.text))\n" }
        }
        return text
    }

    /// A page renamed: its card, and what is folded of it, under the new title.
    func renaming(_ title: String, to new: String) -> SavedRiver {
        var river = self
        river.cards = cards.map { $0 == title ? new : $0 }
        if river.folded.remove(title) != nil { river.folded.insert(new) }
        if let marks = river.rows.removeValue(forKey: title) { river.rows[new] = marks }
        return river
    }

    /// A page gone: its card, and what was folded of it.
    func removing(_ title: String) -> SavedRiver {
        var river = self
        river.cards.removeAll { $0 == title }
        river.folded.remove(title)
        river.rows[title] = nil
        return river
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
