import ReflectCore
import SwiftUI
import WeftCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What a line of the editor shows under it besides its words — drawn with
/// the views the cards always drew them with.
enum EditorAttachment: Hashable {
    /// The pictures in a line.
    case pictures([ImageReference])
    /// The card of a link alone in its line, and what the link says.
    case card(String, String?)
    /// A block of Markdown drawn whole: a query, a tiddler embedded.
    case block(String)
}

/// Marks the last character of a line with what is drawn under it.
final class AttachmentMark: NSObject {
    let attachment: EditorAttachment
    init(_ attachment: EditorAttachment) { self.attachment = attachment }
}

extension NSAttributedString.Key {
    static let weftAttachment = NSAttributedString.Key("WeftAttachment")
    /// A list's `-`, drawn as a bullet.
    static let weftBullet = NSAttributedString.Key("WeftBullet")
}

/// Draws a list's `-` as the bullet it stands for — the text itself as written.
final class LiveGlyphs: NSObject, NSLayoutManagerDelegate {
    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>, font: PlatformFont,
                       forGlyphRange range: NSRange) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        let bullets = (0..<range.length).filter {
            storage.attribute(.weftBullet, at: characterIndexes[$0], effectiveRange: nil) != nil
        }
        guard !bullets.isEmpty else { return 0 }
        var character: [UniChar] = [0x2022]
        var bullet: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font as CTFont, &character, &bullet, 1), bullet != 0 else { return 0 }
        var list = [CGGlyph](UnsafeBufferPointer(start: glyphs, count: range.length))
        for index in bullets { list[index] = bullet }
        layoutManager.setGlyphs(list, properties: properties, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
        return range.length
    }
}

private struct AttachmentContent: View {
    let attachment: EditorAttachment
    let card: String

    var body: some View {
        switch attachment {
        case .pictures(let pictures):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(pictures.enumerated()), id: \.offset) { _, picture in
                    PictureView(reference: picture)
                }
            }
        case .card(let source, let text):
            LinkCardView(source: source, text: text)
        case .block(let source):
            MarkdownView(blocks: MarkdownCache.blocks(source), card: card, editable: false)
        }
    }
}

/// What is drawn under one line: as wide as the text, as tall as it needs,
/// telling how tall that is — the line keeps that much room under it.
private struct AttachmentRoot: View {
    let attachment: EditorAttachment
    let card: String
    let width: CGFloat
    let store: WikiStore
    let river: River
    let report: (CGFloat) -> Void

    var body: some View {
        AttachmentContent(attachment: attachment, card: card)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { report(ceil($0)) }
            .environment(store)
            .environment(river)
            .environment(\.openURL, OpenURLAction { [river, card] url in
                if let target = InlineMarkdown.title(from: url) {
                    river.open(target, from: card)
                    return .handled
                }
                return .systemAction
            })
    }
}

#if os(macOS)
private typealias Host = NSHostingView<AttachmentRoot>
#else
private typealias Host = UIHostingController<AttachmentRoot>
#endif

/// The views drawn under an editor's lines, kept by what they draw — so a
/// line restyled does not decode its picture again — and placed where the
/// layout put the room for them.
@MainActor
final class EditorAttachments {
    private weak var view: PlatformTextView?
    let store: WikiStore
    let river: River
    var card: String
    /// Told when what is drawn under a line turned out another height: the
    /// room under it is to be made again.
    var onHeightChange: (EditorAttachment) -> Void = { _ in }
    private var heights: [EditorAttachment: CGFloat] = [:]
    private var hosts: [String: (attachment: EditorAttachment, host: Host, width: CGFloat)] = [:]
    /// The foot of the lowest, in the view.
    private(set) var bottom: CGFloat = 0

    init(view: PlatformTextView, store: WikiStore, river: River, card: String) {
        self.view = view
        self.store = store
        self.river = river
        self.card = card
    }

    /// How tall an attachment is, as last drawn: the room its line keeps.
    func room(for attachment: EditorAttachment) -> CGFloat { heights[attachment] ?? 0 }

