import SwiftUI

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
extension View {
    /// A ring, an icon, in a card's gutter: centred where an outline's
    /// bullets are, a little before the words — into the card's side if
    /// it must — the gutter's width kept.
    func gutterMark() -> some View {
        frame(width: 28)
            .offset(x: Measures.gutter - 28)
            .frame(width: Measures.gutter, alignment: .leading)
    }
}
#endif
