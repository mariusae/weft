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
    @FocusState private var focus: Field?

    enum Field: Hashable { case title, tag }

    var body: some View {
        if let draft = store.draft(title) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    TextField("Title", text: binding(\.title))
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .semibold))
                        .focused($focus, equals: .title)
                    Spacer()
                    Button("Cancel") { withAnimation { store.cancel(title) } }
                        .keyboardShortcut(.cancelAction)
                    Button("Done") { withAnimation { store.save(title) } }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                }
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
                fields(draft)
            }
            .onAppear { if !store.exists(title) { focus = .title } }
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
            store.draft(title)![keyPath: path]
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

    private func fields(_ draft: Tiddler) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(draft.fields.filter { $0.value.text != nil }, id: \.name) { field in
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
