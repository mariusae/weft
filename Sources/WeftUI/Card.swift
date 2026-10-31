import SwiftUI
import WeftCore

/// A tiddler's card in the river: its title and controls, then its tags,
/// body and what is tagged with it — or, in Edit, its editor — and at its
/// foot, what links to it.
struct Card: View {
    @Environment(WikiStore.self) private var store
    let title: String
    @State private var hovering = false
    @State private var confirmingDelete = false
    /// How many pages refer to it, counted when its deletion is asked for —
    /// not each time the card is drawn.
    @State private var referring = 0
    /// How wide the controls over the title are.
    @State private var controlsWidth: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if store.isEditing(title) {
                CardEditor(title: title)
            } else if !store.folded.contains(title) {
                if store.needsReview(title) {
                    ConflictView(title: title)
                } else {
                    // On the phone, where there is no room for Edit and
                    // Preview beside the title, a tap on what it says edits it.
                    VStack(alignment: .leading, spacing: 12) {
                        if let tiddler = store.tiddler(title) {
                            content(tiddler)
                        } else if store.kind(title) == .day {
                            Text(compact ? "Nothing written on this day yet. Tap to write." : "Nothing written on this day yet.")
                                .foregroundStyle(Ink.secondary.color)
                        } else {
                            missing
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard compact else { return }
                        withAnimation(.snappy(duration: 0.25)) { store.edit(title) }
                    }
                }
                let links = store.backlinks(of: title)
                if !links.isEmpty {
                    BacklinkFan(card: title, links: links)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, sizeClass == .compact ? 14 : 22)
        .padding(.vertical, sizeClass == .compact ? 14 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.rule.color.opacity(store.isSelected(title) ? 0 : 1)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.accent.color.opacity(store.isSelected(title) ? 0.45 : 0)))
        .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
        .onHover { hovering = $0 }
        // A click makes it the card ⌘↩ goes to.
        .simultaneousGesture(TapGesture().onEnded { store.select(title) })
        .confirmationDialog("Delete “\(title)”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { withAnimation { store.delete(title) } }
        } message: {
            Text(referring == 0 ? "Its file is removed; the graph's history keeps it."
                 : "\(referring) \(referring == 1 ? "page refers" : "pages refer") to it. Its file is removed; the graph's history keeps it.")
        }
        .environment(\.openURL, OpenURLAction { url in
            if let target = InlineMarkdown.title(from: url) {
                store.open(target, from: title)
                return .handled
            }
            return .systemAction
        })
    }

