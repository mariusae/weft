import SwiftUI
#if os(macOS)
import AppKit
import ReflectUI
#endif

/// The river's measures, in one place: spacing on one scale, two corners,
/// and the sizes a card's title and ring take from the text's — so cards,
/// their parts and what is round them line up and keep the same rhythm.
/// The Mac's are compact; the phone keeps the room a finger wants.
enum Measures {
    // MARK: Spacing, on one scale

    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20

    // MARK: Corners

    /// A card's, the query's bar's, a panel's.
    #if os(macOS)
    static let cardRadius: CGFloat = 12
    #else
    static let cardRadius: CGFloat = 14
    #endif
    /// A control's, a chip's square, a tip's.
    static let controlRadius: CGFloat = 6

    // MARK: A card

    #if os(macOS)
    /// Round what a card says: its sides, its top and its foot.
    static let cardSides: CGFloat = xl
    static let cardTop: CGFloat = m + 2
    static let cardBottom: CGFloat = m + 2
    /// Between its parts — title, words, what links to it.
    static let cardParts: CGFloat = s
    /// A card folded to its peek: above and below its one line.
    static let peekPadding: CGFloat = s + 1

    /// The column before a card's words: a ring, an icon, an outline's
    /// bullets go in it — title, words and what is under them all begin
    /// after it, at the one edge.
    static var gutter: CGFloat { OutlineCardEditor.textIndent }
    /// A mark's size — a ring, an icon — as the outline draws its checkboxes.
    static var markSize: CGFloat { OutlineCardEditor.markSize }
    /// A mark's colour, open: as the outline draws its checkboxes.
    @MainActor static var markColor: Color { Color(nsColor: PageOutlineEditor.markColor) }
    /// The column before the gutter, in a card's side: its fold, a row's
    /// handle — room for them clear of the card's edge.
    static var margin: CGFloat { cardSides + xs }
    /// The middle of a text editor's first line, down from its top.
    static var textFirstLine: CGFloat {
        let font = NSFont.systemFont(ofSize: TextSettings.size)
        return 2 + font.ascender - font.capHeight / 2
    }

    /// Between cards in a river, open and peeking.
    static let cardGap: CGFloat = m
    static let peekGap: CGFloat = 6
    /// Round the river.
    static let riverSides: CGFloat = xl
    static let riverEnds: CGFloat = l

    /// A card's title, and a thing-to-do's ring: from the text's size.
    static var titleSize: CGFloat { (TextSettings.size * 1.35).rounded() }
    static var ringSize: CGFloat { (TextSettings.size * 1.3).rounded() }
    #else
    static var titleSize: CGFloat { 22 }
    static var ringSize: CGFloat { 21 }
    #endif
}


#if os(macOS)
// MARK: A card's rows

extension VerticalAlignment {
    private enum CardFirstLine: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
    }

    /// The middle of a card row's first line: what stands beside it — its
    /// fold, its mark, its controls — centred on it. An editor says where
    /// its own first line is; anything else, its middle.
    static let cardFirstLine = VerticalAlignment(CardFirstLine.self)
}

/// Every line of a card, alike: its margin — the card's side, for its fold
/// or a row's handle — its gutter, for its mark, then what it says, and
/// what follows it. Each in its column, on the first line's middle: what
/// is beside what lines up because it is laid out so, not moved there.
struct CardRow<Margin: View, Mark: View, Content: View>: View {
    /// Whether it has a gutter of its own: not when what it holds draws its
    /// own there, as the outline does.
    var gutter = true
    @ViewBuilder var margin: () -> Margin
    @ViewBuilder var mark: () -> Mark
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .cardFirstLine, spacing: 0) {
            // Each column its width, whether anything is in it or not: an
            // empty one is kept by nothing as tall as nothing.
            ZStack {
                Color.clear.frame(width: Measures.margin, height: 0)
                margin()
            }
            .frame(width: Measures.margin)
            // Over what it says, which reaches into it — an outline's row
            // buttons — where it has something: a card's handle.
            .zIndex(1)
            if gutter {
                ZStack {
                    Color.clear.frame(width: Measures.gutter, height: 0)
                    mark()
                }
                .frame(width: Measures.gutter)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .leading) { if CardGrid.shown { CardGrid(gutter: gutter) } }
    }
}

extension CardRow where Margin == EmptyView {
    init(gutter: Bool = true, @ViewBuilder mark: @escaping () -> Mark, @ViewBuilder content: @escaping () -> Content) {
        self.init(gutter: gutter, margin: { EmptyView() }, mark: mark, content: content)
    }
}

extension CardRow where Margin == EmptyView, Mark == EmptyView {
    init(gutter: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.init(gutter: gutter, margin: { EmptyView() }, mark: { EmptyView() }, content: content)
    }
}

/// `WEFT_GRID=1`: each row's columns drawn over it — its margin's edge and
/// its gutter's — to see that what should line up does.
struct CardGrid: View {
    static let shown = ProcessInfo.processInfo.environment["WEFT_GRID"] != nil
    let gutter: Bool

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Measures.margin)
            Rectangle().fill(.red.opacity(0.5)).frame(width: 1)
            Color.clear.frame(width: Measures.gutter - 1)
            Rectangle().fill(.blue.opacity(0.5)).frame(width: 1)
        }
        .allowsHitTesting(false)
    }
}

/// What goes in a card's gutter: a thing to do's ring — round, as a page
/// is, not square as a checklist's row — or the page's icon; sized and
/// centred as the outline's checkboxes and bullets are.
struct GutterMark: View {
    enum Kind: Equatable {
        case ring(done: Bool)
        case icon(String)
    }
    let kind: Kind?
    var help: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            switch kind {
            case .ring(let done):
                Button { action?() } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: Measures.markSize))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(done ? Color.white : Measures.markColor, Ink.accent.color)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: Measures.gutter)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointing()
                .help(help ?? (done ? "Done — click to open again" : "To do — click when done"))
                .accessibilityLabel(done ? "Done" : "To do")
            case .icon(let symbol):
                Button { action?() } label: {
                    Image(systemName: symbol)
                        .font(.system(size: Measures.markSize * 0.9))
                        .foregroundStyle(Ink.secondary.color)
                        .frame(width: Measures.gutter)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointing()
                .disabled(action == nil)
                .help(help ?? "")
            case nil:
                Color.clear
            }
        }
        .frame(width: Measures.gutter)
    }
}
#endif
