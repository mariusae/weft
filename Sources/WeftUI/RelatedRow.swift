import SwiftUI
import WeftCore

/// A card's related pages — frontmatter `related:`, Prism's and Weft's
/// alike — as pills under a heading: those it names, and those naming it.
/// A pill opens its card after this one; its menu unrelates it; + relates
/// another, the titles that fit what is typed offered.
struct RelatedRow: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    let title: String
    /// Asked for from the card's menu, or the row's +.
    @Binding var adding: Bool
    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        let related = store.related(of: title)
        if !related.isEmpty || adding {
            VStack(alignment: .leading, spacing: 6) {
                FootRow("Related") {
                    ForEach(related, id: \.title) { page in
                        Button { river.open(page.title, from: title) } label: { RelatedPill(page: page, shown: store.shownTitle(page.title)) }
                            .buttonStyle(.plain)
                            .help(page.isOwn ? "Related here" : "“\(store.shownTitle(page.title))” relates itself to this")
                            .contextMenu {
                                Button("Unrelate", systemImage: "minus.circle") { store.unrelate(title, from: page.title) }
                            }
                    }
                    if adding {
                        TextField("Relate to…", text: $typed)
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .frame(width: 180)
                            .padding(.vertical, 3)
                            .focused($focused)
                            .onSubmit { relate(suggestions(excluding: related).first?.title ?? typed) }
                            // Once it is on screen: on the phone, asked at once, the keys don't come.
                            .task {
                                try? await Task.sleep(for: .milliseconds(150))
                                focused = true
                            }
                            .onChange(of: focused) { if !focused && typed.isEmpty { adding = false } }
                            #if os(macOS)
                            .onExitCommand { typed = ""; adding = false }
                            #endif
                    } else {
                        Button { adding = true } label: {
                            Image(systemName: "plus")
                                .font(.caption.weight(.bold))
                                .frame(width: 24, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Ink.faint.color)
                        .help("Relate to Another Page")
                    }
                }
                let offered = suggestions(excluding: related)
                if !offered.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(offered, id: \.title) { target in
                            Button { relate(target.title) } label: {
                                Label(target.shown, systemImage: target.symbol)
                                    .font(.caption)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .overlay(Capsule().strokeBorder(Ink.accent.color.opacity(0.4)))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Ink.accent.color)
                        }
                    }
                }
            }
        }
    }

    /// Pages by what is typed, not this one or those related already.
    private func suggestions(excluding related: [WikiStore.RelatedPage]) -> [LinkTarget] {
        let query = typed.trimmingCharacters(in: .whitespaces)
        guard adding, !query.isEmpty else { return [] }
        let taken = Set(related.map { $0.title.lowercased() } + [title.lowercased()])
        return Array(store.linkSuggestions(query).filter { !taken.contains($0.title.lowercased()) }.prefix(6))
    }

    private func relate(_ other: String) {
        let other = other.trimmingCharacters(in: .whitespaces)
        guard !other.isEmpty else { return }
        store.relate(title, to: other)
        typed = ""
        adding = false
    }
}

/// A related page's pill: a link's, its symbol a chain — slanted when no
/// page has the name yet.
struct RelatedPill: View {
    let page: WikiStore.RelatedPage
    let shown: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: page.isOwn ? "link" : "arrow.turn.down.left")
                .font(.caption2.weight(.semibold))
            Text(shown)
                .italic(!page.exists)
                .lineLimit(1)
        }
        .footPill()
        .foregroundStyle(page.exists ? Ink.text.color : Ink.secondary.color)
        .background(Ink.rule.color.opacity(page.exists ? 0.9 : 0.5), in: Capsule())
        .overlay(Capsule().strokeBorder(Ink.rule.color))
    }
}

/// A row at a card's foot — what it is related to, the rivers it is in —
/// all alike: on the Mac its name in line before its pills, quiet; on the
/// phone over them, in small capitals.
struct FootRow<Content: View>: View {
    let name: String
    @ViewBuilder let content: () -> Content

    init(_ name: String, @ViewBuilder content: @escaping () -> Content) {
        self.name = name
        self.content = content
    }

    var body: some View {
        #if os(macOS)
        HStack(alignment: .firstTextBaseline, spacing: Measures.s) {
            Text(name)
                .font(.caption.weight(.medium))
                .foregroundStyle(Ink.secondary.color)
                .fixedSize()
            FlowLayout(spacing: 6) { content() }
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.8)
                .foregroundStyle(Ink.secondary.color)
            FlowLayout(spacing: 6) { content() }
        }
        #endif
    }
}

/// A pill at a card's foot: a related page's, a river's.
extension View {
    func footPill() -> some View {
        #if os(macOS)
        self.font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        #else
        self.font(.callout)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
        #endif
    }
}
