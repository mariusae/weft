import SwiftUI
import WeftCore

/// A tiddler's card in the river: its title and controls, then its page —
/// written in where it stands — and at its foot, what links to it.
struct Card: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    let title: String
    @State private var hovering = false
    @State private var confirmingDelete = false
    /// How many pages refer to it, counted when its deletion is asked for —
    /// not each time the card is drawn.
    @State private var referring = 0
    /// How wide the controls over the title are.
    @State private var controlsWidth: CGFloat = 0
    /// The title being typed in: renaming.
    @State private var renaming = false
    @FocusState private var titleFocused: Bool
    @State private var controller = EditorController()
    @State private var insertingQuery = false
    @State private var addingTag = false
    @State private var addingField = false
    @State private var definingFields = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            relinking
            if !river.isFolded(title) {
                if store.needsReview(title) {
                    ConflictView(title: title)
                } else {
                    CardEditor(title: title, controller: controller, addingTag: $addingTag,
                               addingField: $addingField, definingFields: $definingFields)
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
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.rule.color.opacity(river.isSelected(title) ? 0 : 1)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.accent.color.opacity(river.isSelected(title) ? 0.45 : 0)))
        .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
        .onHover { hovering = $0 }
        // A click makes it the card ⌘↩ goes to.
        .simultaneousGesture(TapGesture().onEnded { river.select(title) })
        .confirmationDialog("Delete “\(title)”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { withAnimation { store.delete(title) } }
        } message: {
            Text(referring == 0 ? "Its file is removed; the graph's history keeps it."
                 : "\(referring) \(referring == 1 ? "page refers" : "pages refer") to it. Its file is removed; the graph's history keeps it.")
        }
        .environment(\.openURL, OpenURLAction { url in
            if let target = InlineMarkdown.title(from: url) {
                river.open(target, from: title)
                return .handled
            }
            return .systemAction
        })
        // A new tiddler's title is typed first.
        .onChange(of: river.wantsCaret(title) == .title, initial: true) { _, wanted in
            guard wanted else { return }
            startRenaming()
            river.caretTaken(title)
        }
        .onChange(of: titleFocused) { _, focused in
            if focused {
                river.caretEntered(title)
            } else {
                renaming = false
                river.caretLeft(title)
            }
        }
    }

    /// Being renamed: whether what refers to it is updated too.
    @ViewBuilder private var relinking: some View {
        if let draft = store.draftHead(title), store.tiddler(title) != nil, store.kind(title) != .day {
            let new = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if new != title, !new.isEmpty {
                let references = store.references(to: title)
                if !references.isEmpty {
                    Toggle(isOn: Binding(get: { store.relinkOnRename[title] ?? true }, set: { store.relinkOnRename[title] = $0 })) {
                        Text("Update \(references.count) \(references.count == 1 ? "tiddler" : "tiddlers") that refer to “\(title)”")
                            .help(references.prefix(12).joined(separator: ", "))
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var canRename: Bool { store.kind(title) != .day && !store.isShadow(title) }

    private func startRenaming() {
        guard canRename else { return }
        renaming = true
        titleFocused = true
    }

    /// The title on one line — running on under the controls, which float
    /// over it on glass, and cut off at the card's edge — and the controls.
    /// Double-clicked, it is typed in.
    private var header: some View {
        let kind = store.kind(title)
        let shown = store.draftHead(title).map(\.title) ?? store.shownTitle(title)
        return HStack(alignment: .center, spacing: 10) {
            if kind == .day {
                Image(systemName: "calendar")
                    .foregroundStyle(Ink.secondary.color)
                    .help("A day")
            }
            if renaming {
                TextField("Title", text: Binding {
                    store.draftHead(title)?.title ?? title
                } set: { value in
                    store.change(title) { $0.title = value }
                })
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(1)
                .focused($titleFocused)
                .onSubmit {
                    // A new tiddler named: on to what it says. One renamed: done.
                    if store.exists(title) { Platform.endEditing() } else { river.edit(title) }
                }
                // Typed in, clear of the controls.
                .padding(.trailing, controlsWidth + 8)
            } else {
                Text(shown)
                    .font(.system(size: 22, weight: .semibold))
                    .italic(!store.exists(title) && !store.isEditing(title))
                    .foregroundStyle(store.exists(title) || store.isEditing(title) ? Ink.text.color : Ink.secondary.color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .onTapGesture(count: 2) { startRenaming() }
            }
            let wiki = store.draftHead(title)?.isWiki ?? (kind == .wiki)
            if wiki {
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
        // Dragged by its title to elsewhere in the river; on the phone, held first.
        .draggingCard(title, shown: shown, enabled: !renaming)
        .overlay(alignment: .trailing) {
            controls
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { controlsWidth = $0 }
        }
    }

    /// Text or Outline; and, in a glass capsule, the card's menu and its
    /// close button.
    private func dayButton(_ symbol: String, _ name: String, by: Int) -> some View {
        Button { withAnimation(.snappy(duration: 0.28)) { river.openDay(beside: title, by: by) } } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
    }

    private var controls: some View {
        let writing = river.isWriting(title)
        return HStack(spacing: 8) {
            #if os(macOS)
            Picker("", selection: Binding(get: { store.editorMode(title) }, set: { store.setEditorMode($0, for: title) })) {
                ForEach(WikiStore.EditorMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            .padding(3)
            .glassEffect(.regular.interactive(), in: .capsule)
            .help("Write as Text, or as an Outline of rows")
            #else
            if writing {
                // Writing on the phone: Done, the keyboard put away.
                Button { Platform.endEditing() } label: {
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
            #endif
            HStack(spacing: 0) {
                if store.kind(title) == .day, !writing {
                    // The day before and after, opened just after this one.
                    dayButton("chevron.left", "Previous Day", by: -1)
                    dayButton("chevron.right", "Next Day", by: 1)
                }
                menu
                Button { withAnimation { river.close(title) } } label: {
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
            .popover(isPresented: $insertingQuery) {
                QueryBuilder(query: Self.starterQuery, card: title) { query in
                    insert(query)
                    insertingQuery = false
                } cancel: {
                    insertingQuery = false
                }
            }
        }
        #if os(macOS)
        .opacity(hovering || writing || river.isSelected(title) ? 1 : 0.55)
        .animation(.easeOut(duration: 0.15), value: hovering)
        #endif
    }

    private var menu: some View {
        Menu {
            if canRename {
                Button("Rename", systemImage: "character.cursor.ibeam") { startRenaming() }
            }
            Button(river.isFolded(title) ? "Unfold" : "Fold") {
                withAnimation(.snappy(duration: 0.2)) { river.toggleFold(title) }
            }
            Button("Close Other Cards") { withAnimation { river.closeOthers(title) } }
            #if os(iOS)
            // The Mac's switch in the header, on the phone in here: no room beside the title.
            Picker("Write As", selection: Binding(get: { store.editorMode(title) }, set: { store.setEditorMode($0, for: title) })) {
                ForEach(WikiStore.EditorMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            #endif
            Divider()
            Button("Add Tag", systemImage: "tag") { addingTag = true }
            Button("Add Field", systemImage: "plus.rectangle") {
                addingField = true
                store.fieldsShown.insert(title)
            }
            Button("Insert Query…", systemImage: "line.3.horizontal.decrease.circle") { insertingQuery = true }
            if store.tiddler(title) != nil, !store.tagged(title).isEmpty || !FieldSpec.specs(of: store.tiddler(title)!).isEmpty {
                Button("Fields of Tiddlers Tagged “\(title)”…", systemImage: "list.bullet.rectangle") { definingFields = true }
            }
            if store.tiddler(title) != nil || store.isEditing(title) {
                let wiki = store.draftHead(title)?.isWiki ?? store.isWiki(title)
                Button(wiki ? "Remove from Wiki" : "Add to Wiki") { store.setWiki(title, !wiki) }
            }
            Divider()
            Button("Copy Link") { Platform.copy("[[\(title)]]") }
            if Platform.canReveal, let path = store.path(of: title) {
                Button("Show in Finder") { Platform.reveal(path) }
            }
            if store.tiddler(title) != nil, !store.isShadow(title) {
                Divider()
                Button("Delete Tiddler…", role: .destructive) {
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
    }

    /// A query put in: at the caret, while the caret is in the text; else at
    /// the foot of what the card says.
    private func insert(_ query: Query) {
        if river.isWriting(title), store.editorMode(title) == .text {
            controller.insertBlock(query.block)
        } else {
            river.change(title, settling: true) { page in
                let text = page.text
                page.text += (text.isEmpty || text.hasSuffix("\n\n") ? "" : text.hasSuffix("\n") ? "\n" : "\n\n") + query.block + "\n"
            }
        }
    }

    /// What a new query starts as: what is tagged with this tiddler.
    private static var starterQuery: Query {
        var query = Query()
        query.tags = [Query.this]
        return query
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
