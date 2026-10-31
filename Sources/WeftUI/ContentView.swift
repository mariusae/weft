import SwiftUI
import WeftCore

public struct ContentView: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
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
                        .navigationSubtitle("\(store.count) pages")
                        #else
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar { RiverToolbar() }
                }
            }
        }
        .overlay(alignment: .top) {
            if store.quickOpenShown && store.root != nil {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { store.quickOpenShown = false }
                    QuickOpen().padding(.top, sizeClass == .compact ? 12 : 70)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.quickOpenShown)
        // Prism's warm ink and its accent, throughout.
        .foregroundStyle(Ink.text.color)
        .tint(Ink.accent.color)
        .onChange(of: store.focusRequest) { compactColumn = .detail }
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
            #if os(iOS)
            Button("Quick Open", systemImage: "magnifyingglass") { store.quickOpenShown = true }
                .keyboardShortcut("o")
            #endif
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

/// ⌘↩: the selected card between Edit and Preview.
private struct EditToggle: View {
    @Environment(WikiStore.self) private var store

    var body: some View {
        let title = store.focus.flatMap { store.river.contains($0) ? $0 : nil }
        let editing = title.map(store.isEditing) ?? false
        Button(editing ? "Preview" : "Edit", systemImage: editing ? "eye" : "square.and.pencil") { store.toggleEditing() }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(title == nil)
            .help(editing ? "Preview the Selected Card (⌘↩)" : "Edit the Selected Card (⌘↩)")
    }
}

/// At the foot of the river: syncing, then what it did — or, until
/// tapped, why it failed.
private struct SyncNoticeView: View {
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
        case open = "Open", recent = "Recent", wiki = "Wiki", tags = "Tags", missing = "Missing"
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

    /// Pages matching what is typed: by title or alias, then by what they say.
    private var searchResults: some View {
        titles(store.searchResults(), empty: "Nothing matches", kinds: true)
    }

    @ViewBuilder private var list: some View {
        switch tab {
        case .open: titles(store.river, empty: "No cards open", closable: true)
        case .recent: titles(store.recent(), empty: "Nothing yet", kinds: true)
        case .wiki: titles(store.wikiPages(), empty: "No wiki pages yet")
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

    private func titles(_ titles: [String], empty: String, closable: Bool = false, missing: Bool = false, kinds: Bool = false) -> some View {
        List(titles, id: \.self) { title in
            HStack {
                Button { store.open(title) } label: {
                    HStack(spacing: 7) {
                        if kinds {
                            Image(systemName: store.kind(title).symbol)
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
    /// The card at the top of the river, as it is scrolled.
    @State private var inView: String?

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
                .scrollTargetLayout()
                .animation(.snappy(duration: 0.28), value: store.river)
                .padding(.horizontal, sizeClass == .compact ? 10 : 28)
                .padding(.vertical, sizeClass == .compact ? 12 : 22)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $inView, anchor: .top)
            .onChange(of: inView) { store.cardInView = inView }
            .background(Color.river)
            #if os(macOS)
            .overlay(alignment: .trailing) {
                if store.river.count > 1 {
                    RiverRail(inView: inView ?? store.river.first) { title in
                        store.select(title)
                        withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(title, anchor: .top) }
                    }
                }
            }
            #endif
            .overlay {
                if store.isLoading {
                    ProgressView().controlSize(.large)
                } else if store.river.isEmpty {
                    Text("Open a tiddler from the sidebar, or make one with ⌘N.")
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .bottom) { SyncNoticeView().padding(.bottom, 14) }
            .onChange(of: store.focusRequest) {
                guard let focus = store.focus else { return }
                withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(focus, anchor: .top) }
            }
        }
    }
}

#if os(macOS)
/// The river at a glance, at its right edge, with the sidebar shut: a tick
/// for each open card, the one in view marked; under the pointer, their
/// titles — one clicked brought into view.
private struct RiverRail: View {
    @Environment(WikiStore.self) private var store
    let inView: String?
    let go: (String) -> Void
    @State private var hovering = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .trailing, spacing: hovering ? 1 : 6) {
                ForEach(store.river, id: \.self) { title in
                    let current = title == inView
                    Button { go(title) } label: {
                        HStack(spacing: 9) {
                            if hovering {
                                Text(store.shownTitle(title))
                                    .font(.callout.weight(current ? .semibold : .regular))
                                    .foregroundStyle(current ? Ink.text.color : Ink.secondary.color)
                                    .lineLimit(1)
                                    .frame(maxWidth: 260, alignment: .trailing)
                            }
                            Capsule()
                                .fill(current ? Ink.accent.color : Ink.faint.color.opacity(0.7))
                                .frame(width: current ? 18 : 11, height: 3)
                        }
                        .padding(.vertical, hovering ? 4 : 0)
                        .padding(.horizontal, hovering ? 6 : 0)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(hovering ? "" : store.shownTitle(title))
                }
            }
            .padding(hovering ? 10 : 8)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxHeight: 520)
        .background {
            if hovering { RoundedRectangle(cornerRadius: 14).fill(.regularMaterial).shadow(color: .black.opacity(0.12), radius: 12, y: 4) }
        }
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.18), value: hovering)
        .padding(.trailing, 8)
    }
}
#endif
