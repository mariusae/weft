import PrismCore
import ReflectCore
import SwiftUI
import WeftCore

public struct ContentView: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    @Environment(\.undoManager) private var undoManager
    /// The phone's rivers, one shown at a time; on the Mac each is a tab.
    @Environment(RiverSet.self) private var riverSet: RiverSet?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// On the iPhone, where the sidebar and the river take turns: which shows.
    @State private var compactColumn = NavigationSplitViewColumn.detail

    /// A tab moved to a window of its own: opened by the app, which knows its windows.
    let moveToWindow: (River) -> Void

    public init(moveToWindow: @escaping (River) -> Void = { _ in }) {
        self.moveToWindow = moveToWindow
    }

    #if os(macOS)
    /// How wide the window is, and the river's column in it: what the tabs
    /// may have of the title bar.
    @State private var windowWidth: CGFloat = 900
    @State private var detailWidth: CGFloat = 900
    /// What the toolbar keeps besides: its own spacing round its items.
    static let tabSlack: CGFloat = 8

    /// The title bar's room for tabs: the river's column, less the window's
    /// buttons and the sidebar's at its left — while the sidebar is shut —
    /// and the toolbar's buttons at its right, each as the toolbar shows it.
    private var tabRoom: CGFloat {
        let sidebarShut = detailWidth > windowWidth - 40
        let left: CGFloat = (sidebarShut ? 150 : 24) + Self.tabSlack
        var buttons: CGFloat = 4
        if store.sync != nil { buttons += 1 }
        let review: CGFloat = store.conflicted().isEmpty ? 0 : 130
        let right = buttons * 38 + 30 + review
        return max(TabLayout.shownMin + 2 * TabLayout.bunched, detailWidth - left - right)
    }

    private var hasTabs: Bool { (riverSet?.rivers.count ?? 0) > 1 }

    private var graphLine: String {
        store.isLoading || store.sync != nil ? "\(store.graphName) · \(store.count) pages" : "\(store.graphName) · \(store.count) pages · not synced"
    }
    #endif

    public var body: some View {
        Group {
            if store.root == nil {
                Welcome()
            } else {
                NavigationSplitView(preferredCompactColumn: $compactColumn) {
                    Sidebar()
                        .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 400)
                        #if os(iOS)
                        // On the iPhone, back to the river without opening a card.
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            if sizeClass == .compact {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button { compactColumn = .detail } label: {
                                        HStack(spacing: 4) {
                                            Text(river.title).lineLimit(1)
                                            Image(systemName: "chevron.forward").fontWeight(.semibold)
                                        }
                                    }
                                    .accessibilityLabel("Back to \(river.title)")
                                }
                            }
                        }
                        #endif
                } detail: {
                    KeptRivers(showSidebar: sizeClass == .compact ? { compactColumn = .sidebar } : nil)
                        #if os(macOS)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
                        #endif
                        #if os(macOS)
                        // A card's pages read beside the river.
                        .inspector(isPresented: Binding(get: { river.reading != nil }, set: { if !$0 { river.reading = nil } })) {
                            if let reading = river.reading {
                                ReaderPanel(title: reading)
                                    .inspectorColumnWidth(min: 360, ideal: 520, max: 900)
                            }
                        }
                        #else
                        // Over it, on the phone and the iPad.
                        .sheet(isPresented: Binding(get: { river.reading != nil }, set: { if !$0 { river.reading = nil } })) {
                            if let reading = river.reading {
                                ReaderPanel(title: reading)
                                    .environment(store)
                                    .environment(river)
                                    .presentationDetents([.large])
                            }
                        }
                        #endif
                        #if os(macOS)
                        // One river: called by it, the graph under it. More: their
                        // tabs in the title bar, as Safari's, the one shown the title.
                        .navigationTitle(hasTabs ? "" : river.title)
                        // A folder in no repository is not synced: said, as Sync Now
                        // greyed out alone would not.
                        .navigationSubtitle(hasTabs ? "" : graphLine)
                        // The tabs stand as the title: none kept room for besides.
                        .toolbar(removing: hasTabs ? .title : nil)
                        .toolbar {
                            if hasTabs, let riverSet {
                                // At the leading edge, after the sidebar's button, as Safari's.
                                ToolbarItem(placement: .navigation) {
                                    // All the room the toolbar's buttons leave: they keep
                                    // theirs, the tabs bunching to make do with the rest.
                                    RiverTabs(rivers: riverSet, width: tabRoom, moveToWindow: moveToWindow)
                                }
                            }
                        }
                        #else
                        // Which river it is, the bar at its foot says; on the
                        // phone, glass controls float over it in place of a bar.
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(sizeClass == .compact ? .hidden : .automatic, for: .navigationBar)
                        #endif
                        .toolbar { RiverToolbar() }
                }
            }
        }
        #if os(macOS)
        // Over the river, as Prism's Go to is: a click outside it puts it away.
        .overlay(alignment: .top) {
            if river.quickOpenShown && store.root != nil {
                ZStack(alignment: .top) {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { river.quickOpenShown = false }
                    QuickOpen().padding(.top, 12)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: river.quickOpenShown)
        #else
        // On the phone, the start page, as Safari's; else a sheet, as Prism's Go to is.
        .fullScreenCover(isPresented: Binding(get: { river.quickOpenShown && store.root != nil && sizeClass == .compact },
                                              set: { river.quickOpenShown = $0 })) {
            StartPage(rivers: riverSet)
                .environment(store)
                .environment(river)
        }
        .sheet(isPresented: Binding(get: { river.quickOpenShown && store.root != nil && sizeClass != .compact }, set: { river.quickOpenShown = $0 })) {
            QuickOpen()
                .environment(store)
                .environment(river)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Ink.paper.color)
        }
        #endif
        .sheet(isPresented: Binding(get: { river.deletedShown }, set: { river.deletedShown = $0 })) {
            DeletedPagesSheet().environment(store).environment(river)
        }
        .sheet(isPresented: Binding(get: { river.choosingIcon }, set: { river.choosingIcon = $0 })) {
            RiverIconSheet(name: river.name ?? river.title, current: river.icon, color: river.color) { symbol in
                river.setIcon(symbol)
            }
        }
        #if os(iOS)
        .riverNaming(river, asking: !river.riversShown)
        .sheet(isPresented: Binding(get: { river.riversShown }, set: { river.riversShown = $0 })) {
            SavedRiversSheet().environment(store).environment(river)
        }
        #else
        .riverNaming(river)
        #endif
        #if os(macOS)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        #endif
        // Prism's warm ink and its accent, throughout.
        .foregroundStyle(Ink.text.color)
        .tint(Ink.accent.color)
        .onChange(of: river.focusRequest) { compactColumn = .detail }
        // What is done to pages and cards undone with the window's undo.
        .onAppear { store.undoManager = undoManager }
        .onChange(of: undoManager) { store.undoManager = undoManager }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.activated() } else { store.saveEditing() }
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
    @Environment(River.self) private var river

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            let conflicts = store.conflicted()
            if !conflicts.isEmpty {
                Button {
                    river.openConflicts()
                } label: {
                    Label("\(conflicts.count) to Review", systemImage: "exclamationmark.triangle")
                        .labelStyle(.titleAndIcon)
                }
                .tint(.orange)
                .help("Tiddlers changed on two devices")
            }
            if let sync = store.sync { SyncButton(sync: sync) }
            #if os(iOS)
            Button("Quick Open", systemImage: "magnifyingglass") { river.quickOpenShown = true }
            #endif
            Button("Today", systemImage: "calendar") { river.openToday() }
                .help("Today's Note (⇧⌘T)")
            Button("New Tiddler", systemImage: "plus") { river.newTiddler() }
                .help("New Tiddler (⌘N)")
            Button("Close All", systemImage: "rectangle.stack.badge.minus") { river.closeAll() }
                .help("Close All Cards (⇧⌘W)")
            #if os(macOS)
            RiversButton()
            #endif
        }
    }
}

