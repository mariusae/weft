import SwiftUI
import WeftCore

/// A card in Edit, under its header: its tags, body and fields. What is
/// written is kept in the store, and saved a moment after typing pauses.
struct CardEditor: View {
    @Environment(WikiStore.self) private var store
    let title: String
    @State private var newTag = ""
    @State private var newField = ""
    @State private var controller = EditorController()
    @State private var insertingQuery = false
    @State private var definingFields = false
    @FocusState private var focus: Field?

    enum Field: Hashable { case tag }

    var body: some View {
        if let draft = store.draft(title) {
            VStack(alignment: .leading, spacing: 12) {
                renaming(draft)
                tags(draft)
                VStack(alignment: .leading, spacing: 0) {
                    #if os(macOS)
                    HStack(spacing: 2) {
                        if mode == .text {
                            FormattingButtons(controller: controller)
                            Divider().frame(height: 16).padding(.horizontal, 4)
                        }
                        insertQueryButton
                        Spacer()
                        modePicker(draft)
                    }
                    .foregroundStyle(Ink.secondary.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    Divider()
                    #else
                    HStack {
                        Spacer()
                        insertQueryButton
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    #endif
                    #if os(macOS)
                    if mode == .outline {
                        OutlineCardEditor(text: binding(\.text), title: title)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 10)
                    } else {
                        textEditor
                    }
                    #else
                    textEditor
                    #endif
                }
                .background(Ink.rule.color.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                let specs = store.schema(for: draft)
                if !specs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(specs, id: \.name) { spec in
                            TypedFieldEditor(spec: spec, value: Binding {
                                store.draft(title)?[field: spec.name]?.text ?? ""
                            } set: { value in
                                guard var updated = store.draft(title) else { return }
                                updated[field: spec.name] = .text(value)
                                store.updateDraft(title, updated)
                            })
                        }
                    }
                    .font(.callout)
                }
                schema(draft)
                fields(draft, excluding: Set(specs.map(\.name)))
            }
        }
    }

