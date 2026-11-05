import SwiftUI
import ReflectCore
import WeftCore

/// A query river's settings, as a podcast app's playlist has them: its
/// name, icon and colour; how it sorts; what it includes, from where, and
/// what not; which tags come first or last, and how; and the cards held in
/// it by hand or taken out of it.
struct QueryRiverEditor: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    @Environment(\.dismiss) private var dismiss
    let ask: QueryEditorAsk

    @State private var name = ""
    @State private var icon = "clock"
    @State private var color = "orange"
    @State private var query = Query(text: "sort: -modified")
    @State private var from = From.all
    @State private var started = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $name, prompt: Text("Most Recent"))
                }
                Section("Icon") {
                    IconGrid(icon: $icon, color: color)
                    ColorGrid(color: $color)
                }
                Section {
                    Picker("Sort", selection: sortChoice) {
                        ForEach(SortChoice.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    NavigationLink { KindsChooser(query: $query) } label: {
                        LabeledContent("Kinds of Pages", value: KindsChooser.said(query))
                    }
                    Picker("From", selection: $from) {
                        ForEach(From.allCases) { Text($0.label).tag($0) }
                    }
                    switch from {
                    case .all: EmptyView()
                    case .tagged:
                        NavigationLink { TagsChooser(title: "Tagged", tags: $query.anyTags, ordered: false) } label: {
                            LabeledContent("Tagged", value: listed(query.anyTags, none: "Choose…"))
                        }
                    case .linking:
                        NavigationLink { PageChooser(page: $query.linksTo) } label: {
                            LabeledContent("Page", value: query.linksTo.isEmpty ? "Choose…" : store.shownTitle(query.linksTo))
                        }
                    }
                    NavigationLink { TagsChooser(title: "Excluding Tags", tags: $query.excludedTags, ordered: false) } label: {
                        LabeledContent("Excluding Tags", value: listed(query.excludedTags, none: "None"))
                    }
                    EditedSincePicker(days: $query.editedSinceDaysAgo)
                } footer: {
                    if from == .linking { Text("Pages linking to it, and pages related to it either way.") }
                }
                Section {
                    NavigationLink { TagsChooser(title: "High-Priority Tags", tags: $query.highPriority, ordered: query.priorityMode == .ranked) } label: {
                        LabeledContent("High-Priority Tags", value: listed(query.highPriority, none: "None"))
                    }
                    NavigationLink { TagsChooser(title: "Low-Priority Tags", tags: $query.lowPriority, ordered: query.priorityMode == .ranked) } label: {
                        LabeledContent("Low-Priority Tags", value: listed(query.lowPriority, none: "None"))
                    }
                    Picker("Priority Mode", selection: $query.priorityMode) {
                        Text("Ranked").tag(Query.PriorityMode.ranked)
                        Text("Grouped").tag(Query.PriorityMode.grouped)
                    }
                } footer: {
                    Text(query.priorityMode == .ranked
                         ? "Tags are ordered within each priority type. Each high- and low-priority tag has higher or lower priority than the others."
                         : "Tags can be high- or low-priority, but are not further ranked within those groups.")
                }
                if ask == .edit {
                    Section {
                        NavigationLink { HeldCards() } label: {
                            LabeledContent("Additional Tiddlers", value: "\(river.heldCards.count)")
                        }
                        NavigationLink { HiddenCards() } label: {
                            LabeledContent("Excluded Tiddlers", value: "\(river.hiddenCards.count)")
                        }
                    }
                }
                Section {
                    LabeledContent("Finds", value: count)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(ask != .edit ? "New Query River" : "Edit River")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ask != .edit ? "Create" : "Done") { finish() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 620, idealHeight: 720)
        #endif
        .onAppear(perform: start)
    }

    private var count: String {
        let found = river.count(query)
        return "\(found) \(found == 1 ? "tiddler" : "tiddlers")"
    }

    private func listed(_ tags: [String], none: String) -> String {
        tags.isEmpty ? none : tags.joined(separator: ", ")
    }

    /// What it was, to begin from: this river's own, or a new one's.
    private func start() {
        guard !started else { return }
        started = true
        if ask == .edit {
            name = river.name ?? river.title
            query = river.query ?? Query(text: "sort: -modified")
            icon = river.icon ?? icon
            color = river.color ?? color
        }
        from = !query.anyTags.isEmpty ? .tagged : !query.linksTo.isEmpty ? .linking : .all
    }

    private func finish() {
        var query = query
        // What From does not ask, not asked.
        if from != .tagged { query.anyTags = [] }
        if from != .linking { query.linksTo = "" }
        let name = name.trimmingCharacters(in: .whitespaces)
        switch ask {
        case .new:
            guard let saved = store.addQueryRiver(name, query: query, icon: icon, color: color) else { return }
            river.recall(saved)
        case .newHere:
            guard let saved = store.addQueryRiver(name, query: query, icon: icon, color: color) else { return }
            river.replace(withSaved: saved)
        case .edit:
            if river.name == nil || river.name != name { river.save(as: name) }
            river.setQuery(query, icon: icon, color: color)
        }
        dismiss()
    }

    // MARK: Choices

    enum From: String, CaseIterable, Identifiable {
        case all, tagged, linking
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "All Pages"
            case .tagged: "Tagged…"
            case .linking: "Linked or Related To…"
            }
        }
    }

    enum SortChoice: String, CaseIterable, Identifiable {
        case newestChanged, oldestChanged, newestCreated, oldestCreated, title
        var id: String { rawValue }
        var label: String {
            switch self {
            case .newestChanged: "Newest Changed"
            case .oldestChanged: "Oldest Changed"
            case .newestCreated: "Newest Created"
            case .oldestCreated: "Oldest Created"
            case .title: "Title"
            }
        }
        var sort: (Query.Sort, Bool) {
            switch self {
            case .newestChanged: (.modified, true)
            case .oldestChanged: (.modified, false)
            case .newestCreated: (.created, true)
            case .oldestCreated: (.created, false)
            case .title: (.title, false)
            }
        }
    }

    private var sortChoice: Binding<SortChoice> {
        Binding {
            SortChoice.allCases.first { $0.sort == (query.sort, query.descending) } ?? .newestChanged
        } set: {
            (query.sort, query.descending) = $0.sort
        }
    }

}

