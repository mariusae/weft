import ReflectCore
import SwiftUI
import WeftCore

/// A card's page, written in where it stands — there is no Edit, and no
/// Preview: its tags, its typed fields, its body — as text or as an
/// outline, both reading as what they say — what it tags, and its other
/// fields. A change begins the card's draft, saved a moment after typing
/// pauses; when the caret leaves the card, the draft is let go.
struct CardEditor: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    let title: String
    let controller: EditorController
    /// Asked for from the card's menu.
    @Binding var addingTag: Bool
    @Binding var addingField: Bool
    @Binding var addingRelated: Bool
    @Binding var definingFields: Bool
    /// An untitled page that is a thing to do: its ring before its first
    /// line — in an outline, standing for its first row's mark.
    var lead: Tiddler.TaskState? = nil
    @State private var newTag = ""
    /// Where its words' first line's middle is, down from the editor's top.
    @State private var firstLine: CGFloat?
    /// Empty or not as the editor last said, typed in, until the store hears.
    @State private var typedEmpty: Bool?
    @State private var newField = ""
    @FocusState private var focus: Field?

    enum Field: Hashable { case tag, field }

    var body: some View {
        // All but its words, which the editor reads for itself: typing
        // redraws the editor, not the tags, fields and foot around it.
        let page = store.draftHead(title) ?? store.tiddler(title)
        VStack(alignment: .leading, spacing: partSpacing) {
            if store.isShadow(title), !store.isEditing(title) {
                Label("Built into Weft. Write in it, and it becomes one of your tiddlers.", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, textEdge)
            }
            tags(page?.tags ?? [])
                .padding(.leading, textEdge)
            let specs = page.map { store.schema(for: $0) } ?? []
            if !specs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(specs, id: \.name) { spec in
                        TypedFieldEditor(spec: spec, value: Binding {
                            (store.draft(title) ?? store.tiddler(title))?[field: spec.name]?.text ?? ""
                        } set: { value in
                            river.change(title, settling: true) { $0[field: spec.name] = .text(value) }
                        })
                    }
                }
                .font(.callout)
                .padding(10)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: Measures.controlRadius + 2))
                .padding(.leading, textEdge)
            }
            editor(page)
            // Related without a link: pages named in its frontmatter, or naming it.
            if page != nil || addingRelated { RelatedRow(title: title, adding: $addingRelated).padding(.leading, textEdge) }
            // The saved rivers it is a card of, but this one.
            if page != nil { InRiversRow(title: title).padding(.leading, textEdge) }
            if let page { foot(page, specs: specs).padding(.leading, textEdge) }
        }
        .onChange(of: focus) { _, now in
            if now != nil { river.caretEntered(title, in: .fields) } else { river.caretLeft(title, from: .fields) }
            if now != .tag { addingTag = false }
            if now != .field { addingField = false }
        }
    }

    // MARK: The body

    private var mode: WikiStore.EditorMode { store.editorMode(title) }

    /// Where a card's title and words begin: after its gutter, on the Mac.
    private var textEdge: CGFloat {
        #if os(macOS)
        Measures.gutter
        #else
        0
        #endif
    }

    private var partSpacing: CGFloat {
        #if os(macOS)
        Measures.cardParts
        #else
        12
        #endif
    }

    @AppStorage(TextSettings.sizeKey) private var textSize = TextSettings.standardSize
    @AppStorage(TextSettings.faceKey) private var face = ""

    @ViewBuilder private func editor(_ page: Tiddler?) -> some View {
        let wants = river.wantsCaret(title) == .body
        let taken = { river.caretTaken(title) }
        let focused: (Bool) -> Void = { $0 ? river.caretEntered(title, in: .body) : river.caretLeft(title, from: .body) }
        let body = ZStack(alignment: .topLeading) {
            BodyEditor(title: title, mode: mode, controller: controller, wants: wants, taken: taken, focused: focused,
                       lead: lead, onFirstLine: { firstLine = $0 }, onEmptinessChange: { typedEmpty = $0 })
            if showsPlaceholder {
                Text(placeholder(page))
                    .foregroundStyle(Ink.faint.color)
                    // In line with an outline's words, clear of its bullet.
                    .padding(.leading, mode == .outline ? OutlineCardEditor.textIndent : 0)
                    .allowsHitTesting(false)
                    #if os(macOS)
                    // Its middle on the outline's first line, where the
                    // editor says that is — the ring's, the words' to come.
                    .alignmentGuide(.top) { d in mode == .outline ? d.height / 2 - (firstLine ?? d.height / 2 + 2) : -2 }
                    #else
                    .padding(.top, 2)
                    #endif
            }
        }
        // The store has heard: what it has, not what was typed, again.
        .onChange(of: storedEmpty) { typedEmpty = nil }
        // Set again when Settings change how.
        .id("\(textSize) \(face)")
        #if os(macOS)
        if mode == .outline {
            // Its gutter its own: the outline draws its marks — the page's ring
            // among them — there. Its first line, as it says it is.
            body.alignmentGuide(.cardFirstLine) { firstLine ?? $0[VerticalAlignment.center] }
        } else {
            // Text has no gutter of its own: the card's, the ring in it.
            HStack(alignment: .cardFirstLine, spacing: 0) {
                GutterMark(kind: lead.map { .ring(done: $0 == .done) }) {
                    withAnimation(.snappy(duration: 0.2)) { store.setTaskState(title, lead == .done ? .todo : .done) }
                }
                body.alignmentGuide(.cardFirstLine) { _ in Measures.textFirstLine }
            }
        }
        #else
        body
        #endif
    }

    /// Empty, as the editor says as it is typed in — at once, not a moment
    /// later as the store hears — else as the store has it: asked of its
    /// head, not its words, told when it comes to be empty or not.
    private var storedEmpty: Bool {
        (store.isEditing(title) ? store.draftHead(title) : store.tiddler(title))?.text.isEmpty ?? true
    }

    private var showsPlaceholder: Bool {
        let stored = storedEmpty
        #if os(macOS)
        // The same for every card, being written in or not: a new one too.
        return typedEmpty ?? stored
        #else
        return !river.isWriting(title) && stored
        #endif
    }

    private func placeholder(_ page: Tiddler?) -> String {
        if store.kind(title) == .day { return "Nothing written on this day yet." }
        if page == nil { return Untitled.isName(title) ? "Jot something down." : "No tiddler has this title yet. Write here to make it." }
        return "Write here."
    }


    // MARK: Tags

    @ViewBuilder private func tags(_ tags: [String]) -> some View {
        if !tags.isEmpty || addingTag {
            VStack(alignment: .leading, spacing: 6) {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Button { river.open(tag, from: title) } label: { TagPill(tag: tag) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Remove Tag", systemImage: "minus.circle") {
                                    let at = tags.firstIndex(of: tag) ?? tags.count
                                    river.change(title, settling: true) { $0.tags.removeAll { $0 == tag } }
                                    store.undoable("Remove Tag “\(tag)”") { [river, title] in
                                        river.change(title, settling: true) { $0.tags.insert(tag, at: min(at, $0.tags.count)) }
                                    }
                                }
                            }
                    }
                    if addingTag {
                        TextField("Add tag", text: $newTag)
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .frame(width: 140)
                            .padding(.vertical, 3)
                            .focused($focus, equals: .tag)
                            .onSubmit { addTag(newTag) }
                            .onAppear { focus = .tag }
                    } else {
                        Button { addingTag = true } label: {
                            Image(systemName: "plus")
                                .font(.caption.weight(.bold))
                                .frame(width: 24, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Ink.faint.color)
                        .help("Add a Tag")
                    }
                }
                // Tags already in use, matching what is typed.
                let suggestions = tagSuggestions(excluding: tags)
                if !suggestions.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(suggestions, id: \.self) { tag in
                            Button { addTag(tag) } label: {
                                Text(tag)
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

    private func tagSuggestions(excluding current: [String]) -> [String] {
        let typed = newTag.trimmingCharacters(in: .whitespaces)
        guard addingTag, !typed.isEmpty else { return [] }
        let tags = store.tags().map(\.tag).filter { !current.contains($0) }
        return completions(for: typed, among: tags, limit: 8)
    }

    private func addTag(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespaces)
        newTag = ""
        guard !tag.isEmpty, !((store.draft(title) ?? store.tiddler(title))?.tags.contains(tag) ?? false) else { return }
        store.change(title) { $0.tags.append(tag) }
        focus = .tag
    }

    // MARK: The foot

    @ViewBuilder private func foot(_ page: Tiddler, specs: [FieldSpec]) -> some View {
        // A tag with fields of its own: what they are, and one more of it.
        let own = FieldSpec.specs(of: page)
        let tagged = store.tagged(title)
        if definingFields {
            VStack(alignment: .leading, spacing: 6) {
                SchemaEditor(tag: page.title, specs: Binding {
                    FieldSpec.specs(of: store.draft(title) ?? store.tiddler(title) ?? page)
                } set: { specs in
                    river.change(title, settling: true) { $0[field: FieldSpec.field] = specs.isEmpty ? nil : .list(specs.map(\.item)) }
                })
                Button("Done") { definingFields = false }
                    .font(.callout)
            }
        } else if !own.isEmpty || !tagged.isEmpty {
            HStack(spacing: 10) {
                if !own.isEmpty {
                    Button { definingFields = true } label: {
                        Label(own.map(\.name).joined(separator: ", "), systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("The fields of tiddlers tagged “\(title)”")
                }
                Spacer()
                Button("New \(title)", systemImage: "plus") { river.newTiddler(taggedWith: title) }
                    .font(.callout)
            }
        }
        if !tagged.isEmpty, !Self.listsTagged(page) {
            TaggedList(label: "Tagged “\(title)”", titles: tagged)
        }
        fields(page, excluding: Set(specs.map(\.name)))
    }

    /// Whether the body has a query for what is tagged with this tiddler,
    /// which the foot of the card would only repeat.
    private static func listsTagged(_ tiddler: Tiddler) -> Bool {
        MarkdownCache.blocks(tiddler.text).contains { block in
            guard case .query(let query) = block else { return false }
            return query.tags.contains(Query.this) || query.tags.contains(tiddler.title)
        }
    }

    /// Its other fields, each written in where it is shown.
    @ViewBuilder private func fields(_ page: Tiddler, excluding typed: Set<String>) -> some View {
        let fields = page.fields.filter { field in
            // `wiki` is the badge by the title; `list` and the fields a tag
            // gives are shown as what they are.
            // `task` and `done`, the ring by the title.
            field.value.text != nil && !["list", "wiki", "related", "task", "done", RiverLink.homeKey, PageIcon.key, FieldSpec.field].contains(field.name)
                && !typed.contains(field.name)
        }
        if !fields.isEmpty || addingField {
            DisclosureGroup(isExpanded: Binding(get: { addingField || store.fieldsShown.contains(title) },
                                                set: { if $0 { store.fieldsShown.insert(title) } else { store.fieldsShown.remove(title) } })) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 4) {
                    ForEach(fields, id: \.name) { field in
                        GridRow {
                            Text(field.name).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                            HStack {
                                TextField("", text: Binding {
                                    (store.draft(title) ?? store.tiddler(title))?[field: field.name]?.text ?? ""
                                } set: { value in
                                    river.change(title, settling: true) { $0[field: field.name] = .text(value) }
                                })
                                .textFieldStyle(.plain)
                                Button {
                                    let value = field.value
                                    river.change(title, settling: true) { $0[field: field.name] = nil }
                                    store.undoable("Remove Field “\(field.name)”") { [river, title] in
                                        river.change(title, settling: true) { $0[field: field.name] = value }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Remove Field")
                            }
                        }
                    }
                    GridRow {
                        TextField("Add field", text: $newField)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .field)
                            .frame(minWidth: 80)
                            .onSubmit(addField)
                            .onAppear { if addingField { focus = .field } }
                        Color.clear.frame(height: 1)
                    }
                    .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.top, 4)
            } label: {
                Text("Fields").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func addField() {
        let name = newField.trimmingCharacters(in: .whitespaces).lowercased()
        newField = ""
        let page = store.draft(title) ?? store.tiddler(title)
        guard !name.isEmpty, !Tiddler.reservedFields.contains(name), page?[field: name] == nil else { return }
        store.change(title) { $0[field: name] = .text("") }
        store.fieldsShown.insert(title)
    }
}

/// A card's body, as text or as an outline: a view of its own, the one
/// drawn again for each key — its binding reads the words as it is made,
/// and what reads them is told when they change.
private struct BodyEditor: View {
    @Environment(WikiStore.self) private var store
    let title: String
    let mode: WikiStore.EditorMode
    let controller: EditorController
    let wants: Bool
    let taken: () -> Void
    let focused: (Bool) -> Void
    var lead: Tiddler.TaskState? = nil
    var onFirstLine: (CGFloat) -> Void = { _ in }
    var onEmptinessChange: (Bool) -> Void = { _ in }

    var body: some View {
        if mode == .outline {
            #if os(macOS)
            OutlineCardEditor(text: text, title: title, wantsCaret: wants, onCaretTaken: taken, onFocusChange: focused,
                              lead: lead, onLead: { [store, title, lead] in
                                  withAnimation(.snappy(duration: 0.2)) { store.setTaskState(title, lead == .done ? .todo : .done) }
                              }, onFirstLine: onFirstLine, onEmptinessChange: onEmptinessChange)
            #else
            OutlineCardEditor(text: text, title: title, wantsCaret: wants, onCaretTaken: taken, onFocusChange: focused,
                              lead: lead, onLead: { [store, title, lead] in
                                  withAnimation(.snappy(duration: 0.2)) { store.setTaskState(title, lead == .done ? .todo : .done) }
                              })
            #endif
        } else {
            TiddlerEditor(text: text, controller: controller, card: title,
                          suggest: { store.linkSuggestions($0) }, exists: { store.linkExists($0) },
                          onEscape: { Platform.endEditing() },
                          wantsCaret: wants, onCaretTaken: taken, onFocusChange: focused,
                          onEmptinessChange: onEmptinessChange)
        }
    }

    /// The body: as the draft has it, else as saved; a change to it begins the draft.
    private var text: Binding<String> {
        Binding {
            (store.draft(title) ?? store.tiddler(title))?.text ?? ""
        } set: { value in
            let current = (store.draft(title) ?? store.tiddler(title))?.text
            guard current.map({ !value.isSameText(as: $0) }) ?? true else { return }
            store.change(title) { $0.text = value }
        }
    }
}

/// A list of links at a card's foot.
struct TaggedList: View {
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
