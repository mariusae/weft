import SwiftUI
import WeftCore

/// Over a query river's cards: what it finds, said in words, a tap away
/// from its settings.
struct QueryRiverHeader: View {
    @Environment(River.self) private var river

    var body: some View {
        Button { river.queryEditor = .edit } label: {
            HStack(spacing: 10) {
                Image(systemName: river.icon ?? "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RiverColor.color(river.color), in: Circle())
                Text(river.query?.summary ?? "")
                    .font(.callout)
                    .foregroundStyle(Ink.secondary.color)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("Edit")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Ink.accent.color)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Ink.paper.color, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Edit what the river finds, and how it orders it")
    }
}
