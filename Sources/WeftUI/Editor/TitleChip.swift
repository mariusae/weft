import Foundation
import ReflectCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// An untitled page's first line, made its title: from the card's More,
/// or ⌃⌘T on the Mac.
enum FirstLineTitle {
    /// The first line with anything on it, as a paragraph: its line break too.
    static func line(in text: NSString) -> NSRange? {
        var location = 0
        while location < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            guard paragraph.length > 0 else { break }
            if !text.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return paragraph }
            location = NSMaxRange(paragraph)
        }
        return nil
    }

    /// A paragraph without its line break.
    static func words(of line: NSRange, in text: NSString) -> NSRange {
        var words = line
        while words.length > 0, [10, 13].contains(text.character(at: NSMaxRange(words) - 1)) { words.length -= 1 }
        return words
    }

    /// The title the line makes: empty, when it has no words to make one.
    static func title(of line: NSRange, in text: NSString) -> String {
        Untitled.title(from: text.substring(with: words(of: line, in: text)))
    }

    /// What goes when the line is made the title: it, the blank lines
    /// before it, and those after it.
    static func taken(by line: NSRange, in text: NSString) -> NSRange {
        var end = NSMaxRange(line)
        while end < text.length {
            let next = text.paragraphRange(for: NSRange(location: end, length: 0))
            guard next.length > 0, text.substring(with: next).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
            end = NSMaxRange(next)
        }
        return NSRange(location: 0, length: end)
    }
}

extension TiddlerTextView {
    private var shownText: NSString {
        #if os(macOS)
        string as NSString
        #else
        (text ?? "") as NSString
        #endif
    }

    /// The first line with words made the title, taken out of what it
    /// says — with the blank lines round it — the caret where it began.
    /// False, when the page has a title, or nothing to be titled by.
    @discardableResult
    func titleByFirstLine() -> Bool {
        let text = shownText
        guard isUntitled(), let line = FirstLineTitle.line(in: text) else { return false }
        let title = FirstLineTitle.title(of: line, in: text)
        guard !title.isEmpty else { return false }
        let taken = FirstLineTitle.taken(by: line, in: text)
        // Titled first: the text, changed, is saved under it.
        onTitle(title)
        replace(taken, with: "")
        selection = NSRange(location: 0, length: 0)
        return true
    }
}