/// Which kinds of page a query finds: each — in the inbox, a thing to do,
/// done, pinned, a wiki page, a day — any, only those, or none of those.
struct KindsChooser: View {
    @Binding var query: Query

    enum Want: String, CaseIterable, Identifiable {
        case any, only, not
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any: "Any"
            case .only: "Only"
            case .not: "Not"
            }
        }
    }

    static let kinds: [Query.Flag] = [.inbox, .todo, .done, .pinned, .wiki, .note, .topic, .day, .week, .template]

    static func name(_ flag: Query.Flag) -> String {
        switch flag {
        case .inbox: "In the Inbox"
        case .todo: "Still To Do"
        case .done: "Done"
        case .pinned: "Pinned"
        case .wiki: "Wiki Pages"
        case .note: "Notes and Tiddlers"
        case .topic: "Topics"
        case .day: "Days"
        case .week: "Weeks"
        case .template: "Templates"
        }
    }

    /// What the query asks of kinds, in a few words: "Only Still To Do, not In the Inbox".
    static func said(_ query: Query) -> String {
        var parts: [String] = []
        if !query.flags.isEmpty { parts.append("Only " + query.flags.map(name).joined(separator: ", ")) }
        if !query.excludedFlags.isEmpty { parts.append("Not " + query.excludedFlags.map(name).joined(separator: ", ")) }
        return parts.isEmpty ? "All" : parts.joined(separator: "; ")
    }

    var body: some View {
        Form {
            Section {
                ForEach(Self.kinds, id: \.self) { kind in
                    Picker(Self.name(kind), selection: want(kind)) {
                        ForEach(Want.allCases) { Text($0.label).tag($0) }
                    }
                }
            } footer: {
                Text("Only: pages of every kind marked so. Not: no page of any kind marked so.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Kinds of Pages")
    }

    private func want(_ kind: Query.Flag) -> Binding<Want> {
        Binding {
            query.flags.contains(kind) ? .only : query.excludedFlags.contains(kind) ? .not : .any
        } set: { want in
            query.flags.removeAll { $0 == kind }
            query.excludedFlags.removeAll { $0 == kind }
            switch want {
            case .any: break
            case .only: query.flags.append(kind)
            case .not: query.excludedFlags.append(kind)
            }
        }
    }
}

/// How lately a page was edited, for a query to find it: since the
/// start of a day, by the calendar — the usual days back, and the query's
/// own if it is another.
struct EditedSincePicker: View {
    @Binding var days: Int?
    static let usual = [0, 1, 2, 3, 7, 14, 30, 90, 365]

    var body: some View {
        Picker("Edited", selection: $days) {
            Text("Any Time").tag(Int?.none)
            ForEach(choices, id: \.self) { Text(Self.label($0)).tag(Int?.some($0)) }
        }
    }

    private var choices: [Int] {
        guard let days, !Self.usual.contains(days) else { return Self.usual }
        return (Self.usual + [days]).sorted()
    }

    static func label(_ days: Int) -> String {
        switch days {
        case 0: "Today"
        case 1: "Since Yesterday"
        case 7: "Since a Week Ago"
        case 14: "Since 2 Weeks Ago"
        case 30: "Since a Month Ago"
        case 90: "Since 3 Months Ago"
        case 365: "Since a Year Ago"
        default: "Since \(days) Days Ago"
        }
    }
}

/// Symbols a river can show as: a few at hand — and its own, if another —
/// and the rest, by name, a step away.
private struct IconGrid: View {
    @Binding var icon: String
    let color: String
    static let icons = ["clock", "star", "flag", "bolt", "book", "lightbulb", "tray", "checkmark.circle",
                        "calendar", "folder", "tag", "heart", "briefcase", "house", "leaf", "sparkles"]

    private var shown: [String] {
        Self.icons.contains(icon) ? Self.icons : Array(Self.icons.dropLast()) + [icon]
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
            ForEach(shown, id: \.self) { name in
                Button { icon = name } label: {
                    Image(systemName: name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(icon == name ? .white : RiverColor.color(color))
                        .frame(width: 32, height: 32)
                        .background(icon == name ? RiverColor.color(color) : RiverColor.color(color).opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help(PageIcon.name(of: name))
                .accessibilityLabel(PageIcon.name(of: name))
            }
        }
        .padding(.vertical, 4)
        NavigationLink { MoreIcons(icon: $icon, color: color) } label: {
            LabeledContent("More Icons", value: PageIcon.name(of: icon))
        }
    }
}

/// Every icon on offer, by name, for a query river.
private struct MoreIcons: View {
    @Binding var icon: String
    let color: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        IconPicker(current: icon, tint: RiverColor.color(color), chosenFill: RiverColor.color(color), allowsNone: false) { symbol in
            if let symbol { icon = symbol }
            dismiss()
        }
        .navigationTitle("Icon")
    }
}

private struct ColorGrid: View {
    @Binding var color: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
            ForEach(RiverColor.names, id: \.self) { name in
                Button { color = name } label: {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(RiverColor.color(name))
                        .frame(width: 30, height: 30)
                        .overlay {
                            if color == name {
                                RoundedRectangle(cornerRadius: 9).strokeBorder(RiverColor.color(name), lineWidth: 2.5).padding(-4)
                                RoundedRectangle(cornerRadius: 6).strokeBorder(.white, lineWidth: 2).padding(1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
            }
        }
        .padding(.vertical, 6)
    }
}

/// The colours a river can be, by name.
enum RiverColor {
    static let names = ["pink", "red", "orange", "yellow", "brown", "green", "mint", "teal", "cyan", "blue", "indigo", "purple"]

    static func color(_ name: String?) -> Color {
        switch name {
        case "pink": .pink
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "brown": .brown
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "blue": .blue
        case "indigo": .indigo
        case "purple": .purple
        default: Ink.accent.color
        }
    }
}

/// Tags to choose from — the chosen first, in order when the order counts.
private struct TagsChooser: View {
    @Environment(WikiStore.self) private var store
    let title: String
    @Binding var tags: [String]
    let ordered: Bool
    @State private var search = ""

    var body: some View {
        List {
            if !tags.isEmpty {
                Section(ordered ? "Chosen, highest first" : "Chosen") {
                    ForEach(tags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                    }
                    .onMove { tags.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { tags.remove(atOffsets: $0) }
                }
            }
            Section("Tags") {
                ForEach(available, id: \.tag) { item in
                    Button {
                        if let at = tags.firstIndex(where: { $0.caseInsensitiveCompare(item.tag) == .orderedSame }) {
                            tags.remove(at: at)
                        } else {
                            tags.append(item.tag)
                        }
                    } label: {
                        HStack {
                            Text(item.tag)
                            Spacer()
                            Text("\(item.count)").foregroundStyle(.secondary)
                            Image(systemName: chosen(item.tag) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(chosen(item.tag) ? Ink.accent.color : Ink.faint.color)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .searchable(text: $search, prompt: "Find a tag")
        .navigationTitle(title)
    }

    private func chosen(_ tag: String) -> Bool { tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }

    private var available: [(tag: String, count: Int)] {
        let all = store.tags()
        guard !search.isEmpty else { return all }
        return all.filter { $0.tag.localizedCaseInsensitiveContains(search) }
    }
}

/// The cards held in the river by hand: let go, they go back where the
/// query puts them.
private struct HeldCards: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river

    var body: some View {
        List {
            if river.heldCards.isEmpty {
                Text("Cards opened in the river, or dragged into place, are held here.").foregroundStyle(.secondary)
            }
            ForEach(river.heldCards, id: \.self) { title in
                HStack {
                    Text(store.shownTitle(title))
                    Spacer()
                    Button("Release") { river.releaseToQuery(title) }
                        .buttonStyle(.borderless)
                }
            }
        }
        .navigationTitle("Additional Tiddlers")
    }
}

/// The cards taken out of the river: brought back, they are where the
/// query puts them.
private struct HiddenCards: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river

    var body: some View {
        List {
            if river.hiddenCards.isEmpty {
                Text("Cards closed in the river are kept out of it, and listed here.").foregroundStyle(.secondary)
            }
            ForEach(river.hiddenCards, id: \.self) { title in
                HStack {
                    Text(store.shownTitle(title))
                    Spacer()
                    Button("Restore") { river.restoreHidden(title) }
                        .buttonStyle(.borderless)
                }
            }
        }
        .navigationTitle("Excluded Tiddlers")
    }
}

/// A page to choose, found as it is typed: as Quick Open finds them.
private struct PageChooser: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var page: String
    @State private var search = ""

    var body: some View {
        List {
            ForEach(found, id: \.self) { target in
                Button {
                    page = target.title
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: target.symbol)
                            .foregroundStyle(Ink.accent.color)
                            .frame(width: 20)
                        Text(target.shown)
                            .lineLimit(1)
                        Spacer()
                        if target.title == page { Image(systemName: "checkmark").foregroundStyle(Ink.accent.color) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $search, prompt: "Find a page")
        .navigationTitle("Linked or Related To")
    }

    /// What is typed found — pages, days — or, with nothing typed, the
    /// pages written last; nothing that is not yet written.
    private var found: [LinkTarget] {
        store.quickOpen(search, limit: 30).filter { $0.kind != .new && $0.kind != .river }
    }
}