/// Every open task in the graph, as Prism's Tasks lens groups them: each
/// ticked off where it stands, or its page opened.
struct TaskList: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river

    var body: some View {
        let groups = store.taskGroups()
        let pages = store.todoPages()
        List {
            // Pages that are things to do, whole: first.
            if !pages.isEmpty {
                Section {
                    ForEach(pages, id: \.self) { title in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Button { withAnimation { store.setTaskState(title, .done) } } label: {
                                Image(systemName: "circle")
                                    .foregroundStyle(Ink.secondary.color)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Done")
                            Button { river.open(title) } label: {
                                Text(store.shownTitle(title))
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("To-Do Pages")
                }
            }
            ForEach(groups, id: \.label) { group in
                Section {
                    ForEach(group.tasks, id: \.ordinalKey) { task in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Button { withAnimation { store.setTask(task, done: true) } } label: {
                                Image(systemName: "circle")
                                    .foregroundStyle(Ink.secondary.color)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Done")
                            Button { if let title = store.title(atPath: task.notePath) { river.open(title) } } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(WikiStore.plain(task.text)).lineLimit(2)
                                    if group.kind != .note {
                                        Text(store.title(atPath: task.notePath).map(store.shownTitle) ?? task.noteTitle)
                                            .font(.caption)
                                            .foregroundStyle(Ink.secondary.color)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text(group.notePath.flatMap(store.title(atPath:)).map(store.shownTitle) ?? group.label)
                }
            }
        }
        .overlay {
            if groups.isEmpty && pages.isEmpty { Text("No open tasks").foregroundStyle(.secondary) }
        }
    }
}

/// Prism's Reading Queue: the pages saved to read, oldest first — each
/// opened with its page read beside it; done with, or put off.
struct ReadingList: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river

    var body: some View {
        let queue = store.readingQueue()
        List(queue.titles, id: \.self) { title in
            Button {
                river.open(title)
                river.reading = title
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "doc.richtext")
                        .font(.caption)
                        .foregroundStyle(Ink.secondary.color)
                        .frame(width: 16)
                    Text(store.shownTitle(title)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button("Done", systemImage: "checkmark") { store.finishReading(title) }.tint(.green)
                Button("Later", systemImage: "clock") { store.finishReading(title, snooze: .tomorrow) }.tint(.orange)
            }
            .contextMenu {
                Button("Done", systemImage: "checkmark") { store.finishReading(title) }
                Menu("Later") {
                    ForEach(ReadingQueue.Snooze.allCases, id: \.self) { snooze in
                        Button(snooze.title, systemImage: snooze.symbol) { store.finishReading(title, snooze: snooze) }
                    }
                }
            }
        }
        .overlay {
            if queue.titles.isEmpty {
                VStack(spacing: 4) {
                    Text("All read").foregroundStyle(.secondary)
                    if store.linkNotes == nil { Text("Reading the graph…").font(.caption).foregroundStyle(.tertiary) }
                    else { Text(ReadingQueue.restDetail(next: queue.next)).font(.caption).foregroundStyle(.tertiary) }
                }
            }
        }
    }
}

extension NoteTask {
    /// Which task it is: its page, and its place among the page's tasks.
    var ordinalKey: String { "\(notePath)#\(ordinal)" }
}

/// At the foot of the river, a moment after something is done that typing
/// can't undo — a page deleted, cards closed, a tag taken off: Undo.
struct UndoOfferView: View {
    @Environment(WikiStore.self) private var store

    var body: some View {
        Group {
            if let offer = store.undoOffer {
                HStack(spacing: 12) {
                    Text(offer)
                        .lineLimit(1)
                        .foregroundStyle(Ink.secondary.color)
                    Button("Undo") { withAnimation(.snappy) { store.takeUndoOffer() } }
                        .fontWeight(.semibold)
                        .buttonStyle(.plain)
                        .foregroundStyle(Ink.accent.color)
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: store.undoOffer)
    }
}

/// At the foot of the river: syncing, then what it did — or, until
/// tapped, why it failed.
struct SyncNoticeView: View {
    @Environment(WikiStore.self) private var store
    @State private var detailsShown = false

    var body: some View {
        Group {
            switch store.syncNotice {
            case .syncing:
                capsule {
                    ProgressView().controlSize(.small)
                    Text("Syncing…")
                }
            case .done(let said):
                capsule {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(said)
                }
            case .failed(let message):
                Button { detailsShown = true } label: {
                    capsule {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Couldn't sync")
                        Text("Details").foregroundStyle(Ink.accent.color)
                    }
                }
                .buttonStyle(.plain)
                .alert("Couldn't sync", isPresented: $detailsShown) {
                    Button("Try Again") { store.syncNow() }
                    Button("OK", role: .cancel) { store.dismissSyncNotice() }
                } message: {
                    Text(message)
                }
            case nil:
                EmptyView()
            }
        }
        .animation(.snappy(duration: 0.25), value: store.syncNotice)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func capsule<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// How syncing is going, and a sync now.
private struct SyncButton: View {
    @Environment(WikiStore.self) private var store
    let sync: WikiSync

    var body: some View {
        Button {
            store.syncNow()
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
            Text("Open a Reflect graph. Weft keeps its tiddlers in it, beside your notes and days.")
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
    @Environment(River.self) private var river
    @FocusState private var searchFocused: Bool
    @State private var tab: Tab = .open

    enum Tab: String, CaseIterable {
        case open = "Open", recent = "Recent", inbox = "Inbox", reading = "Reading", tasks = "Tasks", pinned = "Pinned",
             wiki = "Wiki", tags = "Tags", missing = "Missing"
    }

    var body: some View {
        @Bindable var river = river
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $river.search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = store.searchResults(river.search, limit: 1).first { river.open(first) }
                    }
                if !river.search.isEmpty {
                    Button { river.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .top], 10)
            .padding(.bottom, 6)

            if river.search.trimmingCharacters(in: .whitespaces).isEmpty {
                // More than a segmented control holds: a row of them, scrolled.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Tab.allCases, id: \.self) { item in
                            Button { tab = item } label: {
                                Text(item.rawValue)
                                    .font(.callout.weight(tab == item ? .semibold : .regular))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(tab == item ? Ink.text.color : Ink.secondary.color)
                                    .background(tab == item ? Ink.accent.color.opacity(0.14) : .clear, in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .padding(.bottom, 6)
                list
            } else {
                searchResults
            }
        }
        .onChange(of: river.searchFocusRequest) { searchFocused = true }
    }

    /// Pages matching what is typed: by title or alias, then by what they
    /// say — the line it is in under each, what was typed marked.
    private var searchResults: some View {
        let query = river.search.trimmingCharacters(in: .whitespaces)
        let found = store.searchResults(query)
        return List(found, id: \.self) { title in
            Button { river.open(title) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: store.symbol(of: title))
                        .font(.caption)
                        .foregroundStyle(Ink.secondary.color)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.marked(store.shownTitle(title), query))
                            .lineLimit(1)
                        if let snippet = store.searchSnippet(for: title, matching: query) {
                            Text(Self.marked(snippet, query))
                                .font(.caption)
                                .foregroundStyle(Ink.secondary.color)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if found.isEmpty { Text("Nothing matches").foregroundStyle(.secondary) }
        }
    }

    /// Words with what was searched for marked in them.
    private static func marked(_ words: String, _ query: String) -> AttributedString {
        var marked = AttributedString(words)
        guard !query.isEmpty else { return marked }
        var rest = marked.startIndex..<marked.endIndex
        while let found = marked[rest].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            marked[found].backgroundColor = Ink.accent.color.opacity(0.18)
            marked[found].foregroundColor = Ink.text.color
            rest = found.upperBound..<marked.endIndex
        }
        return marked
    }

    @ViewBuilder private var list: some View {
        switch tab {
        case .open: titles(river.cards, empty: "No cards open", closable: true)
        case .recent: titles(store.recent(), empty: "Nothing yet", kinds: true)
        case .inbox: titles(store.inbox(), empty: "Nothing in the inbox", kinds: true)
        case .pinned: titles(store.pinned(), empty: "Pin a page from its card's menu", kinds: true)
        case .tasks: TaskList()
        case .reading: ReadingList()
        case .wiki: titles(store.wikiPages(), empty: "No wiki pages yet")
        case .missing: titles(store.missing(), empty: "No links to missing tiddlers", missing: true)
        case .tags:
            List(store.tags(), id: \.tag) { item in
                Button { river.open(item.tag) } label: {
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

    private func titles(_ titles: [String], empty: String, closable: Bool = false, missing: Bool = false, kinds: Bool = false) -> some View {
        List(titles, id: \.self) { title in
            HStack {
                Button { river.open(title) } label: {
                    HStack(spacing: 7) {
                        if kinds {
                            Image(systemName: store.symbol(of: title))
                                .font(.caption)
                                .foregroundStyle(Ink.secondary.color)
                                .frame(width: 16)
                        }
                        Text(missing ? title : store.shownTitle(title))
                            .italic(missing)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if closable {
                    Button { withAnimation { river.close(title) } } label: { Image(systemName: "xmark") }
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

/// Every tab's river kept as it was: a tab shows at once, scrolled as it
/// was left. On the phone, the one river.
private struct KeptRivers: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    @Environment(RiverSet.self) private var riverSet: RiverSet?
    var showSidebar: (() -> Void)?

    var body: some View {
        #if os(macOS)
        KeptRiverViews(store: store, rivers: riverSet?.rivers ?? [river], shown: river, riverSet: riverSet)
        #else
        if showSidebar != nil, let riverSet {
            // On the phone: the river shrinking into the overview of them all, as Safari's page does.
            PhoneRivers(rivers: riverSet, showSidebar: showSidebar)
        } else {
            RiverColumn(showSidebar: showSidebar)
                // Its scroll and the card in view, each river's own.
                .id(river.id)
        }
        #endif
    }
}

#if os(macOS)
/// Each tab's river in a view of its own, kept as it was, and only the one
/// shown in the window: what changes over the rivers as another is shown
/// is not looked through by every card in them, nor are hidden ones laid out.
private struct KeptRiverViews: NSViewRepresentable {
    let store: WikiStore
    let rivers: [River]
    let shown: River
    let riverSet: RiverSet?

    final class Host: NSView {
        var kept: [UUID: NSHostingView<AnyView>] = [:]
        var current: NSHostingView<AnyView>?
    }

    func makeNSView(context: Context) -> Host { Host() }

    func updateNSView(_ host: Host, context: Context) {
        let open = Set(rivers.map(\.id))
        for (id, view) in host.kept where !open.contains(id) {
            view.removeFromSuperview()
            host.kept[id] = nil
        }
        let view = host.kept[shown.id] ?? {
            let view = NSHostingView(rootView: AnyView(RiverColumn().environment(store).environment(shown).environment(riverSet)))
            // As big as it is given.
            view.sizingOptions = []
            view.autoresizingMask = [.width, .height]
            host.kept[shown.id] = view
            return view
        }()
        guard view !== host.current else { return }
        if let left = host.current {
            // The caret out of the tab left, as it was when its river was made anew.
            if let window = host.window, let responder = window.firstResponder as? NSView, responder.isDescendant(of: left) {
                window.makeFirstResponder(nil)
            }
            left.removeFromSuperview()
        }
        view.frame = host.bounds
        host.addSubview(view)
        host.current = view
    }
}
#endif

#if os(iOS)
/// The phone's river, and under it — shown as it shrinks away — the
/// overview of them all: as Safari's page does, the river drawn smaller,
/// its corners rounding, into its own tile, the others coming into focus
/// round it; a tile chosen, that river growing out of it to fill the screen.
private struct PhoneRivers: View {
    @Environment(River.self) private var river
    let rivers: RiverSet
    let showSidebar: (() -> Void)?
    /// How far into its tile the river is: 0 filling the screen, 1 its tile's size.
    @State private var progress: CGFloat = 0
    /// The overview there, under the river: while it is shown, and as it goes.
    @State private var mounted = false
    /// Shrunk into its tile: the tile itself showing, the river not.
    @State private var settled = false
    /// Where the river is, filling the screen.
    @State private var frame: CGRect = .zero

    private static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)

    var body: some View {
        ZStack {
            if mounted {
                RiverOverview(rivers: rivers)
                    .opacity(Double(progress))
                    .blur(radius: (1 - progress) * 10)
                    .allowsHitTesting(settled)
            }
            // The rivers side by side, as Safari's pages are: the one shown,
            // and — while it is dragged aside — those beside it, sliding in
            // with it, as paper does. Each kept by its id, so the one slid
            // in is the same view once it is the one shown.
            ForEach(shownRivers, id: \.id) { each in
                let place = CGFloat(index(of: each) - rivers.currentIndex)
                RiverColumn(showSidebar: showSidebar)
                    .environment(each)
                    .modifier(IntoTile(progress: each === river ? progress : 0, from: frame, to: tile))
                    .offset(x: place * (frame.width + Self.gutter) + rivers.swipe)
                    .opacity(each === river && settled ? 0 : 1)
                    .allowsHitTesting(each === river && progress == 0 && rivers.swipe == 0)
                    .zIndex(each === river ? 1 : 0)
            }
        }
        // Between rivers slid side by side: a shade under them, as Safari's.
        .background(Color.river.overlay(Color.black.opacity(0.08)).ignoresSafeArea())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onChange(of: rivers.overviewShown) { _, shown in shown ? open() : close() }
    }

    /// Between rivers side by side, as Safari leaves between its pages.
    static let gutter: CGFloat = 14

    /// The river shown — and, being dragged aside, those beside it.
    private var shownRivers: [River] {
        let at = rivers.currentIndex
        guard rivers.swipe != 0 else { return [river] }
        return [at - 1, at, at + 1].filter(rivers.rivers.indices.contains).map { rivers.rivers[$0] }
    }

    private func index(of each: River) -> Int { rivers.rivers.firstIndex { $0 === each } ?? rivers.currentIndex }

    /// The tile of the river shown: where it was laid out — or, a river just
    /// made, not yet there, a small card in the middle.
    private var tile: CGRect {
        if let tile = rivers.tileFrames[river.id] { return tile }
        return frame.insetBy(dx: frame.width * 0.3, dy: frame.height * 0.3)
    }

    private func open() {
        settled = false
        mounted = true
        Task { @MainActor in
            // Once the overview is laid out, its tiles where they will be.
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(Self.spring) { progress = 1 } completion: {
                guard rivers.overviewShown else { return }
                withAnimation(.easeOut(duration: 0.12)) { settled = true }
            }
        }
    }

    private func close() {
        // From the tile chosen: the river shown now grows out of it.
        settled = false
        withAnimation(Self.spring) { progress = 0 } completion: {
            guard !rivers.overviewShown else { return }
            mounted = false
        }
    }
}

/// A view drawn into a smaller card: scaled to its width, cut to its
/// height, its corners rounded, and moved to where it is — `progress` of
/// the way there.
private struct IntoTile: ViewModifier, Animatable {
    var progress: CGFloat
    let from: CGRect
    let to: CGRect

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = max(0, progress)
        let fit = from.width > 0 ? to.width / from.width : 1
        let scale = 1 + (fit - 1) * p
        // Cut to the tile's height, as seen once scaled.
        let height = from.height + (to.height / max(fit, 0.01) - from.height) * p
        let radius = 18 / max(fit, 0.01) * p
        content
            .clipShape(TopCard(height: height, radius: radius, cuts: p > 0.001))
            // Lifted off what is under it, as a card is, while it moves.
            .overlay {
                TopCard(height: height, radius: radius, cuts: p > 0.001)
                    .stroke(Ink.rule.color.opacity(Double(p)), lineWidth: 1 / max(scale, 0.01))
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.18 * Double(min(1, p * 3))), radius: 24 * p, y: 8 * p)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: (to.minX - from.minX) * p, y: (to.minY - from.minY) * p)
    }
}

/// The top of a view, so high, its corners rounded — or, not cutting,
/// all of it and more.
private struct TopCard: Shape {
    var height: CGFloat
    var radius: CGFloat
    var cuts: Bool

    func path(in rect: CGRect) -> Path {
        guard cuts else { return Path(rect.insetBy(dx: -4000, dy: -4000)) }
        return Path(roundedRect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(height, rect.height)),
                    cornerRadius: radius, style: .continuous)
    }
}
#endif

private struct RiverColumn: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    @Environment(RiverSet.self) private var riverSet: RiverSet?
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// On the iPhone: back to the sidebar, from the glass over the river.
    var showSidebar: (() -> Void)?
    /// The card at the top of the river, as it is scrolled.
    @State private var inView: String?
    /// Read down into the river: the controls over it out of the way, the
    /// bar at its foot gathered to the river's name — as Prism does.
    @State private var tucked = false
    #if os(iOS)
    @State private var scrolling = ScrollFollower()
    /// The keys up — for a card, or a find bar, or anything else.
    @State private var keysUp = false
    #endif
    /// Where a card being dragged would be dropped.
    @State private var drop: CardDrop?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if river.isQuery { QueryRiverHeader().padding(.bottom, 16) }
                    ForEach(river.cards, id: \.self) { title in
                        // Peeking cards closer together: a list to glance down, still of cards.
                        let gap: CGFloat = river.isFolded(title) ? 11 : 22
                        DroppableCard(title: title, drop: $drop, gap: gap)
                            .padding(.bottom, gap)
                            .id(title)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                    removal: .opacity.combined(with: .scale(scale: 0.97))))
                    }
                }
                .scrollTargetLayout()
                .animation(.snappy(duration: 0.28), value: river.cards)
                .padding(.horizontal, sizeClass == .compact ? 10 : 28)
                .padding(.vertical, sizeClass == .compact ? 12 : 22)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $inView, anchor: .top)
            .onChange(of: inView) { river.cardInView = inView }
            #if os(iOS)
            .onScrollPhaseChange { _, phase in scrolling.byHand = phase == .interacting || phase == .decelerating }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
                if let now = scrolling.follow(y), now != tucked { tucked = now }
            }
            // Not over what is over the keys: a find bar, a card's own bar.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keysUp = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keysUp = false }
            // Pinched in, every card down to its title — the river at a
            // glance; pinched out, all open again.
            .simultaneousGesture(MagnifyGesture(minimumScaleDelta: 0.08).onEnded { value in
                if value.magnification < 0.8, !river.allFolded {
                    withAnimation(.snappy(duration: 0.3)) { river.foldAll() }
                } else if value.magnification > 1.25 {
                    withAnimation(.snappy(duration: 0.3)) { river.unfoldAll() }
                }
            })
            .sensoryFeedback(.impact(weight: .light), trigger: river.foldsVersion)
            // Pulled down, a sync — as Prism's day is.
            .refreshable { await store.syncPulled() }
            // A tick for a card moved, a lighter one for one closed.
            .sensoryFeedback(trigger: river.cards) { before, after in
                if before.count == after.count, Set(before) == Set(after) { return .impact(weight: .medium) }
                return after.count < before.count ? .impact(weight: .light) : nil
            }
            #endif
            .background(Color.river)
            // What a query river finds anew, waiting to be shown.
            .overlay(alignment: .top) {
                if river.updates > 0 {
                    Button {
                        withAnimation(.snappy(duration: 0.3)) { river.applyUpdates() }
                        if let first = river.cards.first { withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(first, anchor: .top) } }
                    } label: {
                        Label("\(river.updates) updated", systemImage: "arrow.up")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .foregroundStyle(.white)
                            .background(Ink.accent.color, in: Capsule())
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: river.updates > 0)
            .sheet(item: Binding(get: { river.queryEditor }, set: { river.queryEditor = $0 })) { ask in
                QueryRiverEditor(ask: ask).environment(store).environment(river)
            }
            #if os(macOS)
            .overlay(alignment: .trailing) {
                if river.cards.count > 1 {
                    RiverRail(inView: inView ?? river.cards.first) { title in
                        river.select(title)
                        withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(title, anchor: .top) }
                    }
                }
            }
            #endif
            .overlay {
                if store.isLoading {
                    ProgressView().controlSize(.large)
                } else if river.cards.isEmpty {
                    #if os(iOS)
                    if showSidebar != nil {
                        ContentUnavailableView {
                            Label("Nothing Open", systemImage: "rectangle.stack")
                        } description: {
                            Text("Tap the river's name below to find a page, or + to start one.")
                        }
                    } else {
                        Text("Open a tiddler from the sidebar, or make one with ⌘N.")
                            .foregroundStyle(.secondary)
                    }
                    #else
                    Text("Open a tiddler from the sidebar, or make one with ⌘N.")
                        .foregroundStyle(.secondary)
                    #endif
                }
            }
            #if os(iOS)
            // The cards scroll on under it, and their last lines up past it.
            .safeAreaInset(edge: .bottom) {
                // Not over the keys' bar while writing.
                VStack(spacing: 8) {
                    SyncNoticeView()
                    UndoOfferView()
                    if !river.isWritingAny, !keysUp {
                        // On the phone, Safari's bar; on the iPad, the rivers' switcher.
                        if showSidebar != nil {
                            PhoneBar(rivers: riverSet, tucked: tucked) { tucked = false }
                        } else if let riverSet {
                            RiverSwitcher(rivers: riverSet, small: tucked)
                        }
                    }
                }
                // As tall gathered as not: the river's room under it never
                // changes as it is scrolled — which moved what was scrolled,
                // which gathered or opened the bar again, and shook the river.
                .padding(.bottom, 4)
            }
            #endif
            .overlay(alignment: .bottom) {
                #if os(macOS)
                VStack(spacing: 8) {
                    UndoOfferView()
                    SyncNoticeView()
                }
                .padding(.bottom, 14)
                #endif
            }
            .onChange(of: river.focusRequest) {
                guard let focus = river.focus else { return }
                // Once a card just opened is among the stack's: scrolled to in
                // the change that put it there, it is not found to scroll to.
                DispatchQueue.main.async {
                    withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(focus, anchor: .top) }
                }
            }
        }
    }
}

#if os(iOS)
/// How far the river has been scrolled, and which way: kept out of what
/// views watch, as it changes with every frame of a scroll.
private final class ScrollFollower {
    var byHand = false
    private var last: CGFloat = 0
    private var travel: CGFloat = 0

    /// Scrolled down by hand some way, tucked; up a little, or near the
    /// top, not. Nil: as it was.
    func follow(_ y: CGFloat) -> Bool? {
        defer { last = y }
        if y < 40 {
            travel = 0
            return false
        }
        guard byHand else { return nil }
        let delta = y - last
        travel = (delta > 0) == (travel > 0) ? travel + delta : delta
        if travel > 24 { return true }
        if travel < -12 { return false }
        return nil
    }
}

#endif

#if os(macOS)
/// The river at a glance, at its right edge, with the sidebar shut: a tick
/// for each open card, the one in view marked; under the pointer, their
/// titles — one clicked brought into view, one dragged moved in the river,
/// a line between rows saying where. A card dragged from the river, or
/// another window's, over it opens it out, and is put where it is let go.
private struct RiverRail: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    let inView: String?
    let go: (String) -> Void
    /// `WEFT_RAIL=<title>`, for a snapshot: shown open, the pointer on that row.
    @State private var hovering = ProcessInfo.processInfo.environment["WEFT_RAIL"] != nil
    /// The row under the pointer, while the titles show.
    @State private var pointed: String? = ProcessInfo.processInfo.environment["WEFT_RAIL"]
    /// How tall its rows are.
    @State private var height: CGFloat = 0
    /// Where a card dragged over it would go. `WEFT_RAIL_DROP=<title>`, for
    /// a snapshot: just before that row.
    @State private var drop: CardDrop? = ProcessInfo.processInfo.environment["WEFT_RAIL_DROP"].map { CardDrop(title: $0, after: false) }
    /// Each row's middle, down the rail: a drop above one goes before it.
    @State private var middles: [String: CGFloat] = [:]

    /// The titles shown: under the pointer, or a card dragged over it.
    private var open: Bool { hovering || drop != nil }

    var body: some View {
        // As tall as its rows, scrolling only when they would not fit.
        ScrollView(showsIndicators: false) {
            rows.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: min(max(height, 1), 520))
        .background {
            if open { RoundedRectangle(cornerRadius: 14).fill(.regularMaterial).shadow(color: .black.opacity(0.12), radius: 12, y: 4) }
        }
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.18), value: open)
        .padding(.trailing, 8)
    }

    private var rows: some View {
        // No gap between rows while their titles show, so the pointer
        // passes from one to the next without lighting none between.
        VStack(alignment: .trailing, spacing: open ? 0 : 6) {
            // A query river's, as far as a rail can show: its first cards.
            ForEach(river.isQuery ? Array(river.cards.prefix(60)) : river.cards, id: \.self) { title in
                let current = title == inView
                let lit = hovering && pointed == title
                Button { go(title) } label: {
                    HStack(spacing: 9) {
                        if open {
                            Text(store.shownTitle(title))
                                .font(.callout.weight(current ? .semibold : .regular))
                                .foregroundStyle(current || lit ? Ink.text.color : Ink.secondary.color)
                                .lineLimit(1)
                                .frame(maxWidth: 260, alignment: .trailing)
                        }
                        // The tick's room is the same lit or not: were the
                        // row to widen under the pointer, the rail would
                        // shift, the pointer leave it, and the row narrow
                        // again — a shiver.
                        Capsule()
                            .fill(current ? Ink.accent.color : lit ? Ink.secondary.color : Ink.faint.color.opacity(0.7))
                            .frame(width: current || lit ? 18 : 11, height: 3)
                            .frame(width: 18, alignment: .trailing)
                    }
                    .padding(.vertical, open ? 5.5 : 0)
                    .padding(.horizontal, open ? 8 : 0)
                    // Each row as wide as the widest: none of the panel
                    // between rows that lights nothing.
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background {
                        if lit { RoundedRectangle(cornerRadius: 7).fill(Ink.accent.color.opacity(0.12)) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .draggingCard(title, shown: store.shownTitle(title))
                .onHover { inside in
                    if inside { pointed = title } else if pointed == title { pointed = nil }
                }
                .help(open ? "" : store.shownTitle(title))
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).midY } action: { middles[title] = $0 }
                .overlay(alignment: drop?.after == true ? .bottom : .top) {
                    if let drop, drop.title == title {
                        Capsule()
                            .fill(Ink.accent.color)
                            .frame(height: 3)
                            .padding(.horizontal, 6)
                            .offset(y: drop.after ? 1.5 : -1.5)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(8)
        .coordinateSpace(.named(Self.space))
        .onDrop(of: [.weftCard], delegate: RailDropDelegate(cards: river.cards, middles: middles, drop: $drop, river: river))
        .animation(.easeOut(duration: 0.1), value: pointed)
        .animation(.easeOut(duration: 0.1), value: drop)
    }

    private static let space = "rail"
}

/// A card dragged over the rail: before the first row whose middle is
/// below it, or after them all.
private struct RailDropDelegate: DropDelegate {
    let cards: [String]
    let middles: [String: CGFloat]
    @Binding var drop: CardDrop?
    let river: River

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.weftCard]) }

    func dropEntered(info: DropInfo) { aim(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        aim(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { drop = nil }

    func performDrop(info: DropInfo) -> Bool {
        drop = nil
        guard let place = place(info) else { return false }
        return river.moveDropped(info, to: place)
    }

    private func place(_ info: DropInfo) -> CardDrop? {
        let y = info.location.y
        if let next = cards.first(where: { (middles[$0] ?? .infinity) > y }) { return CardDrop(title: next, after: false) }
        return cards.last.map { CardDrop(title: $0, after: true) }
    }

    private func aim(_ info: DropInfo) {
        let aimed = place(info)
        if drop != aimed { drop = aimed }
    }
}
#endif

extension EnvironmentValues {
    /// What Settings shows of the GitHub account: given by the app, which
    /// knows the account.
    @Entry public var accountSettings: AnyView? = nil
}
