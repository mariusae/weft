import SwiftUI
import WeftCore

/// Over a query river's cards: what it finds, said in words, a tap away
/// from its settings.
struct QueryRiverHeader: View {
    @Environment(River.self) private var river

    #if os(macOS)
    private static let spacing: CGFloat = 0
    private static let mark: CGFloat = 20
    #else
    private static let spacing: CGFloat = 10
    private static let mark: CGFloat = 26
    #endif

    var body: some View {
        Button { river.queryEditor = .edit } label: {
            HStack(spacing: Self.spacing) {
                Image(systemName: river.icon ?? "line.3.horizontal.decrease.circle")
                    .font(.system(size: Self.mark / 2, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Self.mark, height: Self.mark)
                    .background(RiverColor.color(river.color), in: Circle())
                    #if os(macOS)
                    // In the gutter, as a card's ring: what it finds said where cards' words begin.
                    .frame(width: Measures.gutter)
                    #endif
                Text(river.query?.summary ?? "")
                    .font(.callout)
                    .foregroundStyle(Ink.secondary.color)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("Edit")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Ink.accent.color)
            }
            #if os(macOS)
            // A card's shape and sides, as the cards under it: its margin before.
            .padding(.leading, Measures.margin)
            .padding(.trailing, Measures.cardSides)
            .padding(.vertical, 7)
            .background(Ink.paper.color, in: RoundedRectangle(cornerRadius: Measures.cardRadius))
            .contentShape(RoundedRectangle(cornerRadius: Measures.cardRadius))
            #else
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Ink.paper.color, in: Capsule())
            .contentShape(Capsule())
            #endif
        }
        .buttonStyle(.plain)
        .pointing()
        .help("Edit what the river finds, and how it orders it")
    }
}
