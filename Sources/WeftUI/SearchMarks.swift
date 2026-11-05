import GraphKit
import SwiftUI

/// What a search found, shown: the words asked for marked where they are.
enum SearchMarks {
    /// The words of what is typed — not its `#tags` or `is:` — to mark.
    static func terms(_ typed: String) -> [String] {
        let words = TextQuery(Query(search: typed).textContains, typing: true)
        return (words.words + words.phrases).filter { !$0.isEmpty }
    }

    /// Words with each term marked where it is, case and accents aside.
    static func marked(_ words: String, _ terms: [String]) -> AttributedString {
        var marked = AttributedString(words)
        for term in terms {
            var rest = marked.startIndex..<marked.endIndex
            while let found = marked[rest].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                mark(&marked, found)
                rest = found.upperBound..<marked.endIndex
            }
        }
        return marked
    }

    static func mark(_ text: inout AttributedString, _ range: Range<AttributedString.Index>) {
        text[range].backgroundColor = Ink.accent.color.opacity(0.18)
        text[range].foregroundColor = Ink.text.color
    }
}

extension PageIndex.TextHit.Line {
    /// The line, what was asked marked in it.
    var attributed: AttributedString {
        var text = AttributedString(self.text)
        let characters = text.characters
        for mark in marks where mark.upperBound <= characters.count {
            let start = characters.index(characters.startIndex, offsetBy: mark.lowerBound)
            let end = characters.index(start, offsetBy: mark.count)
            SearchMarks.mark(&text, start..<end)
        }
        return text
    }

    /// The first of what was asked, as the line has it: to find in its page.
    var firstMarked: String? {
        guard let mark = marks.first, mark.upperBound <= text.count else { return nil }
        let start = text.index(text.startIndex, offsetBy: mark.lowerBound)
        return String(text[start..<text.index(start, offsetBy: mark.count)])
    }
}
