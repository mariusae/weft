import SwiftUI
import WeftCore

/// A query block, shown: what it asks, in a line, and what it finds — as a
/// list, a line of links, a table, cards, a count, or a tree of tags.
struct QueryView: View {
    @Environment(WikiStore.self) private var store
    let query: Query
    let card: String
    /// A table's columns: those the query names, or else the fields its
    /// first tag gives what it tags.
    private var columns: [String] {
        guard query.columns.isEmpty, let tag = query.tags.first else { return query.columns }
        let resolved = tag == Query.this ? card : tag
        return store.tiddler(resolved).map { FieldSpec.specs(of: $0).map(\.name) } ?? []
    }

    /// Which of the card's query blocks this is, when it can be edited in
    /// place; nil inside an embed or a quote.
    let index: Int?
    let depth: Int
    @State private var editing = false

    var body: some View {
        let titles = store.run(query, this: card)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(query.summary).lineLimit(1)
                Spacer(minLength: 8)
                if query.show != .count {
                    Text("\(titles.count)").monospacedDigit()
                }
                if let index, store.exists(card), !store.isEditing(card) {
                    Button("Edit Query") { editing = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(Ink.accent.color)
                        .popover(isPresented: $editing) {
                            QueryBuilder(query: query, card: card) { changed in
                                store.updateQuery(in: card, at: index, to: changed)
                                editing = false
                            } cancel: {
                                editing = false
                            }
                        }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            results(titles)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.accent.color.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Ink.accent.color.opacity(0.15)))
    }

    @ViewBuilder private func results(_ titles: [String]) -> some View {
        if titles.isEmpty && query.show != .count {
            Text("Nothing found").font(.callout).foregroundStyle(.tertiary)
        } else {
            switch query.show {
            case .list:
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(titles, id: \.self) { title in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(.secondary)
                            TiddlerLink(title: title)
                        }
                    }
                }
            case .inline:
                FlowLayout(spacing: 4) {
                    ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                        HStack(spacing: 0) {
                            TiddlerLink(title: title)
                            if index < titles.count - 1 { Text(",").foregroundStyle(.secondary) }
                        }
                    }
                }
            case .count:
                Text("\(titles.count) \(titles.count == 1 ? "tiddler" : "tiddlers")")
                    .font(.title3.weight(.semibold))
            case .table:
                QueryTable(titles: titles, columns: columns)
            case .cards:
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(titles.prefix(30), id: \.self) { title in
                        QueryCard(title: title, card: card, depth: depth)
                    }
                    if titles.count > 30 {
                        Text("and \(titles.count - 30) more").font(.callout).foregroundStyle(.secondary)
                    }
                }
            case .tree:
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(titles, id: \.self) { title in
                        TagTree(title: title, level: 0, seen: [card])
                    }
                }
            }
        }
    }
}

/// A link to a tiddler, faded and slanted when there is none.
struct TiddlerLink: View {
    @Environment(WikiStore.self) private var store
    let title: String
    var shown: String?

    var body: some View {
        Link(destination: InlineMarkdown.url(for: title)) {
            Text(shown ?? title)
                .italic(!store.exists(title))
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(store.exists(title) ? Ink.accent.color : .secondary)
    }
}

private struct QueryTable: View {
    @Environment(WikiStore.self) private var store
    let titles: [String]
    let columns: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 5) {
                GridRow {
                    Text("Title")
                    ForEach(columns, id: \.self) { Text($0) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider()
                ForEach(titles, id: \.self) { title in
                    let specs = store.tiddler(title).map { store.schema(for: $0) } ?? []
                    GridRow {
                        TiddlerLink(title: title)
                        ForEach(columns, id: \.self) { column in
                            if let spec = specs.first(where: { $0.name == column }) {
                                TypedValue(spec: spec, text: value(column, of: title))
                            } else {
                                InlineText(text: value(column, of: title))
                            }
                        }
                    }
                }
            }
            .font(.callout)
        }
    }

