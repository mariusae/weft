import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Markdown styled as it is typed: headings large, emphasis emphatic, code
/// in a fixed face, the markup itself faded — and a `[[link]]` a token, its
/// brackets faint, a link to no tiddler drawn as missing.
struct MarkdownStyler {
    var size: CGFloat
    /// Whether a tiddler has a title, to draw links to it.
    var exists: (String) -> Bool

    #if os(macOS)
    static let defaultSize: CGFloat = 14
    #else
    static let defaultSize: CGFloat = 17
    #endif

    func style(_ storage: NSTextStorage) {
        let text = storage.string as NSString
        let whole = NSRange(location: 0, length: text.length)
        storage.beginEditing()
        storage.setAttributes(base, range: whole)
        var fence: String?
        text.enumerateSubstrings(in: whole, options: [.byParagraphs]) { line, range, _, _ in
            guard let line else { return }
            if let current = fence {
                storage.addAttributes([.font: mono, .foregroundColor: current == "query" ? Palette.accent : Palette.text], range: range)
                if line.hasPrefix("```") { fence = nil; storage.addAttribute(.foregroundColor, value: Palette.faint, range: range) }
                return
            }
            if line.hasPrefix("```") {
                fence = line.drop { $0 == "`" }.trimmingCharacters(in: .whitespaces)
                storage.addAttributes([.font: mono, .foregroundColor: Palette.faint], range: range)
                return
            }
            styleLine(line, range: range, in: storage)
        }
        storage.endEditing()
    }

    private var base: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return [.font: PlatformFont.systemFont(ofSize: size), .foregroundColor: Palette.text, .paragraphStyle: paragraph]
    }

    private var mono: PlatformFont { PlatformFont.monospacedSystemFont(ofSize: size * 0.92, weight: .regular) }

    private func styleLine(_ line: String, range: NSRange, in storage: NSTextStorage) {
        let nsLine = line as NSString
        func sub(_ local: NSRange) -> NSRange { NSRange(location: range.location + local.location, length: local.length) }
        // A heading: larger, its hashes faint.
        let hashes = line.prefix { $0 == "#" }.count
        if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
            let scale: CGFloat = [1.45, 1.25, 1.12, 1.05, 1, 1][hashes - 1]
            storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: size * scale, weight: .semibold), range: range)
            storage.addAttribute(.foregroundColor, value: Palette.faint, range: sub(NSRange(location: 0, length: hashes + 1)))
        }
        // A quote or callout's marker, a list's bullet or number.
        for pattern in [#"^>\s?(\[![A-Za-z]+\])?"#, #"^\s*(?:[-*+]|\d+[.)])\s(?:\[[ xX]\]\s)?"#] {
            for match in Self.matches(pattern, in: line) {
                storage.addAttribute(.foregroundColor, value: Palette.faint, range: sub(match.range))
            }
        }
        for match in Self.matches(#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#, in: line) {
            storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: size, weight: .semibold), range: sub(match.range(at: 1)))
            fade(markers: match.range, inner: match.range(at: 1), in: storage, offset: range.location)
        }
        for match in Self.matches(#"(?<![*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?!\*)"#, in: line) {
            storage.addAttribute(.font, value: Fonts.italic(size: size), range: sub(match.range(at: 1)))
            fade(markers: match.range, inner: match.range(at: 1), in: storage, offset: range.location)
        }
        for match in Self.matches(#"`[^`]+`"#, in: line) {
            storage.addAttributes([.font: mono, .backgroundColor: Palette.codeBackground], range: sub(match.range))
        }
        for match in Self.matches(#"\[([^\[\]]+)\]\(([^)\s]+)\)"#, in: line) {
            storage.addAttribute(.foregroundColor, value: Palette.accent, range: sub(match.range(at: 1)))
            storage.addAttribute(.foregroundColor, value: Palette.faint, range: sub(NSRange(location: match.range(at: 1).upperBound,
                                                                                           length: match.range.upperBound - match.range(at: 1).upperBound)))
        }
        // `[[Title]]`, `[[Title|shown]]`, `![[Embed]]`: tokens.
        for match in Self.matches(#"(!?)\[\[([^\[\]|]+)(?:\|([^\[\]]+))?\]\]"#, in: line) {
            let title = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            let found = exists(title)
            let shown = match.range(at: 3).location != NSNotFound ? match.range(at: 3) : match.range(at: 2)
            storage.addAttribute(.foregroundColor, value: Palette.faint, range: sub(match.range))
            storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: size * 0.8), range: sub(match.range))
            var token: [NSAttributedString.Key: Any] = [
                .foregroundColor: found ? Palette.accent : Palette.dim,
                .backgroundColor: (found ? Palette.accent : Palette.dim).withAlphaComponent(match.range(at: 1).length > 0 ? 0.16 : 0.10),
                .font: found ? PlatformFont.systemFont(ofSize: size, weight: .medium) : Fonts.italic(size: size),
            ]
            if match.range(at: 3).location != NSNotFound {
                // The target, before the bar, is faint like the brackets.
                storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: size * 0.8), range: sub(match.range(at: 2)))
                token[.toolTip] = title
            }
            storage.addAttributes(token, range: sub(shown))
        }
    }

    private func fade(markers whole: NSRange, inner: NSRange, in storage: NSTextStorage, offset: Int) {
        let before = NSRange(location: offset + whole.location, length: inner.location - whole.location)
        let after = NSRange(location: offset + inner.upperBound, length: whole.upperBound - inner.upperBound)
        storage.addAttribute(.foregroundColor, value: Palette.faint, range: before)
        storage.addAttribute(.foregroundColor, value: Palette.faint, range: after)
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
