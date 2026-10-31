import SwiftUI
import WeftCore

public struct ContentView: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    /// On the iPhone, where the sidebar and the river take turns: which shows.
    @State private var compactColumn = NavigationSplitViewColumn.detail

    public init() {}

    public var body: some View {
        @Bindable var store = store
        Group {
            if store.root == nil {
                Welcome()
            } else {
                NavigationSplitView(preferredCompactColumn: $compactColumn) {
                    Sidebar()
                        .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 400)
                } detail: {
                    River()
                        .navigationTitle(store.graphName)
                        #if os(macOS)
                        .navigationSubtitle("\(store.count) tiddlers")
                        #else
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar { RiverToolbar() }
                }
            }
        }
        .onChange(of: store.focusRequest) { compactColumn = .detail }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.activated() }
        }
        .alert("Weft", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
    }
}

/// Above the river: tiddlers to review, the sync, a new tiddler, closing every card.
private struct RiverToolbar: ToolbarContent {
    @Environment(WikiStore.self) private var store

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            let conflicts = store.conflicted()
            if !conflicts.isEmpty {
                Button {
                    store.openConflicts()
                } label: {
                    Label("\(conflicts.count) to Review", systemImage: "exclamationmark.triangle")
                        .labelStyle(.titleAndIcon)
                }
                .tint(.orange)
                .help("Tiddlers changed on two devices")
            }
            if let sync = store.sync { SyncButton(sync: sync) }
            EditToggle()
            Button("Today", systemImage: "calendar") { store.openToday() }
                .help("Today's Note (⌘T)")
            Button("New Tiddler", systemImage: "plus") { store.newTiddler() }
                .help("New Tiddler (⌘N)")
            Button("Close All", systemImage: "rectangle.stack.badge.minus") { store.closeAll() }
                .help("Close All Cards (⇧⌘W)")
        }
    }
}

/// ⌘↩: the selected card from reading to editing, and while it is edited,
/// between its editor and a preview.
private struct EditToggle: View {
    @Environment(WikiStore.self) private var store

    var body: some View {
        let title = store.focus.flatMap { store.river.contains($0) ? $0 : nil }
        let editing = title.map(store.isEditing) ?? false
        let previewing = title.map(store.isPreviewing) ?? false
        Button(editing && !previewing ? "Preview" : "Edit",
               systemImage: editing && !previewing ? "eye" : "pencil") { store.toggleEditing() }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(title == nil || (!editing && store.note(title!) != nil))
            .help(editing && !previewing ? "Preview the Card Being Edited (⌘↩)" : "Edit the Selected Card (⌘↩)")
    }
}

/// How syncing is going, and a sync now.
private struct SyncButton: View {
    @Environment(WikiStore.self) private var store
    let sync: WikiSync

    var body: some View {
        Button {
            if case .failed(let message) = sync.status { store.error = "The last sync failed: \(message)" }
            sync.sync()
        } label: {
            Label("Sync", systemImage: symbol)
                .symbolEffect(.rotate, isActive: sync.status == .syncing)
        }
        .tint(isFailed ? .orange : nil)
        .help(help)
    }

    private var isFailed: Bool {
        if case .failed = sync.status { return true }
        return false
    }

    private var symbol: String {
        isFailed ? "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90" : "arrow.triangle.2.circlepath"
    }

    private var help: String {
        switch sync.status {
        case .idle: "Sync Now (⌘R)"
        case .syncing: "Syncing…"
        case .synced(let date): "Synced \(date.formatted(.relative(presentation: .named))). Sync Now (⌘R)"
        case .failed(let message): "The last sync failed: \(message)"
        }
    }
}

private struct Welcome: View {
    @Environment(WikiStore.self) private var store

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Weft").font(.largeTitle.weight(.semibold))
            Text("Open a Reflect graph. Weft keeps its tiddlers in the graph's wiki/ folder.")
                .foregroundStyle(.secondary)
            Button("Open Graph…") { store.chooseGraph() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: The sidebar

private struct Sidebar: View {
    @Environment(WikiStore.self) private var store
    @FocusState private var searchFocused: Bool
    @State private var tab: Tab = .open

    enum Tab: String, CaseIterable {
        case open = "Open", recent = "Recent", tags = "Tags", missing = "Missing"
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $store.search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = store.searchResults(limit: 1).first { store.open(first) }
                    }
                if !store.search.isEmpty {
                    Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .top], 10)
            .padding(.bottom, 6)

            if store.search.trimmingCharacters(in: .whitespaces).isEmpty {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                list
            } else {
                searchResults
            }
        }
        .onChange(of: store.searchFocusRequest) { searchFocused = true }
    }

    /// Tiddlers matching what is typed, then Reflect notes.
    private var searchResults: some View {
        let tiddlers = store.searchResults()
        let notes = store.noteResults().filter { !tiddlers.contains($0.title) }
        return List {
            if !tiddlers.isEmpty {
                SwiftUI.Section("Tiddlers") {
                    ForEach(tiddlers, id: \.self) { title in
                        Button { store.open(title) } label: {
                            Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !notes.isEmpty {
                SwiftUI.Section("Reflect") {
                    ForEach(notes, id: \.path) { note in
                        Button { store.open(note.title) } label: {
                            Label(note.displayTitle, systemImage: note.day != nil ? "calendar" : "doc.text")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay {
            if tiddlers.isEmpty && notes.isEmpty { Text("Nothing matches").foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private var list: some View {
        switch tab {
        case .open: titles(store.river, empty: "No cards open", closable: true)
        case .recent: titles(store.recent(), empty: "Nothing yet")
        case .missing: titles(store.missing(), empty: "No links to missing tiddlers", missing: true)
        case .tags:
            List(store.tags(), id: \.tag) { item in
                Button { store.open(item.tag) } label: {
                    HStack {
                        TagPill(tag: item.tag)
                        Spacer()
                        Text("\(item.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func titles(_ titles: [String], empty: String, closable: Bool = false, missing: Bool = false) -> some View {
        List(titles, id: \.self) { title in
            HStack {
                Button { store.open(title) } label: {
                    Text(missing ? title : store.note(title)?.displayTitle ?? title)
                        .italic(missing)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if closable {
                    Button { withAnimation { store.close(title) } } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help("Close")
                }
            }
        }
        .overlay {
            if titles.isEmpty { Text(empty).foregroundStyle(.secondary) }
        }
    }
}

// MARK: The river

private struct River: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(store.river, id: \.self) { title in
                        Card(title: title)
                            .id(title)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                    removal: .opacity.combined(with: .scale(scale: 0.97))))
                    }
                }
                .animation(.snappy(duration: 0.28), value: store.river)
                .padding(.horizontal, sizeClass == .compact ? 10 : 28)
                .padding(.vertical, sizeClass == .compact ? 12 : 22)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .background(Color.river)
            .overlay {
                if store.river.isEmpty {
                    Text("Open a tiddler from the sidebar, or make one with ⌘N.")
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: store.focusRequest) {
                guard let focus = store.focus else { return }
                withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(focus, anchor: .top) }
            }
        }
    }
}