    private func value(_ column: String, of title: String) -> String {
        guard let tiddler = store.tiddler(title) else { return "" }
        switch column {
        case "tags": return tiddler.tags.joined(separator: ", ")
        case "modified": return tiddler.modified?.formatted(date: .abbreviated, time: .omitted) ?? ""
        case "created": return tiddler.created?.formatted(date: .abbreviated, time: .omitted) ?? ""
        default: return tiddler[field: column]?.text ?? tiddler[field: column]?.list?.joined(separator: ", ") ?? ""
        }
    }
}

private struct QueryCard: View {
    @Environment(WikiStore.self) private var store
    let title: String
    let card: String
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TiddlerLink(title: title).font(.headline)
            if depth < 2, let tiddler = store.tiddler(title), !tiddler.text.isEmpty {
                MarkdownView(blocks: MarkdownCache.blocks(tiddler.text), card: card, depth: depth + 1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A tiddler and, folded under it, what is tagged with it: a table of contents.
private struct TagTree: View {
    @Environment(WikiStore.self) private var store
    let title: String
    let level: Int
    let seen: Set<String>
    @State private var expanded = false

    var body: some View {
        let children = level < 5 && !seen.contains(title) ? store.tagged(title) : []
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if children.isEmpty {
                    Image(systemName: "circle.fill").font(.system(size: 4)).frame(width: 14).foregroundStyle(.tertiary)
                } else {
                    Button { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .frame(width: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                TiddlerLink(title: title)
            }
            if expanded {
                ForEach(children, id: \.self) { child in
                    TagTree(title: child, level: level + 1, seen: seen.union([title]))
                        .padding(.leading, 16)
                }
            }
        }
    }
}

/// A query, as a form: which tiddlers, in what order, shown how.
struct QueryBuilder: View {
    @Environment(WikiStore.self) private var store
    @State var query: Query
    let card: String
    let done: (Query) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("Tagged", text: list(\.tags), prompt: Text("Tags, separated by commas"))
                    TextField("Not tagged", text: list(\.excludedTags), prompt: Text("Tags to leave out"))
                    TextField("Listed in", text: $query.listedIn, prompt: Text("A tiddler whose list to follow"))
                    TextField("Links to", text: $query.linksTo, prompt: Text("Tiddlers linking to this one"))
                    TextField("Linked from", text: $query.linkedFrom, prompt: Text("Tiddlers this one links to"))
                    TextField("Title has", text: $query.titleContains)
                    TextField("Text has", text: $query.textContains)
                    TextField("Has fields", text: list(\.hasFields), prompt: Text("Fields, separated by commas"))
                } header: {
                    Text("Find")
                } footer: {
                    Text("Write {this} for the tiddler this query is in.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Order") {
                    Picker("Sort by", selection: $query.sort) {
                        Text("Natural order").tag(Query.Sort.automatic)
                        Text("Title").tag(Query.Sort.title)
                        Text("Created").tag(Query.Sort.created)
                        Text("Modified").tag(Query.Sort.modified)
                    }
                    Toggle("Reversed", isOn: $query.descending)
                    TextField("At most", text: Binding(
                        get: { query.limit.map(String.init) ?? "" },
                        set: { query.limit = Int($0.trimmingCharacters(in: .whitespaces)) }
                    ), prompt: Text("No limit"))
                }
                Section("Show") {
                    Picker("As", selection: $query.show) {
                        ForEach(Query.Display.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    if query.show == .table {
                        TextField("Columns", text: list(\.columns), prompt: Text("Fields, separated by commas"))
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Text("Finds \(store.run(query, this: card).count)").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Done") { done(query) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 520)
    }

    /// A list of words as one field, separated by commas.
    private func list(_ path: WritableKeyPath<Query, [String]>) -> Binding<String> {
        Binding {
            query[keyPath: path].joined(separator: ", ")
        } set: { text in
            query[keyPath: path] = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }
}
