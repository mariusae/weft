import Foundation
import SwiftUI
import WeftCore
import ReflectCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Links shown as the outline editor shows them, as Slack does: in the
/// accent colour, on a pale pill of it, with what kind of link it is before
/// it — the web, a page, a day, a saved river. A web address is shortened to where it goes
/// — its site, and the first and last parts of its path — and shown whole
/// on the caret's lines. Tags are pills too, with no kind.
///
/// Nothing is written differently: the Markdown is the Markdown. The icon
/// takes the room of the hidden markup before the link's words, kerned
/// wide enough for it.
final class LinkPill: NSObject {
    enum Kind { case web, page, day, river, tag }
    let kind: Kind
    /// Whether it has hidden markup before its words to put its icon in.
    let hasLead: Bool
    /// A link to no tiddler: quieter.
    let missing: Bool

    init(_ kind: Kind, hasLead: Bool, missing: Bool = false) {
        self.kind = kind
        self.hasLead = hasLead && kind != .tag
        self.missing = missing
    }

    var symbol: String? {
        guard hasLead else { return nil }
        switch kind {
        case .web: return "link"
        case .page: return "doc.text"
        case .day: return "calendar"
        case .river: return RiverLink.symbol
        case .tag: return nil
        }
    }

    var tint: PlatformColor { missing ? Palette.dim : Palette.accent }

    static func iconSide(for font: PlatformFont) -> CGFloat { (font.pointSize * 0.72).rounded() }

    /// The room before its words: the icon, and space either side of it.
    func leadWidth(for font: PlatformFont) -> CGFloat {
        symbol == nil ? 3 : 4 + Self.iconSide(for: font) + 3
    }

    static let tailWidth: CGFloat = 3
    static let ellipsis = "…"

    static func ellipsisWidth(for font: PlatformFont) -> CGFloat {
        ceil((ellipsis as NSString).size(withAttributes: [.font: font]).width)
    }

    /// What the link is to: a page, by its title, or an address.
    static func target(of span: InlineSpan) -> URL? {
        switch span.kind {
        case .wikiLink(let title):
            let name = title.replacingOccurrences(of: "\\", with: "").trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : InlineMarkdown.url(for: name)
        case .link(let address), .url(let address):
            // `[words](Title)`: a page, as Prism reads it, when it is no address.
            if address.contains(":") { return URL(string: address) }
            let name = address.removingPercentEncoding ?? address
            return name.isEmpty ? nil : InlineMarkdown.url(for: name)
        default:
            return nil
        }
    }
}

extension NSAttributedString.Key {
    /// Over a link or tag shown as a pill: its `LinkPill`.
    static let weftPill = NSAttributedString.Key("WeftPill")
    /// On the hidden character laid out as a shortened address's ellipsis.
    static let weftEllipsis = NSAttributedString.Key("WeftEllipsis")
    /// On the hidden character whose room shows a link's words instead of
    /// what it says: an untitled page's name, as the page begins.
    static let weftLabel = NSAttributedString.Key("WeftLabel")
    /// Over a link's words: what it is to, followed when it is clicked.
    static let weftLink = NSAttributedString.Key("WeftLink")
    /// Over a quote's line: a bar drawn down its left.
    static let weftQuote = NSAttributedString.Key("WeftQuote")
    /// Over a task's marker, `- [ ]` to its `]`: its `TaskBox`, drawn there.
    static let weftTask = NSAttributedString.Key("WeftTask")
}

/// A task's box, as the outline draws it: a ring for Reflect's `+`, else a
/// square — checked, done.
final class TaskBox: NSObject {
    let done: Bool
    let round: Bool
    /// The size of the words it is beside: its marker, hidden, has none.
    let size: CGFloat
    init(done: Bool, round: Bool, size: CGFloat) {
        self.done = done
        self.round = round
        self.size = size
    }
}

