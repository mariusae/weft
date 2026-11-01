import SwiftUI
import WeftCore

public struct ContentView: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    /// The phone's rivers, one shown at a time; on the Mac each is a tab.
    @Environment(RiverSet.self) private var riverSet: RiverSet?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// On the iPhone, where the sidebar and the river take turns: which shows.
    @State private var compactColumn = NavigationSplitViewColumn.detail

    public init() {}

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
                    RiverColumn(showSidebar: sizeClass == .compact ? { compactColumn = .sidebar } : nil)
                        // Its scroll and the card in view, each river's own.
                        .id(river.id)
                        #if os(macOS)
                        // Each tab called by its river.
                        .navigationTitle(river.title)
                        // A folder in no repository is not synced: said, as Sync Now
                        // greyed out alone would not.
                        .navigationSubtitle(store.isLoading || store.sync != nil
                                            ? "\(store.graphName) · \(store.count) pages" : "\(store.graphName) · \(store.count) pages · not synced")
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
        .overlay(alignment: .top) {
            if river.quickOpenShown && store.root != nil {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { river.quickOpenShown = false }
                    QuickOpen().padding(.top, sizeClass == .compact ? 12 : 70)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: river.quickOpenShown)
        #if os(iOS)
        .riverNaming(river, asking: !river.riversShown)
        .sheet(isPresented: Binding(get: { river.riversShown }, set: { river.riversShown = $0 })) {
            SavedRiversSheet().environment(store).environment(river)
        }
        #else
        .riverNaming(river)
        #endif
        // Prism's warm ink and its accent, throughout.
        .foregroundStyle(Ink.text.color)
        .tint(Ink.accent.color)
        .onChange(of: river.focusRequest) { compactColumn = .detail }
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
                .keyboardShortcut("o")
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
    @Environment(River.self) private var river
    @FocusState private var searchFocused: Bool
    @State private var tab: Tab = .open

    enum Tab: String, CaseIterable {
        case open = "Open", recent = "Recent", wiki = "Wiki", tags = "Tags", missing = "Missing"
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
        .onChange(of: river.searchFocusRequest) { searchFocused = true }
    }

    /// Pages matching what is typed: by title or alias, then by what they say.
    private var searchResults: some View {
        titles(store.searchResults(river.search), empty: "Nothing matches", kinds: true)
    }

    @ViewBuilder private var list: some View {
        switch tab {
        case .open: titles(river.cards, empty: "No cards open", closable: true)
        case .recent: titles(store.recent(), empty: "Nothing yet", kinds: true)
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
    #endif
    /// Where a card being dragged would be dropped.
    @State private var drop: CardDrop?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(river.cards, id: \.self) { title in
                        DroppableCard(title: title, drop: $drop, gap: 18)
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
            .safeAreaBar(edge: .top) {
                if let showSidebar { RiverControls(showSidebar: showSidebar, tucked: tucked) }
            }
            #endif
            .background(Color.river)
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
                    Text("Open a tiddler from the sidebar, or make one with ⌘N.")
                        .foregroundStyle(.secondary)
                }
            }
            #if os(iOS)
            // The cards scroll on under it, and their last lines up past it.
            .safeAreaInset(edge: .bottom) {
                // Not over the keys' bar while writing.
                if let riverSet, !river.isWritingAny { RiverSwitcher(rivers: riverSet, small: tucked).padding(.bottom, 4) }
            }
            #endif
            .overlay(alignment: .bottom) { SyncNoticeView().padding(.bottom, 14) }
            .onChange(of: river.focusRequest) {
                guard let focus = river.focus else { return }
                withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(focus, anchor: .top) }
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

/// Over the top of the river, on the phone, on glass: back to the sidebar,
/// and at the right what is done with the river — tucked away while it is
/// read down.
private struct RiverControls: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    let showSidebar: () -> Void
    let tucked: Bool

    var body: some View {
        HStack {
            Button(action: showSidebar) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Sidebar")
            .glassEffect(.regular.interactive(), in: .circle)
            Spacer()
            HStack(spacing: 2) {
                let conflicts = store.conflicted()
                if !conflicts.isEmpty {
                    control("\(conflicts.count) to Review", "exclamationmark.triangle") { river.openConflicts() }
                        .foregroundStyle(.orange)
                }
                if let sync = store.sync, sync.status != .idle, !isSynced(sync) { SyncButton(sync: sync).labelStyle(.iconOnly).frame(width: 44, height: 44) }
                control("Quick Open", "magnifyingglass") { river.quickOpenShown = true }
                control("Today", "calendar") { river.openToday() }
                Menu {
                    Button("New Tiddler", systemImage: "plus") { river.newTiddler() }
                    Button("Close All", systemImage: "rectangle.stack.badge.minus") { river.closeAll() }
                    if store.sync != nil {
                        Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") { store.syncNow() }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("More")
            }
            .padding(.horizontal, 6)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Ink.accent.color)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .opacity(tucked ? 0 : 1)
        .scaleEffect(tucked ? 0.92 : 1)
        .offset(y: tucked ? -12 : 0)
        .allowsHitTesting(!tucked)
        .animation(.spring(duration: 0.32, bounce: 0.14), value: tucked)
    }

    private func control(_ name: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(name)
    }

    private func isSynced(_ sync: WikiSync) -> Bool {
        if case .synced = sync.status { return true }
        return false
    }
}
#endif

#if os(macOS)
/// The river at a glance, at its right edge, with the sidebar shut: a tick
/// for each open card, the one in view marked; under the pointer, their
/// titles — one clicked brought into view.
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

    var body: some View {
        // As tall as its rows, scrolling only when they would not fit.
        ScrollView(showsIndicators: false) {
            rows.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: min(max(height, 1), 520))
        .background {
            if hovering { RoundedRectangle(cornerRadius: 14).fill(.regularMaterial).shadow(color: .black.opacity(0.12), radius: 12, y: 4) }
        }
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.18), value: hovering)
        .padding(.trailing, 8)
    }

    private var rows: some View {
        // No gap between rows while their titles show, so the pointer
        // passes from one to the next without lighting none between.
        VStack(alignment: .trailing, spacing: hovering ? 0 : 6) {
            ForEach(river.cards, id: \.self) { title in
                let current = title == inView
                let lit = hovering && pointed == title
                Button { go(title) } label: {
                    HStack(spacing: 9) {
                        if hovering {
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
                    .padding(.vertical, hovering ? 5.5 : 0)
                    .padding(.horizontal, hovering ? 8 : 0)
                    // Each row as wide as the widest: none of the panel
                    // between rows that lights nothing.
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background {
                        if lit { RoundedRectangle(cornerRadius: 7).fill(Ink.accent.color.opacity(0.12)) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { pointed = title } else if pointed == title { pointed = nil }
                }
                .help(hovering ? "" : store.shownTitle(title))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(8)
        .animation(.easeOut(duration: 0.1), value: pointed)
    }
}
#endif