    /// Being renamed: whether what refers to it is updated too.
    @ViewBuilder private func renaming(_ draft: Tiddler) -> some View {
        let new = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.tiddler(title) != nil, store.kind(title) != .day, new != title, !new.isEmpty {
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

    private var mode: WikiStore.EditorMode { store.editorMode(title) }

    private var textEditor: some View {
        TiddlerEditor(text: binding(\.text), controller: controller,
                      suggest: { store.linkSuggestions($0) }, exists: { store.exists($0) },
                      onEscape: { withAnimation { store.finishEditing(title) } },
                      focusOnAppear: store.exists(title))
            .padding(.horizontal, 6)
    }

    #if os(macOS)
    /// Text, or Prism's outline: an outline only of a body that would be
    /// written back as it was.
    private func modePicker(_ draft: Tiddler) -> some View {
        let outlinable = mode == .outline || OutlineEditing.canEdit(draft.text)
        return Picker("Editor", selection: Binding(get: { mode }, set: { store.setEditorMode($0, for: title) })) {
            ForEach(WikiStore.EditorMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .controlSize(.small)
        .disabled(!outlinable)
        .help(outlinable ? "Edit as Text, or as an Outline of rows" : "This page can't be edited as an outline without changing how it's written")
    }
    #endif

    private var insertQueryButton: some View {
        Button {
            insertingQuery = true
        } label: {
            Label("Insert Query", systemImage: "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(.borderless)
        .help("Insert a list of tiddlers found by a query")
        .popover(isPresented: $insertingQuery) {
            QueryBuilder(query: Self.starterQuery, card: title) { query in
                if mode == .outline, var draft = store.draft(title) {
                    // An outline's own rows: put at its foot.
                    draft.text += (draft.text.isEmpty || draft.text.hasSuffix("\n\n") ? "" : draft.text.hasSuffix("\n") ? "\n" : "\n\n") + query.block + "\n"
                    store.updateDraft(title, draft)
                } else {
                    controller.insertBlock(query.block)
                }
                insertingQuery = false
            } cancel: {
                insertingQuery = false
            }
        }
    }

    /// What a new query starts as: what is tagged with this tiddler.
    private static var starterQuery: Query {
        var query = Query()
        query.tags = [Query.this]
        return query
    }

    private func binding<Value>(_ path: WritableKeyPath<Tiddler, Value>) -> Binding<Value> {
        Binding {
            // Done or Cancel takes the draft away before SwiftUI has let go of
            // the editor's bindings: they read the tiddler then.
            (store.draft(title) ?? store.tiddler(title) ?? Tiddler(title: title))[keyPath: path]
        } set: { value in
            guard var draft = store.draft(title) else { return }
            draft[keyPath: path] = value
            store.updateDraft(title, draft)
        }
    }

    private func tags(_ draft: Tiddler) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(draft.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                        Button {
                            var updated = draft
                            updated.tags.removeAll { $0 == tag }
                            store.updateDraft(title, updated)
                        } label: {
                            Image(systemName: "xmark").font(.caption2.weight(.bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .foregroundStyle(Ink.accent.color)
                    .background(Ink.accent.color.opacity(0.12), in: Capsule())
                }
                TextField("Add tag", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .frame(width: 140)
                    .padding(.vertical, 3)
                    .focused($focus, equals: .tag)
                    .onSubmit { addTag(newTag) }
            }
            // Tags already in use, matching what is typed.
            let suggestions = tagSuggestions(excluding: draft.tags)
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

    private func tagSuggestions(excluding current: [String]) -> [String] {
        let typed = newTag.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return [] }
        let tags = store.tags().map(\.tag).filter { !current.contains($0) }
        return completions(for: typed, among: tags, limit: 8)
    }

    private func addTag(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, var updated = store.draft(title), !updated.tags.contains(tag) else { return }
        updated.tags.append(tag)
        store.updateDraft(title, updated)
        newTag = ""
        focus = .tag
    }

    /// The fields this tiddler, as a tag, gives what it tags — or a way to
    /// give some.
    @ViewBuilder private func schema(_ draft: Tiddler) -> some View {
        let specs = FieldSpec.specs(of: draft)
        if !specs.isEmpty || definingFields {
            SchemaEditor(tag: draft.title, specs: Binding {
                FieldSpec.specs(of: store.draft(title) ?? draft)
            } set: { specs in
                guard var updated = store.draft(title) else { return }
                updated[field: FieldSpec.field] = specs.isEmpty ? nil : .list(specs.map(\.item))
                store.updateDraft(title, updated)
            })
        } else if !store.tagged(draft.title).isEmpty {
            Button("Give Tiddlers Tagged “\(draft.title)” Fields…", systemImage: "list.bullet.rectangle") { definingFields = true }
                .buttonStyle(.borderless)
                .font(.callout)
        }
    }

    private func fields(_ draft: Tiddler, excluding typed: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(draft.fields.filter { $0.value.text != nil && !typed.contains($0.name) }, id: \.name) { field in
                HStack {
                    Text(field.name).foregroundStyle(.secondary).frame(width: 120, alignment: .trailing)
                    TextField("", text: Binding {
                        store.draft(title)?[field: field.name]?.text ?? ""
                    } set: { value in
                        guard var updated = store.draft(title) else { return }
                        updated[field: field.name] = .text(value)
                        store.updateDraft(title, updated)
                    })
                    .textFieldStyle(.roundedBorder)
                    Button {
                        var updated = draft
                        updated[field: field.name] = nil
                        store.updateDraft(title, updated)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove field")
                }
            }
            HStack {
                TextField("Add field", text: $newField)
                    .textFieldStyle(.plain)
                    .frame(width: 120, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .onSubmit {
                        let name = newField.trimmingCharacters(in: .whitespaces).lowercased()
                        guard !name.isEmpty, !Tiddler.reservedFields.contains(name), var updated = store.draft(title),
                              updated[field: name] == nil else { return }
                        updated[field: name] = .text("")
                        store.updateDraft(title, updated)
                        newField = ""
                    }
                Spacer()
            }
            .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}
