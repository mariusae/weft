import ReflectCore
import SwiftUI
import WeftCore

/// Beside the river, where there is room: what the selected card is linked
/// with, the pages it links to read — to take notes from in the river as
/// they are read — or, on the Mac, its inspector. Chosen at its head.
struct SidePanel: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river

    private var kinds: [River.Side] {
        #if os(macOS)
        River.Side.allCases
        #else
        [.related, .reading]
        #endif
    }

    var body: some View {
        let side = river.side ?? .related
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Beside the River", selection: Binding(get: { side }, set: choose)) {
                    ForEach(kinds, id: \.self) { kind in
                        Label(kind.name, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button { river.side = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointing()
                .foregroundStyle(Ink.secondary.color)
                .help("Hide the Side")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            content(side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.card)
    }

    @ViewBuilder private func content(_ side: River.Side) -> some View {
        switch side {
        case .reading:
            if let reading = river.reading ?? river.selected.flatMap({ store.canRead($0) ? $0 : nil }) {
                ReaderPanel(title: reading, inSide: true).id(reading)
            } else {
                ContentUnavailableView("Nothing to Read", systemImage: "doc.richtext",
                                       description: Text("Choose a card that links to a page, then Read — or Read from a page in Related."))
            }
        case .related:
            if let card = river.selected {
                RelatedSide(card: card).id(card)
            } else {
                ContentUnavailableView("No Card Chosen", systemImage: River.Side.related.symbol,
                                       description: Text("What the chosen card is linked with shows here."))
            }
        case .inspector:
            #if os(macOS)
            if let card = river.selected {
                CardInspector(title: card).id(card)
            } else {
                ContentUnavailableView("No Card Chosen", systemImage: "info.circle")
            }
            #else
            EmptyView()
            #endif
        }
    }

    /// Another side chosen; reading, the page read is the one read last —
    /// else the chosen card's, if it links to one.
    private func choose(_ side: River.Side) {
        if side == .reading {
            if river.reading == nil, let card = river.selected, store.canRead(card) {
                river.reading = card
                return
            }
        }
        river.side = side
    }
}

/// What a card is linked with, beside it as it is written — following the
/// card chosen: what links to it, with the words around each link; what it
/// links to, with its own words there; what it is related to; and what
/// shares its tags. Each opened after it with a click, or read beside it.
struct RelatedSide: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    let card: String

    var body: some View {
        let here = store.backlinks(of: card)
        let out = outgoing
        let related = store.related(of: card).filter(\.exists).map(\.title)
        let tagged = sharingTags(excluding: Set(here.map(\.title) + out.map(\.title) + related))
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 6) {
                    Image(systemName: store.symbol(of: card))
                        .foregroundStyle(Ink.secondary.color)
                    Text(store.shownTitle(card))
                        .font(.headline)
                        .lineLimit(2)
                }
                if here.isEmpty, out.isEmpty, related.isEmpty, tagged.isEmpty {
                    Text("Nothing links with “\(store.shownTitle(card))” yet. Link to another page — [[ — or relate it, and it shows here.")
                        .font(.callout)
                        .foregroundStyle(Ink.secondary.color)
                }
                section(here.count == 1 ? "1 Link Here" : "\(here.count) Links Here", here.map { link in
                    Row(title: link.title, shown: link.shown, symbol: link.symbol,
                        words: store.context(of: link, linkingTo: card))
                })
                section("Links To", out.map { link in
                    Row(title: link.title, shown: link.shown, symbol: link.symbol,
                        words: store.context(of: store.target(card), linkingTo: link.title))
                })
                section("Related", related.map { title in
                    Row(title: title, shown: store.shownTitle(title), symbol: store.symbol(of: title), words: nil)
                })
                ForEach(tagged, id: \.tag) { group in
                    section("#" + group.tag, group.titles.map { title in
                        Row(title: title, shown: store.shownTitle(title), symbol: store.symbol(of: title), words: nil)
                    })
                }
            }
            .padding(16)
        }
    }

    /// What the card links to, as pages: days and pages not written yet too.
    private var outgoing: [LinkTarget] {
        store.links(from: card).filter { $0 != card }.map(store.target).sorted { $0.shown.localizedStandardCompare($1.shown) == .orderedAscending }
    }

    /// The pages sharing each of its tags, a few to a tag — none already shown.
    private func sharingTags(excluding shown: Set<String>) -> [(tag: String, titles: [String])] {
        let tags = (store.draftHead(card) ?? store.tiddler(card))?.tags ?? []
        return tags.compactMap { tag in
            let titles = store.tagged(tag).filter { $0 != card && !shown.contains($0) }.prefix(8)
            return titles.isEmpty ? nil : (tag, Array(titles))
        }
    }

    private struct Row: Identifiable {
        let title: String
        let shown: String
        let symbol: String
        let words: String?
        var id: String { title }
    }

    @ViewBuilder private func section(_ name: String, _ rows: [Row]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(name.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Ink.secondary.color)
                    .padding(.bottom, 4)
                ForEach(rows) { row in line(row) }
            }
        }
    }

    private func line(_ row: Row) -> some View {
        let words = row.words?.trimmingCharacters(in: .whitespaces)
        let says = words.flatMap { $0.isEmpty || $0.caseInsensitiveCompare(row.shown) == .orderedSame ? nil : $0 }
            ?? peek(row.title)
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: row.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.accent.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.shown)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Ink.text.color)
                    .lineLimit(1)
                if let says {
                    Text(says)
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary.color)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if store.canRead(row.title) {
                Button { river.reading = row.title } label: { Image(systemName: "doc.richtext") }
                    .buttonStyle(.plain)
                    .pointing()
                    .foregroundStyle(Ink.accent.color)
                    .help("Read “\(row.shown)” here")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy(duration: 0.28)) { river.open(row.title, from: card) } }
        .pointing()
        .contextMenu {
            Button("Open After “\(store.shownTitle(card))”", systemImage: "arrow.up.forward.square") { river.open(row.title, from: card) }
            if store.canRead(row.title) {
                Button("Read Here", systemImage: "doc.richtext") { river.reading = row.title }
            }
        }
    }

    /// What a page says, as a line or two: for one linked without words around it.
    private func peek(_ title: String) -> String? {
        guard store.tiddler(title) != nil else { return nil }
        let summary = store.peek(of: title).summary
        return summary.isEmpty ? nil : summary
    }
}