    /// Puts each where its line's room is — making the ones new, letting go
    /// of the ones gone.
    func place() {
        guard let view, let layout = view.layoutManagerForAttachments, let container = view.textContainerForAttachments,
              let storage = layout.textStorage else { return }
        let origin = view.textOrigin
        let padding = container.lineFragmentPadding
        let width = max(40, container.size.width - padding * 2)
        var seen = Set<String>()
        var count: [EditorAttachment: Int] = [:]
        var lowest: CGFloat = 0
        layout.ensureLayout(for: container)
        storage.enumerateAttribute(.weftAttachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let mark = value as? AttachmentMark else { return }
            let attachment = mark.attachment
            let occurrence = count[attachment, default: 0]
            count[attachment] = occurrence + 1
            let key = "\(attachment.hashValue)#\(occurrence)"
            seen.insert(key)
            let glyph = layout.glyphIndexForCharacter(at: range.location)
            let line = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let height = heights[attachment] ?? 0
            // In with its line's words: a list item's, past its bullet or box.
            let indent = (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
            let width = max(40, width - indent)
            let frame = CGRect(x: origin.x + padding + indent, y: origin.y + line.maxY + 4, width: width, height: max(height, 1))
            let host = self.host(key, attachment, width: width)
            #if os(macOS)
            if host.frame != frame { host.frame = frame }
            #else
            if host.view.frame != frame { host.view.frame = frame }
            #endif
            lowest = max(lowest, frame.maxY - origin.y)
        }
        for (key, entry) in hosts where !seen.contains(key) {
            #if os(macOS)
            entry.host.removeFromSuperview()
            #else
            entry.host.view.removeFromSuperview()
            #endif
            hosts[key] = nil
        }
        bottom = lowest
    }

    private func host(_ key: String, _ attachment: EditorAttachment, width: CGFloat) -> Host {
        if let entry = hosts[key], entry.attachment == attachment {
            if abs(entry.width - width) > 0.5 {
                #if os(macOS)
                entry.host.rootView = root(attachment, width: width)
                #else
                entry.host.rootView = root(attachment, width: width)
                #endif
                hosts[key] = (attachment, entry.host, width)
            }
            return entry.host
        }
        if let old = hosts[key] {
            #if os(macOS)
            old.host.removeFromSuperview()
            #else
            old.host.view.removeFromSuperview()
            #endif
        }
        #if os(macOS)
        let host = NSHostingView(rootView: root(attachment, width: width))
        host.sizingOptions = []
        view?.addSubview(host)
        #else
        let host = UIHostingController(rootView: root(attachment, width: width))
        host.sizingOptions = []
        host.view.backgroundColor = .clear
        view?.addSubview(host.view)
        #endif
        hosts[key] = (attachment, host, width)
        return host
    }

    private func root(_ attachment: EditorAttachment, width: CGFloat) -> AttachmentRoot {
        AttachmentRoot(attachment: attachment, card: card, width: width, store: store, river: river) { [weak self] height in
            guard let self, abs((heights[attachment] ?? 0) - height) > 0.5 else { return }
            heights[attachment] = height
            onHeightChange(attachment)
        }
    }
}

#if os(macOS)
typealias PlatformTextView = NSTextView

extension NSTextView {
    var layoutManagerForAttachments: NSLayoutManager? { layoutManager }
    var textContainerForAttachments: NSTextContainer? { textContainer }
    var textOrigin: CGPoint { textContainerOrigin }
}
#else
typealias PlatformTextView = UITextView

extension UITextView {
    var layoutManagerForAttachments: NSLayoutManager? { layoutManager }
    var textContainerForAttachments: NSTextContainer? { textContainer }
    var textOrigin: CGPoint { CGPoint(x: textContainerInset.left, y: textContainerInset.top) }
}
#endif

/// The editor's text, live: styled as it reads, its markup showing on the
/// caret's lines only, what its lines show drawn under them. Shared by the
/// Mac's text view and the phone's.
@MainActor
final class LiveMarkdown {
    var styler: MarkdownStyler
    let attachments: EditorAttachments
    private weak var view: PlatformTextView?
    /// The paragraphs whose markup shows: the caret's, while it is in.
    private var revealed: NSRange?
    private(set) var focused = false
    /// Fence lines in the text as last styled.
    private var fences = -1
    /// Told when the height the text needs may have changed.
    var onResize: () -> Void = {}
    private let glyphs = LiveGlyphs()

    init(view: PlatformTextView, styler: MarkdownStyler, store: WikiStore, river: River, card: String) {
        self.view = view
        self.styler = styler
        view.layoutManagerForAttachments?.delegate = glyphs
        attachments = EditorAttachments(view: view, store: store, river: river, card: card)
        attachments.onHeightChange = { [weak self] attachment in self?.restyle(showing: attachment) }
    }

    private var storage: NSTextStorage? { view?.layoutManagerForAttachments?.textStorage }

    private func style(around range: NSRange?) {
        guard let storage else { return }
        styler.style(storage, around: range, revealed: revealed) { [attachments] in attachments.room(for: $0) }
    }

    /// The text changed, in `range`: those paragraphs styled again — every
    /// one, when a fence came or went.
    func edited(_ range: NSRange, in storage: NSTextStorage) {
        let text = storage.string as NSString
        let count = MarkdownStyler.fences(in: text)
        if focused { revealed = MarkdownStyler.revealed(for: NSRange(location: NSMaxRange(range), length: 0), in: text) }
        style(around: count == fences ? (revealed.map { NSUnionRange($0, range) } ?? range) : nil)
        fences = count
    }

    /// After a change has been laid out: what is under the lines put in place.
    func changed() {
        attachments.place()
        onResize()
    }

    func selectionChanged(_ selection: NSRange) {
        guard let storage else { return }
        let now = focused ? MarkdownStyler.revealed(for: selection, in: storage.string as NSString) : nil
        guard now != revealed else { return }
        let before = revealed
        revealed = now
        if let before { style(around: before) }
        if let now { style(around: now) }
        changed()
    }

    func focusChanged(_ focused: Bool, selection: NSRange) {
        self.focused = focused
        selectionChanged(selection)
    }

    /// Styles the whole text, as it is first shown or put back.
    func restyleAll() {
        guard let storage else { return }
        fences = MarkdownStyler.fences(in: storage.string as NSString)
        style(around: nil)
    }

    /// An attachment's height changed: the lines that show it keep new room.
    private func restyle(showing attachment: EditorAttachment) {
        guard let storage else { return }
        var lines: [NSRange] = []
        storage.enumerateAttribute(.weftAttachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if (value as? AttachmentMark)?.attachment == attachment { lines.append(range) }
        }
        for line in lines { style(around: line) }
        changed()
    }
}