/// Draws a card's links as pills, under its words, its quotes' bars, and
/// its tasks' boxes.
final class LiveLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        drawQuoteBars(in: characters, origin: origin)
        drawPills(in: characters, origin: origin)
        drawTasks(in: characters, origin: origin)
    }

    /// Each task's box at the start of its marker, on the capitals of its line.
    private func drawTasks(in characters: NSRange, origin: CGPoint) {
        guard let storage = textStorage, characters.length > 0 else { return }
        storage.enumerateAttribute(.weftTask, in: characters) { value, range, _ in
            guard let task = value as? TaskBox else { return }
            let font = PlatformFont.systemFont(ofSize: task.size)
            let glyph = glyphIndexForCharacter(at: range.location)
            guard glyph < numberOfGlyphs else { return }
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let point = location(forGlyphAt: glyph)
            let middle = line.minY + point.y - font.capHeight / 2 + origin.y
            let side = (font.pointSize * 0.95).rounded()
            let name = task.round ? (task.done ? "checkmark.circle.fill" : "circle") : (task.done ? "checkmark.square.fill" : "square")
            // Checked: a white tick on the accent colour.
            Graphics.symbol(name, pointSize: side, colors: task.done ? [.white, Palette.accent] : [Palette.dim], weight: .regular,
                            centeredIn: CGRect(x: line.minX + point.x + origin.x, y: middle - side / 2, width: side, height: side))
        }
    }

    /// Each quote's line a bar down its left, from its first line to its
    /// last — the outline's, a line its row.
    private func drawQuoteBars(in characters: NSRange, origin: CGPoint) {
        guard let storage = textStorage, characters.length > 0 else { return }
        let text = storage.string as NSString
        var drawn = Set<Int>()
        storage.enumerateAttribute(.weftQuote, in: characters) { value, range, _ in
            guard value != nil else { return }
            var location = range.location
            while location < NSMaxRange(range) {
                let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
                location = NSMaxRange(paragraph)
                guard drawn.insert(paragraph.location).inserted else { continue }
                var words = paragraph
                while words.length > 1, text.character(at: NSMaxRange(words) - 1) == 10 { words.length -= 1 }
                let glyphs = glyphRange(forCharacterRange: words, actualCharacterRange: nil)
                guard glyphs.length > 0 else { continue }
                let top = lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                let bottom = lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
                let line = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                Graphics.fill([CGRect(x: line.minX + origin.x + 3, y: top.minY + origin.y + 2,
                                      width: 3, height: bottom.maxY - top.minY - 4)],
                              color: Palette.faint, radius: 1.5)
            }
        }
    }

    /// Whether a glyph is nothing to see: hidden markup with no room made
    /// for an icon, an ellipsis or the end of a pill.
    private func isNothing(_ glyph: Int) -> Bool {
        guard let storage = textStorage else { return false }
        let character = characterIndexForGlyph(at: glyph)
        guard character < storage.length else { return true }
        let hidden = ((storage.attribute(.font, at: character, effectiveRange: nil) as? PlatformFont)?.pointSize ?? 12) < 1
        return hidden && (storage.attribute(.kern, at: character, effectiveRange: nil) as? CGFloat ?? 0) == 0
    }

    /// The pieces of some glyphs on each line they run across: around what
    /// is shown, and the room made beside it, not the hidden markup at a
    /// line's ends.
    private func shownPieces(of glyphs: NSRange, in container: NSTextContainer) -> [CGRect] {
        var pieces: [CGRect] = []
        enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, lineGlyphs, _ in
            var piece = NSIntersectionRange(lineGlyphs, glyphs)
            while piece.length > 0, self.isNothing(piece.location) {
                piece = NSRange(location: piece.location + 1, length: piece.length - 1)
            }
            while piece.length > 0, self.isNothing(NSMaxRange(piece) - 1) {
                piece.length -= 1
            }
            guard piece.length > 0 else { return }
            let rect = self.boundingRect(forGlyphRange: piece, in: container)
            if rect.width > 0.5 { pieces.append(rect) }
        }
        return pieces
    }

    private func drawPills(in characters: NSRange, origin: CGPoint) {
        guard let storage = textStorage, let container = textContainers.first, characters.length > 0 else { return }
        storage.enumerateAttribute(.weftPill, in: characters) { value, range, _ in
            guard let pill = value as? LinkPill else { return }
            // The whole pill, though only part of it is being drawn.
            var whole = range
            _ = storage.attribute(.weftPill, at: range.location, longestEffectiveRange: &whole, in: NSRange(location: 0, length: storage.length))
            let glyphs = glyphRange(forCharacterRange: whole, actualCharacterRange: nil)
            let font = storage.attribute(.font, at: NSMaxRange(whole) - 1, effectiveRange: nil) as? PlatformFont
            let words = (0..<whole.length).lazy.map { whole.location + $0 }
                .compactMap { storage.attribute(.font, at: $0, effectiveRange: nil) as? PlatformFont }.first { $0.pointSize >= 1 }
            guard let font = words ?? font else { return }
            let ascent = ceil(font.ascender), descent = ceil(-font.descender)
            var pieces: [CGRect] = []
            for rect in shownPieces(of: glyphs, in: container) {
                let glyph = glyphIndex(for: CGPoint(x: rect.minX + 1, y: rect.midY), in: container)
                let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let baseline = line.minY + location(forGlyphAt: glyph).y
                // A pill with no room of its own reaches a little past its words.
                let pad: CGFloat = pill.hasLead ? 1 : 3
                pieces.append(CGRect(x: rect.minX + origin.x - pad, y: baseline - ascent - 2 + origin.y,
                                     width: rect.width + 2 * pad, height: ascent + descent + 4))
            }
            Graphics.fill(pieces, color: pill.tint.withAlphaComponent(pill.missing ? 0.10 : 0.12), radius: 5)
            if let first = pieces.first, let symbol = pill.symbol {
                let side = LinkPill.iconSide(for: font)
                Graphics.symbol(symbol, pointSize: side * 0.9, color: pill.tint,
                                centeredIn: CGRect(x: first.minX + 4, y: first.minY, width: side, height: first.height))
            }
            // A shortened address's ellipsis, in the room its hidden middle has.
            storage.enumerateAttribute(.weftEllipsis, in: whole) { value, at, _ in
                guard value != nil else { return }
                let glyph = glyphIndexForCharacter(at: at.location)
                let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let point = location(forGlyphAt: glyph)
                (LinkPill.ellipsis as NSString).draw(at: CGPoint(x: line.minX + point.x + origin.x, y: line.minY + point.y - ascent + origin.y),
                                                     withAttributes: [.font: font, .foregroundColor: pill.tint])
            }
            // An untitled page's name, in the room of the name it is linked by.
            storage.enumerateAttribute(.weftLabel, in: whole) { value, at, _ in
                guard let label = value as? String else { return }
                let glyph = glyphIndexForCharacter(at: at.location)
                let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let point = location(forGlyphAt: glyph)
                (label as NSString).draw(at: CGPoint(x: line.minX + point.x + origin.x, y: line.minY + point.y - ascent + origin.y),
                                         withAttributes: [.font: font, .foregroundColor: pill.tint])
            }
        }
    }
}