    /// The title — typed in, while editing — and the card's controls.
    /// The title on one line — running on under the controls, which float
    /// over it on glass, and cut off at the card's edge — and the controls.
    private var header: some View {
        let kind = store.kind(title)
        let editing = store.isEditing(title)
        return HStack(alignment: .center, spacing: 10) {
            if kind == .day {
                Image(systemName: "calendar")
                    .foregroundStyle(Ink.secondary.color)
                    .help("A day")
            }
            if editing {
                TextField("Title", text: Binding {
                    store.draft(title)?.title ?? title
                } set: { value in
                    guard var draft = store.draft(title) else { return }
                    draft.title = value
                    store.updateDraft(title, draft)
                })
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(1)
                // Typed in, clear of the controls.
                .padding(.trailing, controlsWidth + 8)
            } else {
                Text(store.shownTitle(title))
                    .font(.system(size: 22, weight: .semibold))
                    .italic(!store.exists(title))
                    .foregroundStyle(store.exists(title) ? Ink.text.color : Ink.secondary.color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
                    .onTapGesture(count: 2) { store.edit(title) }
            }
            if kind == .wiki || (editing && store.draft(title)?.isWiki == true) {
                Label("Wiki", systemImage: "book.closed")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(Ink.accent.color)
                    .background(Ink.accent.color.opacity(0.1), in: Capsule())
                    .fixedSize()
                    .help("A wiki page: canonical, kept up")
            }
        }
        // As wide as the card gives, however long the title: the rest of it
        // runs on under the controls and is cut off at the card's edge.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .clipped()
        .overlay(alignment: .trailing) {
            controls(editing: editing)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { controlsWidth = $0 }
        }
    }

    /// Edit or Preview; and, in a glass capsule, the card's menu and its
    /// close button.
    private func controls(editing: Bool) -> some View {
        HStack(spacing: 8) {
            if !compact {
                Picker("", selection: Binding(get: { editing }, set: { $0 ? store.edit(title) : store.finishEditing(title) })) {
                    Text("Edit").tag(true)
                    Text("Preview").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                .padding(3)
                .glassEffect(.regular.interactive(), in: .capsule)
                .help("Edit or Preview (⌘↩)")
            } else if editing {
                // Editing on the phone: Done, back to what it says.
                Button { withAnimation(.snappy(duration: 0.25)) { store.finishEditing(title) } } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassEffect(.regular.tint(Ink.accent.color).interactive(), in: .circle)
                .accessibilityLabel("Done")
            }
            HStack(spacing: 0) {
                Menu {
                    if compact && !editing {
                        Button("Edit", systemImage: "pencil") { withAnimation(.snappy(duration: 0.25)) { store.edit(title) } }
                    }
                    Button(store.folded.contains(title) ? "Unfold" : "Fold") {
                        withAnimation(.snappy(duration: 0.2)) { store.toggleFold(title) }
                    }
                    Button("Close Other Cards") { withAnimation { store.closeOthers(title) } }
                    if store.tiddler(title) != nil || editing {
                        let wiki = editing ? store.draft(title)?.isWiki == true : store.isWiki(title)
                        Button(wiki ? "Remove from Wiki" : "Add to Wiki") { store.setWiki(title, !wiki) }
                    }
                    Divider()
                    Button("Copy Link") { Platform.copy("[[\(title)]]") }
                    if Platform.canReveal, let path = store.path(of: title) {
                        Button("Show in Finder") { Platform.reveal(path) }
                    }
                    if store.tiddler(title) != nil, !store.isShadow(title) {
                        Divider()
                        Button("Delete Page…", role: .destructive) {
                            referring = store.references(to: title).count
                            confirmingDelete = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 26)
                        .contentShape(Rectangle())
                }
                #if os(macOS)
                .menuStyle(.button)
                #endif
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
                Button { withAnimation { store.close(title) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 30, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .foregroundStyle(Ink.secondary.color)
            .padding(.horizontal, 2)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        #if os(macOS)
        .opacity(hovering || editing || store.isSelected(title) ? 1 : 0.55)
        .animation(.easeOut(duration: 0.15), value: hovering)
        #endif
    }

    @ViewBuilder private func content(_ tiddler: Tiddler) -> some View {
        if store.isShadow(title) {
            Label("Built into Weft. Edit it, and it becomes one of your tiddlers.", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if !tiddler.tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(tiddler.tags, id: \.self) { tag in
                    Button { store.open(tag, from: title) } label: { TagPill(tag: tag) }
                        .buttonStyle(.plain)
                }
            }
        }
        let specs = store.schema(for: tiddler)
        if !specs.isEmpty {
            PropertiesView(tiddler: tiddler, specs: specs)
        }
        if !tiddler.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            MarkdownView(blocks: MarkdownCache.blocks(tiddler.text), card: title)
        }
        // A tag with fields of its own: what they are, and one more of it.
        let own = FieldSpec.specs(of: tiddler)
        if !own.isEmpty || !store.tagged(title).isEmpty {
            HStack(spacing: 10) {
                if !own.isEmpty {
                    Label(own.map(\.name).joined(separator: ", "), systemImage: "list.bullet.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("The fields of tiddlers tagged “\(title)”")
                }
                Spacer()
                Button("New \(title)", systemImage: "plus") { store.newTiddler(taggedWith: title) }
                    .font(.callout)
            }
        }
        let tagged = store.tagged(title)
        if !tagged.isEmpty, !Self.listsTagged(tiddler) {
            Section(label: "Tagged “\(title)”", titles: tagged)
        }
        let fields = tiddler.fields.filter { field in
            field.name != "list" && field.name != FieldSpec.field && !specs.contains { $0.name == field.name }
        }
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
    }

    /// Whether the body has a query for what is tagged with this tiddler,
    /// which the foot of the card would only repeat.
    private static func listsTagged(_ tiddler: Tiddler) -> Bool {
        MarkdownCache.blocks(tiddler.text).contains { block in
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
                        .foregroundStyle(Ink.accent.color)
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

struct TagPill: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .foregroundStyle(Ink.accent.color)
            .background(Ink.accent.color.opacity(0.12), in: Capsule())
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
