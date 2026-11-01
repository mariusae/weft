import Foundation
import ReflectCore
import WeftCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Markdown written as it reads: headings large, emphasis emphatic, code
/// in a fixed face, a `[[link]]` a token — a link to no tiddler drawn as
/// missing. The markup shows, faint, only on the lines the caret is on;
/// elsewhere it is hidden, and what a line shows besides words — its
/// pictures, the card of a link alone in it, a tiddler embedded, what a
/// query finds — is drawn under it, in room kept for it.
@MainActor
struct MarkdownStyler {
    var size: CGFloat
    /// Whether a tiddler has a title, to draw links to it.
    var exists: (String) -> Bool

    #if os(macOS)
    static let defaultSize: CGFloat = 14
    #else
    static let defaultSize: CGFloat = 17
    #endif

    func style(_ storage: NSTextStorage) { style(storage, around: nil) }

    /// Styles the paragraphs an edit touched — or every one, when `edited`
    /// is nil — knowing whether they are inside a fenced block from the
    /// fences before them. Styling only what changed leaves the rest of the
    /// text laid out as it was: typing costs a paragraph, however long the
    /// page. `revealed`: the paragraphs whose markup shows. `room`: how tall
    /// what is drawn under a line is.
    func style(_ storage: NSTextStorage, around edited: NSRange?, revealed: NSRange? = nil,
               room: @escaping (EditorAttachment) -> CGFloat = { _ in 0 }) {
        let text = storage.string as NSString
        let whole = NSRange(location: 0, length: text.length)
        let range = edited.map { text.paragraphRange(for: NSRange(location: min($0.location, text.length), length: min($0.length, text.length - min($0.location, text.length)))) } ?? whole
        var fence: String?
        var fenceStart = 0
        if range.location > 0 {
            // Inside a fence or not: the fences before say.
            text.enumerateSubstrings(in: NSRange(location: 0, length: range.location), options: [.byParagraphs]) { line, lineRange, _, _ in
                guard let line, line.hasPrefix("```") else { return }
                if fence == nil {
                    fence = line.drop { $0 == "`" }.trimmingCharacters(in: .whitespaces)
                    fenceStart = lineRange.location
                } else {
                    fence = nil
                }
            }
        }
        storage.beginEditing()
        storage.setAttributes(base, range: range)
        text.enumerateSubstrings(in: range, options: [.byParagraphs]) { line, lineRange, enclosing, _ in
            guard let line else { return }
            let shown = revealed.map { NSIntersectionRange($0, enclosing).length > 0 || $0.location == enclosing.location } ?? false
            var look = LineLook()
            if let current = fence {
                if current == "query", !shown {
                    look.hidden = true
                } else {
                    storage.addAttributes([.font: mono, .foregroundColor: current == "query" ? Palette.accent : Palette.text], range: lineRange)
                }
                if line.hasPrefix("```") {
                    fence = nil
                    if !look.hidden { storage.addAttribute(.foregroundColor, value: Palette.faint, range: lineRange) }
                    // What a query finds, under its block.
                    if current == "query" {
                        look.attachment = .block(text.substring(with: NSRange(location: fenceStart, length: NSMaxRange(lineRange) - fenceStart)))
                    }
                }
            } else if line.hasPrefix("```") {
                fence = line.drop { $0 == "`" }.trimmingCharacters(in: .whitespaces)
                fenceStart = lineRange.location
                if fence == "query", !shown {
                    look.hidden = true
                } else {
                    storage.addAttributes([.font: mono, .foregroundColor: Palette.faint], range: lineRange)
                }
            } else {
                look = styleLine(line, range: lineRange, shown: shown, in: storage)
            }
            apply(look, to: enclosing, in: storage, room: room)
        }
        storage.endEditing()
    }

    /// How a line is laid out, besides its words: hidden whole, indented,
    /// with something drawn under it.
    private struct LineLook {
        var hidden = false
        /// Where its first line starts, and where the lines it wraps onto do.
        var firstIndent: CGFloat = 0
        var indent: CGFloat = 0
        var attachment: EditorAttachment?
    }

