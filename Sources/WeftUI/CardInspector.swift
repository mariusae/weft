#if os(macOS)
import ReflectCore
import SwiftUI
import WeftCore

/// Beside the river, the selected card's own: what it is and where it is
/// filed — a thing to do, pinned, in the inbox, the wiki's; its home river,
/// its icon, its tags; how it is written; what it is related to, the
/// rivers it is in and what links to it — each changed where it is shown,
/// not from a menu.
struct CardInspector: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    let title: String
    @State private var newTag = ""
    @State private var choosingIcon = false
    @State private var historyShown = false

    var body: some View {
        let page = store.draftHead(title) ?? store.tiddler(title)
        let filed = page != nil && store.kind(title) != .day && !store.isShadow(title)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if filed {
                    group {
                        row("To-Do", store.taskState(title) == .done ? "checkmark.circle" : "circle") {
                            Picker("To-Do", selection: Binding(get: { store.taskState(title) }, set: { state in
                                withAnimation(.snappy(duration: 0.2)) { store.setTaskState(title, state) }
                            })) {
                                Text("No").tag(Tiddler.TaskState?.none)
                                Text("To Do").tag(Tiddler.TaskState?.some(.todo))
                                Text("Done").tag(Tiddler.TaskState?.some(.done))
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .fixedSize()
                            .controlSize(.small)
                        }
                        toggle("Pinned", "pin", Binding(get: { store.isPinned(title) }, set: { store.setPinned(title, $0) }))
                        toggle("In the Inbox", "tray", Binding(get: { store.isInInbox(title) }, set: { store.setInbox(title, $0) }))
                        toggle("In the Wiki", "book.closed", Binding(get: { store.draftHead(title)?.isWiki ?? store.isWiki(title) },
                                                                      set: { store.setWiki(title, $0) }))
                    }
                    group("Filed") {
                        homeRiver
                        tags(page?.tags ?? [])
                    }
                }
                group("Written As") {
                    Picker("Write As", selection: Binding(get: { store.editorMode(title) }, set: { store.setEditorMode($0, for: title) })) {
                        ForEach(WikiStore.EditorMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                links
                // What can be had of it, and its deleting: one to a line, quiet.
                VStack(alignment: .leading, spacing: 8) {
                    if page != nil {
                        Button("History…", systemImage: "clock.arrow.circlepath") { historyShown = true }
                    }
                    if Platform.canReveal, let path = store.path(of: title) {
                        Button("Show in Finder", systemImage: "folder") { Platform.reveal(path) }
                    }
                    if page != nil, !store.isShadow(title) {
                        Button("Delete", systemImage: "trash", role: .destructive) { withAnimation { store.delete(title) } }
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(.borderless)
                .pointing()
            }
            .padding(16)
            // As wide as the column: what is in it wraps or is cut short, not the column.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Ink.paper.color)
        .sheet(isPresented: $historyShown) { HistorySheet(title: title).environment(store) }
    }

    /// A group of what is shown, under its name, if it has one.
    private func group<Content: View>(_ name: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.secondary.color)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A row that is on or off: its icon, its name, its switch at the end.
    private func toggle(_ name: String, _ symbol: String, _ on: Binding<Bool>) -> some View {
        row(name, symbol) {
            Toggle(name, isOn: on)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    /// A row: its icon in a column of its own, so that names line up; its
    /// name; what changes it, at the end.
    private func row<Trailing: View>(_ name: String, _ symbol: String, @ViewBuilder _ trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(Ink.secondary.color)
                .frame(width: 18)
            Text(name)
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 22)
    }

    // MARK: Its parts

    /// Its icon — a click away from another — and its name, which a click
    /// on Rename puts the caret in, in its card.
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { if !store.isShadow(title) { choosingIcon = true } } label: {
                Image(systemName: store.icon(of: title) ?? store.symbol(of: title))
                    .font(.system(size: 18))
                    .foregroundStyle(store.icon(of: title) == nil ? Ink.secondary.color : Ink.accent.color)
                    .frame(width: 32, height: 32)
                    .background(Ink.text.color.opacity(0.06), in: RoundedRectangle(cornerRadius: Measures.controlRadius + 2))
            }
            .buttonStyle(.plain)
            .pointing()
            .help("Choose an icon")
            .popover(isPresented: $choosingIcon) {
                IconPicker(current: store.icon(of: title)) { symbol in
                    store.setIcon(symbol, of: title)
                    choosingIcon = false
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(store.shownTitle(title))
                    .font(.system(size: 15, weight: .semibold, design: TextSettings.design))
                    .lineLimit(2)
                Text(kindLine)
                    .font(.caption)
                    .foregroundStyle(Ink.secondary.color)
            }
            Spacer(minLength: 0)
            if store.kind(title) != .day, !store.isShadow(title) {
                Button("Rename") { river.edit(title, inTitle: true) }
                    .buttonStyle(.borderless)
                    .pointing()
            }
        }
    }

    /// What kind of page it is, and when it was last written.
    private var kindLine: String {
        let kind: String = switch store.kind(title) {
        case .day: "A day"
        case .wiki: "A wiki page"
        default: Untitled.isName(title) ? "An untitled page" : "A page"
        }
        guard let modified = store.tiddler(title)?.modified else { return kind }
        return kind + " · written " + modified.formatted(.relative(presentation: .named))
    }

    /// The saved river it calls its home: chosen from those saved, or by typing.
    private var homeRiver: some View {
        let home = store.homeRiver(of: title)
        return row("Home River", RiverLink.symbol) {
            Menu(home ?? "None") {
                Button("Choose…") { river.homing = title }
                Divider()
                ForEach(store.savedRivers(), id: \.self) { name in
                    Toggle(name, isOn: Binding(get: { home == name }, set: { store.setHomeRiver($0 ? name : nil, of: title) }))
                }
                if home != nil {
                    Divider()
                    Button("None") { store.setHomeRiver(nil, of: title) }
                }
            }
            .fixedSize()
            .controlSize(.small)
        }
    }

    /// Its tags, each taken off by its ×, and a field for another.
    private func tags(_ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Tags", "tag") { EmptyView() }
            VStack(alignment: .leading, spacing: 6) {
                if !tags.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 3) {
                                Button { river.open(tag, from: title) } label: { TagPill(tag: tag) }
                                    .buttonStyle(.plain)
                                    .pointing()
                                Button {
                                    store.change(title) { $0.tags.removeAll { $0 == tag } }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .pointing()
                                .foregroundStyle(Ink.secondary.color)
                                .help("Remove the tag “\(tag)”")
                            }
                        }
                    }
                }
                TextField("Add a tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onSubmit { addTag() }
            }
        }
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        newTag = ""
        guard !tag.isEmpty, !((store.draft(title) ?? store.tiddler(title))?.tags.contains(tag) ?? false) else { return }
        store.change(title) { $0.tags.append(tag) }
    }

    /// What it is related to, the rivers it is a card of, and what links to
    /// it — each opened, or brought back, by a click.
    @ViewBuilder private var links: some View {
        let related = store.related(of: title)
        if !related.isEmpty {
            group("Related") {
                ForEach(related, id: \.title) { page in
                    pageRow(page.title)
                }
            }
        }
        let rivers = store.rivers(holding: title).filter { $0 != river.name }
        if !rivers.isEmpty {
            group("In Rivers") {
                ForEach(rivers, id: \.self) { name in
                    Button { river.follow(river: name) } label: {
                        row(name, store.savedRiverIcon(name) ?? "square.stack") { EmptyView() }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointing()
                }
            }
        }
        let backlinks = store.backlinks(of: title)
        if !backlinks.isEmpty {
            group(backlinks.count == 1 ? "1 Link Here" : "\(backlinks.count) Links Here") {
                ForEach(backlinks.prefix(30), id: \.title) { link in
                    Button { river.open(link.title, from: title) } label: {
                        row(link.shown, link.symbol) { EmptyView() }
                            .lineLimit(1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointing()
                }
            }
        }
    }

    private func pageRow(_ page: String) -> some View {
        Button { river.open(page, from: title) } label: {
            row(store.shownTitle(page), store.symbol(of: page)) { EmptyView() }
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointing()
    }
}
#endif
