import SwiftUI
import WeftCore

/// A tiddler's card in the river: its title and buttons, its tags, its
/// body, and what is tagged with it and links to it — or, being edited,
/// the editor.
struct Card: View {
    @Environment(WikiStore.self) private var store
    let title: String
    @State private var hovering = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.isEditing(title) {
                CardEditor(title: title)
            } else {
                header
                if !store.folded.contains(title) {
                    if store.needsReview(title) {
                        ConflictView(title: title)
                    } else if let tiddler = store.tiddler(title) {
                        content(tiddler)
                    } else {
                        missing
                    }
                }
            }
        }
        .padding(.horizontal, sizeClass == .compact ? 14 : 22)
        .padding(.vertical, sizeClass == .compact ? 14 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(store.focus == title ? 0 : 0.6)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(store.focus == title ? 0.45 : 0)))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .onHover { hovering = $0 }
        .environment(\.openURL, OpenURLAction { url in
            if let target = InlineMarkdown.title(from: url) {
                store.open(target, from: title)
                return .handled
            }
            return .systemAction
        })
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .italic(!store.exists(title))
                .foregroundStyle(store.exists(title) ? .primary : .secondary)
                .textSelection(.enabled)
                .onTapGesture(count: 2) { store.edit(title) }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                CardButton(symbol: "pencil", help: "Edit") { store.edit(title) }
                CardButton(symbol: store.folded.contains(title) ? "chevron.down" : "chevron.up",
                           help: store.folded.contains(title) ? "Unfold" : "Fold") {
                    withAnimation(.snappy(duration: 0.2)) { store.toggleFold(title) }
                }
                Menu {
                    Button("Close Other Cards") { withAnimation { store.closeOthers(title) } }
                    Button("Copy Link") { Platform.copy("[[\(title)]]") }
                    if Platform.canReveal, let path = store.path(of: title) {
                        Button("Show in Finder") { Platform.reveal(path) }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 26, height: 24)
                }
                #if os(macOS)
                .menuStyle(.button)
                #endif
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                CardButton(symbol: "xmark", help: "Close") { withAnimation { store.close(title) } }
            }
            #if os(macOS)
            .opacity(hovering ? 1 : 0.35)
            #endif
        }
    }

    @ViewBuilder private func content(_ tiddler: Tiddler) -> some View {
        if !tiddler.tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(tiddler.tags, id: \.self) { tag in
                    Button { store.open(tag, from: title) } label: { TagPill(tag: tag) }
                        .buttonStyle(.plain)
                }
            }
        }
        if !tiddler.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            MarkdownView(blocks: MarkdownBlock.parse(tiddler.text), card: title)
        }
        let tagged = store.tagged(title)
        if !tagged.isEmpty, !Self.listsTagged(tiddler) {
            Section(label: "Tagged “\(title)”", titles: tagged)
        }
        let fields = tiddler.fields.filter { $0.name != "list" }
        if !fields.isEmpty {
            DisclosureGroup {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 4) {
                    ForEach(fields, id: \.name) { field in
                        GridRow {
                            Text(field.name).foregroundStyle(.secondary)
                            Text(field.value.text ?? field.value.list?.joined(separator: ", ") ?? "")
                                .textSelection(.enabled)
                        }
                    }
                }
                .font(.callout)
                .padding(.top, 4)
            } label: {
                Text("Fields").font(.callout).foregroundStyle(.secondary)
            }
        }
        let backlinks = store.backlinks(title)
        if !backlinks.isEmpty {
            Section(label: "Linked from", titles: backlinks)
        }
    }

    /// Whether the body has a query for what is tagged with this tiddler,
    /// which the foot of the card would only repeat.
    private static func listsTagged(_ tiddler: Tiddler) -> Bool {
        MarkdownBlock.parse(tiddler.text).contains { block in
            guard case .query(let query) = block else { return false }
            return query.tags.contains(Query.this) || query.tags.contains(tiddler.title)
        }
    }

    private var missing: some View {
        HStack {
            Text("No tiddler has this title yet.").foregroundStyle(.secondary)
            Button("Create It") { store.edit(title) }
        }
    }

    /// A list of links at a card's foot.
    private struct Section: View {
        @Environment(WikiStore.self) private var store
        let label: String
        let titles: [String]
        @State private var showingAll = false
        /// How many are shown before Show All.
        private let limit = 24

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Divider().padding(.bottom, 2)
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                FlowLayout(spacing: 4) {
                    ForEach(showingAll ? titles : Array(titles.prefix(limit)), id: \.self) { linked in
                        Link(destination: InlineMarkdown.url(for: linked)) {
                            Text(linked)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                    if titles.count > limit {
                        Button(showingAll ? "Show Fewer" : "Show All \(titles.count)") {
                            withAnimation(.snappy(duration: 0.2)) { showingAll.toggle() }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                    }
                }
                .font(.callout)
            }
        }
    }
}

struct CardButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 26, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

struct TagPill: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}

/// Views laid out in rows, wrapping, as words are.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
