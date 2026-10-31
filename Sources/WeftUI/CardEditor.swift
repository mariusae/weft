import SwiftUI
import WeftCore

/// A card being edited: its title, tags, body and fields, kept as a draft
/// in the store until Done, so scrolling it away loses nothing.
struct CardEditor: View {
    @Environment(WikiStore.self) private var store
    let title: String
    @State private var newTag = ""
    @State private var newField = ""
    @State private var controller = EditorController()
    @State private var insertingQuery = false
    @State private var definingFields = false
    @FocusState private var focus: Field?

    enum Field: Hashable { case title, tag }

    var body: some View {
        if let draft = store.draft(title) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    if store.isPreviewing(title) {
                        Text(draft.title).font(.system(size: 22, weight: .semibold))
                    } else {
                        TextField("Title", text: binding(\.title))
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .semibold))
                            .focused($focus, equals: .title)
                    }
                    Spacer()
                    Picker("", selection: Binding(get: { store.isPreviewing(title) },
                                                  set: { if $0 != store.isPreviewing(title) { store.togglePreview(title) } })) {
                        Text("Edit").tag(false)
                        Text("Preview").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Edit or Preview (⌘↩)")
                    Button("Cancel") { withAnimation { store.cancel(title) } }
                        .keyboardShortcut(.cancelAction)
                    Button("Done") { withAnimation { store.save(title) } }
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                        .help("Save (⌘S)")
                }
                if store.isPreviewing(title) {
                    preview(draft)
                } else {
                    renaming(draft)
                    tags(draft)
                    VStack(alignment: .leading, spacing: 0) {
                        #if os(macOS)
                        HStack(spacing: 2) {
                            FormattingButtons(controller: controller)
                            Divider().frame(height: 16).padding(.horizontal, 4)
                            insertQueryButton
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
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
                        TiddlerEditor(text: binding(\.text), controller: controller,
                                      titles: { store.titles }, exists: { store.exists($0) },
                                      focusOnAppear: store.exists(title))
                            .padding(.horizontal, 6)
                    }
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
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
            .onAppear { if !store.exists(title) { focus = .title } }
        }
    }

    /// Being renamed: whether what refers to it is updated too.
    @ViewBuilder private func renaming(_ draft: Tiddler) -> some View {
        let new = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.exists(title), store.note(title) == nil, new != title, !new.isEmpty {
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

    /// The draft as its card will show it, saved or not.
    @ViewBuilder private func preview(_ draft: Tiddler) -> some View {
        if !draft.tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(draft.tags, id: \.self) { TagPill(tag: $0) }
            }
        }
        let specs = store.schema(for: draft)
        if !specs.isEmpty {
            PropertiesView(tiddler: draft, specs: specs)
        }
        if draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Nothing written yet.").foregroundStyle(.secondary)
        } else {
            MarkdownView(blocks: MarkdownBlock.parse(draft.text), card: title, editable: false)
        }
    }

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
                controller.insertBlock(query.block)
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
                    .foregroundStyle(Color.accentColor)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
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
                                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
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