/// Drawing, the Mac's way and the phone's.
@MainActor
private enum Graphics {
    #if os(macOS)
    private static var symbols: [String: NSImage?] = [:]
    #else
    private static var symbols: [String: UIImage?] = [:]
    #endif

    /// A colour as it shows now.
    private static func colorKey(_ color: PlatformColor) -> String {
        #if os(macOS)
        guard let rgb = color.usingColorSpace(.sRGB) else { return color.description }
        return "\(rgb.redComponent) \(rgb.greenComponent) \(rgb.blueComponent) \(rgb.alphaComponent)"
        #else
        return (color.cgColor.components ?? []).map { "\($0)" }.joined(separator: " ")
        #endif
    }

    static func fill(_ rects: [CGRect], color: PlatformColor, radius: CGFloat) {
        color.setFill()
        for rect in rects {
            #if os(macOS)
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            #else
            UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
            #endif
        }
    }

    static func symbol(_ name: String, pointSize: CGFloat, color: PlatformColor, centeredIn box: CGRect) {
        symbol(name, pointSize: pointSize, colors: [color], weight: .medium, centeredIn: box)
    }

    static func symbol(_ name: String, pointSize: CGFloat, colors: [PlatformColor], weight: PlatformFont.Weight, centeredIn box: CGRect) {
        // Made once for each look — the colours as they are now, light or
        // dark — and kept: looked up for each one drawn, they took longer
        // than the drawing.
        let key = "\(name)|\(pointSize)|\(weight.rawValue)|" + colors.map(Self.colorKey).joined(separator: ",")
        #if os(macOS)
        let image = symbols[key] ?? {
            let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight).applying(.init(paletteColors: colors))
            let made = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
            symbols[key] = made
            return made
        }()
        guard let image else { return }
        let size = image.size
        image.draw(in: CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        #else
        let image = symbols[key] ?? {
            let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight.symbolWeight)
                .applying(UIImage.SymbolConfiguration(paletteColors: colors))
            let made = UIImage(systemName: name, withConfiguration: configuration)
            symbols[key] = made
            return made
        }()
        guard let image else { return }
        let size = image.size
        image.draw(in: CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height))
        #endif
    }
}

