import ReflectCore
import SwiftUI
import WeftCore

/// Under a card, after what it is related to: the saved rivers it is a
/// card of — but the one it shows in — each a pill bringing that river
/// back, as a link to it does.
struct InRiversRow: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    let title: String

    var body: some View {
        let rivers = store.rivers(holding: title).filter { $0 != river.name }
        if !rivers.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("In Rivers")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundStyle(Ink.secondary.color)
                FlowLayout(spacing: 6) {
                    ForEach(rivers, id: \.self) { name in
                        Button { river.follow(river: name) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: RiverLink.symbol)
                                    .font(.caption2.weight(.semibold))
                                Text(name).lineLimit(1)
                            }
                            .font(.callout)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .foregroundStyle(Ink.text.color)
                            .background(Ink.rule.color.opacity(0.9), in: Capsule())
                            .overlay(Capsule().strokeBorder(Ink.rule.color))
                        }
                        .buttonStyle(.plain)
                        .help("Bring back the river “\(name)”")
                        .contextMenu {
                            Button("Copy Link to River", systemImage: "link") { Platform.copy(RiverLink.link(name)) }
                            Button("Copy River Address", systemImage: "safari") { Platform.copy(RiverLink.url(name).absoluteString) }
                        }
                    }
                }
            }
        }
    }
}