    private func apply(_ look: LineLook, to range: NSRange, in storage: NSTextStorage, room: (EditorAttachment) -> CGFloat) {
        guard range.length > 0 else { return }
        if look.hidden { storage.addAttributes(Self.hidden, range: range) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = look.hidden ? 0 : 3
        if look.hidden { paragraph.maximumLineHeight = 0.5 }
        paragraph.firstLineHeadIndent = look.firstIndent
        paragraph.headIndent = look.indent
        if let attachment = look.attachment {
            let height = room(attachment)
            paragraph.paragraphSpacing = height > 0 ? height + 10 : 0
            // Marked on its last character, where what is drawn under it goes.
            storage.addAttribute(.weftAttachment, value: AttachmentMark(attachment), range: NSRange(location: NSMaxRange(range) - 1, length: 1))
        }
        storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
    }

    /// Text hidden: there, for the caret to go through and the file to
    /// keep, but taking no room.
    static let hidden: [NSAttributedString.Key: Any] = [.font: PlatformFont.systemFont(ofSize: 0.1), .foregroundColor: PlatformColor.clear]

    /// How many fence lines a text has: when an edit changes it, what is
    /// inside a block and what is not may have changed below it too.
    static func fences(in text: NSString) -> Int {
        var count = 0
        var at = 0
        while at < text.length {
            let found = text.range(of: "```", options: .literal, range: NSRange(location: at, length: text.length - at))
            guard found.location != NSNotFound else { break }
            if found.location == 0 || text.character(at: found.location - 1) == 10 { count += 1 }
            at = found.location + 3
            // The rest of a fence's backticks are not another.
            while at < text.length, text.character(at: at) == 96 { at += 1 }
        }
        return count
    }

    /// The paragraphs a selection touches — the whole of a query block, when
    /// it is in one: what shows its markup while the caret is there.
    static func revealed(for selection: NSRange, in text: NSString) -> NSRange {
        let clamped = NSRange(location: min(selection.location, text.length), length: min(selection.length, text.length - min(selection.location, text.length)))
        var range = text.paragraphRange(for: clamped)
        var start: Int?
        // The query blocks, found by their fences, that the range touches.
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byParagraphs]) { line, _, enclosing, _ in
            guard let line, line.hasPrefix("```") else { return }
            if let opened = start {
                let block = NSRange(location: opened, length: NSMaxRange(enclosing) - opened)
                if NSIntersectionRange(block, range).length > 0 || NSLocationInRange(range.location, block) { range = NSUnionRange(range, block) }
                start = nil
            } else if line.dropFirst(3).trimmingCharacters(in: .whitespaces) == "query" {
                start = enclosing.location
            }
        }
        return range
    }

    private var base: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return [.font: PlatformFont.systemFont(ofSize: size), .foregroundColor: Palette.text, .paragraphStyle: paragraph]
    }

    private var mono: PlatformFont { PlatformFont.monospacedSystemFont(ofSize: size * 0.92, weight: .regular) }

    private func styleLine(_ line: String, range: NSRange, shown: Bool, in storage: NSTextStorage) -> LineLook {
        let nsLine = line as NSString
        func sub(_ local: NSRange) -> NSRange { NSRange(location: range.location + local.location, length: local.length) }
        var look = LineLook()
        /// Markup: faint on the caret's lines, hidden on the rest — once
        /// the line is otherwise styled.
        var concealed: [NSRange] = []
        func markup(_ local: NSRange) {
            guard local.length > 0 else { return }
            if shown {
                storage.addAttribute(.foregroundColor, value: Palette.faint, range: sub(local))
            } else {
                concealed.append(local)
            }
        }
        // A heading: larger, its hashes markup.
        let hashes = line.prefix { $0 == "#" }.count
        if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
            let scale: CGFloat = [1.45, 1.25, 1.12, 1.05, 1, 1][hashes - 1]
            storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: size * scale, weight: .semibold), range: range)
            markup(NSRange(location: 0, length: hashes + 1))
        }
        // A quote: its marker markup, its words set in and quieter, a bar
        // down their left, as the outline draws one.
        if let match = Self.matches(#"^>\s?"#, in: line).first {
            markup(match.range)
            if !shown {
                look.firstIndent = 14
                look.indent = 14
                storage.addAttributes([.foregroundColor: Palette.dim, .weftQuote: true], range: range)
            }
        }
        // A callout's kind: faint, always — it is what the quote is.
        for match in Self.matches(#"^>\s?(\[![A-Za-z]+\])"#, in: line) {
            storage.addAttribute(.foregroundColor, value: Palette.faint, range: sub(match.range(at: 1)))
        }
        // A list's item: set in by its depth — the spaces that say so taking
        // no room — its lines hanging after its bullet, which is faint, and
        // drawn as a bullet off the caret's line. What it says is after it.
        var content = line
        if let match = Self.matches(#"^([ \t]*)([-*+]|\d+[.)])\s(?:\[[ xX]\]\s)?"#, in: line).first {
            let lead = match.range(at: 1)
            let depth = CGFloat(nsLine.substring(with: lead).reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2)
            if lead.length > 0 { storage.addAttributes(Self.hidden, range: sub(lead)) }
            let marker = NSRange(location: lead.upperBound, length: match.range.upperBound - lead.upperBound)
            storage.addAttribute(.foregroundColor, value: Palette.faint, range: sub(marker))
            let bullet = match.range(at: 2)
            if !shown, bullet.length == 1, "-*+".contains(nsLine.substring(with: bullet)) {
                storage.addAttribute(.weftBullet, value: true, range: sub(bullet))
            }
            let width = (nsLine.substring(with: marker) as NSString).size(withAttributes: [.font: PlatformFont.systemFont(ofSize: size)]).width
            look.firstIndent = depth * 20
            look.indent = depth * 20 + ceil(width)
            content = nsLine.substring(from: match.range.upperBound)
            // A list item that is a heading, as an outline's row can be: `- ## …`.
            let inner = content.prefix { $0 == "#" }.count
            if hashes == 0, (1...6).contains(inner), content.dropFirst(inner).first == " " {
                let scale: CGFloat = [1.45, 1.25, 1.12, 1.05, 1, 1][inner - 1]
                let start = match.range.upperBound
                storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: size * scale, weight: .semibold),
                                     range: sub(NSRange(location: start, length: nsLine.length - start)))
                markup(NSRange(location: start, length: inner + 1))
            }
        }
        for match in Self.matches(#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#, in: line) {
            storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: size, weight: .semibold), range: sub(match.range(at: 1)))
            markers(match.range, inner: match.range(at: 1), markup)
        }
        for match in Self.matches(#"(?<![*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?!\*)"#, in: line) {
            storage.addAttribute(.font, value: Fonts.italic(size: size), range: sub(match.range(at: 1)))
            markers(match.range, inner: match.range(at: 1), markup)
        }
        for match in Self.matches(#"(?<![_\w])__(?=\S)(.+?)(?<=\S)__(?![_\w])"#, in: line) {
            storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: size, weight: .semibold), range: sub(match.range(at: 1)))
            markers(match.range, inner: match.range(at: 1), markup)
        }
        for match in Self.matches(#"(?<![_\w])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![_\w])"#, in: line) {
            storage.addAttribute(.font, value: Fonts.italic(size: size), range: sub(match.range(at: 1)))
            markers(match.range, inner: match.range(at: 1), markup)
        }
        for match in Self.matches(#"~~(?=\S)(.+?)(?<=\S)~~"#, in: line) {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: sub(match.range(at: 1)))
            markers(match.range, inner: match.range(at: 1), markup)
        }
        // A character escaped: its backslash is markup.
        for match in Self.matches(#"\\[\\`*_{}\[\]()#+\-.!~|<>]"#, in: line) {
            markup(NSRange(location: match.range.location, length: 1))
        }
        for match in Self.matches(#"`([^`]+)`"#, in: line) {
            storage.addAttributes([.font: mono, .backgroundColor: Palette.codeBackground], range: sub(match.range(at: 1)))
            markers(match.range, inner: match.range(at: 1), markup)
        }
        // Links and tags: pills, as the outline editor draws them — off the
        // caret's lines, an icon of what each is to in the room of its
        // hidden markup, a web address shortened. In a heading, only coloured.
        func link(_ span: InlineSpan, pills: Bool) {
            let content = span.content
            var opening = span.markup.first { $0.location < content.location } ?? NSRange(location: content.location, length: 0)
            var bang = false
            let closing = span.markup.first { $0.location >= NSMaxRange(content) }
            var kind = LinkPill.Kind.web
            var missing = false
            let target = LinkPill.target(of: span)
            let page = target.flatMap(InlineMarkdown.title(from:))
            switch span.kind {
            case .tag:
                kind = .tag
            case .wikiLink:
                // An embed's `!` is markup too.
                if opening.location > 0, nsLine.character(at: opening.location - 1) == 33 {
                    opening = NSRange(location: opening.location - 1, length: opening.length + 1)
                    bang = true
                }
                if let page, page != nsLine.substring(with: content) { storage.addAttribute(.toolTip, value: page, range: sub(content)) }
            default:
                break
            }
            if let page, kind != .tag {
                kind = Day(page) != nil || Week(page) != nil ? .day : .page
                missing = !exists(page)
            }
            let tint = missing ? Palette.dim : Palette.accent
            storage.addAttribute(.foregroundColor, value: tint, range: sub(content))
            if missing { storage.addAttribute(.font, value: Fonts.italic(size: size), range: sub(content)) }
            // A tag is to its tiddler.
            let to = kind == .tag ? InlineMarkdown.url(for: String(nsLine.substring(with: content).dropFirst())) : target
            for run in span.markup { markup(run) }
            if bang { markup(NSRange(location: opening.location, length: 1)) }
            guard pills else {
                if let to { storage.addAttribute(.weftLink, value: to, range: sub(content)) }
                return
            }
            // Off the caret's lines: the room before its words is its icon's.
            var lead = !shown && opening.length > 0 ? NSMaxRange(opening) - 1 : nil
            var tail = !shown ? closing.map { NSMaxRange($0) - 1 } : nil
            // A web address written out — bare, or `<…>` — is shortened to
            // where it goes, but for on the caret's lines.
            if !shown, kind == .web, case let address = nsLine.substring(with: content), address.lowercased().hasPrefix("http"),
               span.kind == .url(address) || span.kind == .link(address) {
                let parts = AddressShortening.shortened(address)
                if parts.prefix > 0 {
                    func hide(_ local: NSRange) {
                        guard local.length > 0 else { return }
                        storage.addAttributes(Self.hidden, range: sub(NSRange(location: content.location + local.location, length: local.length)))
                    }
                    hide(NSRange(location: 0, length: parts.prefix))
                    lead = content.location + parts.prefix - 1
                    if let middle = parts.middle {
                        hide(middle)
                        let first = sub(NSRange(location: content.location + middle.location, length: 1))
                        storage.addAttributes([.weftEllipsis: true, .kern: LinkPill.ellipsisWidth(for: PlatformFont.systemFont(ofSize: size))], range: first)
                    }
                    if let rest = parts.rest {
                        hide(rest)
                        if tail == nil { tail = content.location + NSMaxRange(rest) - 1 }
                    }
                }
            }
            let pill = LinkPill(kind, hasLead: lead != nil, missing: missing)
            storage.addAttribute(.weftPill, value: pill, range: sub(span.range))
            if let lead, pill.hasLead {
                storage.addAttribute(.kern, value: pill.leadWidth(for: PlatformFont.systemFont(ofSize: size)), range: sub(NSRange(location: lead, length: 1)))
            }
            if let tail, pill.hasLead {
                // What the hidden markup after its words takes — a long
                // address, however small — counts toward the room after them.
                let after = NSRange(location: NSMaxRange(content), length: tail + 1 - NSMaxRange(content))
                let taken = (nsLine.substring(with: after) as NSString).size(withAttributes: [.font: Self.hidden[.font]!]).width
                storage.addAttribute(.kern, value: max(0.5, LinkPill.tailWidth - taken), range: sub(NSRange(location: tail, length: 1)))
            }
            // Followed when clicked: its words, and off the caret's lines its room too.
            if let to { storage.addAttribute(.weftLink, value: to, range: sub(shown ? content : span.range)) }
        }
        for span in InlineMarkup.spans(in: nsLine, range: NSRange(location: 0, length: nsLine.length)) {
            switch span.kind {
            case .link, .wikiLink, .url, .tag: link(span, pills: hashes == 0)
            // Pictures and comments, as Prism reads them: markup, the
            // pictures drawn under the line.
            case .image, .comment: markup(span.range)
            default: break
            }
        }
        let pieces = MarkdownCache.pieces(content)
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        if let card = pieces.card {
            // A link alone in its line: its card, in its place.
            look.attachment = .card(card.source, card.text)
            look.hidden = !shown
        } else if !pieces.pictures.isEmpty {
            look.attachment = .pictures(pieces.pictures)
            look.hidden = !shown && pieces.words.isEmpty
        } else if trimmed.hasPrefix("![["), trimmed.hasSuffix("]]"), !trimmed.dropFirst(3).dropLast(2).contains("]") {
            // A tiddler embedded alone in its line: drawn there, live.
            look.attachment = .block(trimmed)
            look.hidden = !shown
        }
        if look.hidden {
            // Nothing of a hidden line is drawn: its links' pills neither.
            for key in [NSAttributedString.Key.weftPill, .weftEllipsis, .kern] { storage.removeAttribute(key, range: range) }
        } else {
            for local in concealed { storage.addAttributes(Self.hidden, range: sub(local)) }
        }
        return look
    }

    /// The markup either side of what it marks.
    private func markers(_ whole: NSRange, inner: NSRange, _ markup: (NSRange) -> Void) {
        markup(NSRange(location: whole.location, length: inner.location - whole.location))
        markup(NSRange(location: inner.upperBound, length: whole.upperBound - inner.upperBound))
    }

    private static var cache: [String: NSRegularExpression] = [:]

    static func matches(_ pattern: String, in line: String) -> [NSTextCheckingResult] {
        let regex: NSRegularExpression
        if let cached = cache[pattern] {
            regex = cached
        } else {
            regex = try! NSRegularExpression(pattern: pattern)
            cache[pattern] = regex
        }
        return regex.matches(in: line, range: NSRange(location: 0, length: (line as NSString).length))
    }
}

#if os(iOS)
extension NSAttributedString.Key {
    /// Unused on the phone; there is nothing to rest a pointer on.
    static let toolTip = NSAttributedString.Key("WeftToolTip")
}
#endif

enum Palette {
    static var text: PlatformColor { Ink.text.platform }
    static var dim: PlatformColor { Ink.secondary.platform }
    static var faint: PlatformColor { Ink.faint.platform }
    static var accent: PlatformColor { Ink.accent.platform }
    static var codeBackground: PlatformColor { Ink(light: 0x2b2724, dark: 0xece6dc, alpha: 0.06).platform }
}

enum Fonts {
    static func italic(size: CGFloat) -> PlatformFont {
        let font = PlatformFont.systemFont(ofSize: size)
        #if os(macOS)
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        #else
        return font.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: size) } ?? font
        #endif
    }
}