extension PlatformTextView {
    /// The link under a point in the view, when the point is on it: its
    /// words, or the room made for its icon.
    func link(at point: CGPoint) -> URL? {
        guard let (storage, character) = character(at: point) else { return nil }
        return storage.attribute(.weftLink, at: character, effectiveRange: nil) as? URL
    }

    /// The task whose box is under a point, when it can be checked: where
    /// its `[ ]` or `[x]` says which it is.
    func task(at point: CGPoint) -> NSRange? {
        guard isEditable, let (storage, character) = character(at: point) else { return nil }
        var box = NSRange()
        guard storage.attribute(.weftTask, at: character, longestEffectiveRange: &box,
                                in: NSRange(location: 0, length: storage.length)) is TaskBox else { return nil }
        return NSRange(location: NSMaxRange(box) - 2, length: 1)
    }

    /// Whether a click at a point would follow a link or check a task: what
    /// the pointer, moved, asks — one look at the text, not one for each.
    func isClickable(at point: CGPoint) -> Bool {
        guard let (storage, character) = character(at: point) else { return false }
        return storage.attribute(.weftLink, at: character, effectiveRange: nil) != nil
            || isEditable && storage.attribute(.weftTask, at: character, effectiveRange: nil) != nil
    }

    /// The character under a point in the view — on its glyph, not in the
    /// space beyond a line's end.
    private func character(at point: CGPoint) -> (NSTextStorage, Int)? {
        guard let layout = layoutManagerForAttachments, let container = textContainerForAttachments,
              let storage = layout.textStorage, storage.length > 0 else { return nil }
        let inContainer = CGPoint(x: point.x - textOrigin.x, y: point.y - textOrigin.y)
        let glyph = layout.glyphIndex(for: inContainer, in: container)
        guard glyph < layout.numberOfGlyphs else { return nil }
        let bounds = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard bounds.insetBy(dx: -2, dy: -3).contains(inContainer) else { return nil }
        let character = layout.characterIndexForGlyph(at: glyph)
        guard character < storage.length else { return nil }
        return (storage, character)
    }
}

#if os(iOS)
private extension UIFont.Weight {
    var symbolWeight: UIImage.SymbolWeight { self == .medium ? .medium : .regular }
}
#endif

/// Following a link from a card: a page opened in the river after it, an
/// address in the browser.
@MainActor
func follow(_ url: URL, in river: River, from card: String) {
    if let title = InlineMarkdown.title(from: url) {
        withAnimation(.snappy(duration: 0.28)) { river.open(title, from: card) }
    } else {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}
