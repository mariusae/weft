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
/// it — the web, a page, a day. A web address is shortened to where it goes
/// — its site, and the first and last parts of its path — and shown whole
/// on the caret's lines. Tags are pills too, with no kind.
///
/// Nothing is written differently: the Markdown is the Markdown. The icon
/// takes the room of the hidden markup before the link's words, kerned
/// wide enough for it.
final class LinkPill: NSObject {
    enum Kind { case web, page, day, tag }
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
    /// Over a link's words: what it is to, followed when it is clicked.
    static let weftLink = NSAttributedString.Key("WeftLink")
}

/// Draws a card's links as pills, under its words.
final class LiveLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        drawPills(in: characters, origin: origin)
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
        }
    }
}

/// Drawing, the Mac's way and the phone's.
private enum Graphics {
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
        #if os(macOS)
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium).applying(.init(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        let size = image.size
        image.draw(in: CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        #else
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let image = UIImage(systemName: name, withConfiguration: configuration)?.withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        let size = image.size
        image.draw(in: CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height))
        #endif
    }
}

extension PlatformTextView {
    /// The link under a point in the view, when the point is on it: its
    /// words, or the room made for its icon.
    func link(at point: CGPoint) -> URL? {
        guard let layout = layoutManagerForAttachments, let container = textContainerForAttachments,
              let storage = layout.textStorage, storage.length > 0 else { return nil }
        let inContainer = CGPoint(x: point.x - textOrigin.x, y: point.y - textOrigin.y)
        let glyph = layout.glyphIndex(for: inContainer, in: container)
        guard glyph < layout.numberOfGlyphs else { return nil }
        // Only on the glyph itself, not in the space beyond a line's end.
        let bounds = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard bounds.insetBy(dx: -2, dy: -3).contains(inContainer) else { return nil }
        let character = layout.characterIndexForGlyph(at: glyph)
        guard character < storage.length else { return nil }
        return storage.attribute(.weftLink, at: character, effectiveRange: nil) as? URL
    }
}

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
