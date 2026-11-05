#if os(iOS)
import ReflectCore
import SwiftUI
import UIKit
import WeftCore

// The phone's Weft, as Safari is: the river full height, and under it one
// glass bar — back, the river's menu, the river by name, a new tiddler, and
// the rivers all at once. The name dragged aside slides to the river
// beside this one; tapped, the start page, where everything else is found.

// MARK: The bar

/// At the foot of the river, on glass: ‹ back, and held the cards gone to
/// before; ⋯ what is done with the river; its name — tapped, the start
/// page, dragged aside, the river beside it; + a new tiddler; and the
/// rivers all shown. Read down into the river, gathered to its name.
struct PhoneBar: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    @Environment(\.accountSettings) private var accountSettings
    let rivers: RiverSet?
    let tucked: Bool
    let untuck: () -> Void
    @State private var settingsShown = false
    @State private var width: CGFloat = 400
    /// The bar's glass, one piece morphing into another as it is gathered
    /// to the river's name and opened out again.
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            if tucked {
                // Read down into the river: the bar gathered to its name,
                // smaller, low — as Safari's to its site. Tapped, or
                // scrolled back up, it opens out again.
                Button(action: untuck) {
                    Text(river.title)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Ink.text.color)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .contentShape(.capsule)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("name", in: glass)
                // Pulled down: every card folded to its peek — the river at a glance.
                .highPriorityGesture(DragGesture(minimumDistance: 10).onEnded { drag in
                    guard drag.translation.height > 18, drag.translation.height > abs(drag.translation.width) else { return }
                    withAnimation(.snappy(duration: 0.3)) { river.foldAll() }
                })
                .frame(maxWidth: width * 0.6)
                // Low, as Safari's: drawn lower, not laid out lower.
                .offset(y: 14)
                .accessibilityLabel(river.title)
                .accessibilityHint("Shows the river's controls")
            } else {
                HStack(spacing: 8) {
                    find
                        .glassEffectID("find", in: glass)
                    HStack(spacing: 0) {
                        more
                        name
                        // As wide as ⋯, the name in the middle.
                        Color.clear.frame(width: 46, height: 48)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .glassEffectID("name", in: glass)
                    new
                        .glassEffectID("new", in: glass)
                }
                .padding(.horizontal, 14)
                // Dragged aside, the river beside this one; up, the rivers all shown.
                .highPriorityGesture(swipe)
            }
        }
        // Its room the same, gathered or not.
        .frame(height: 48)
        .buttonStyle(.plain)
        .foregroundStyle(Ink.accent.color)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 320) }
        .animation(.spring(duration: 0.38, bounce: 0.12), value: tucked)
        .sensoryFeedback(.selection, trigger: rivers?.currentIndex)
        .sheet(isPresented: $settingsShown) {
            NavigationStack {
                SettingsForm { accountSettings }
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { settingsShown = false } }
                    }
            }
        }
    }

    private var riverSymbol: String { river.icon ?? (river.isQuery ? "line.3.horizontal.decrease.circle" : "square.stack") }

    /// A page found by name, or a new one named: the start page, the keys up.
    private var find: some View {
        Button {
            rivers?.startTyping = true
            river.quickOpenShown = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Find a Tiddler")
    }

    /// A new tiddler, at the top of the river.
    /// Tapped, a new tiddler; held, one of what is on the pasteboard.
    private var new: some View {
        Menu {
            Button("New Tiddler from Pasteboard", systemImage: "doc.on.clipboard") { river.newTiddlerFromPasteboard() }
                .disabled(!Platform.pasteboardHasContents)
            Button("New Tiddler", systemImage: "plus") { river.newTiddler() }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 48, height: 48)
        } primaryAction: {
            river.newTiddler()
        }
        .menuIndicator(.hidden)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("New Tiddler")
        .accessibilityHint("Hold for a new tiddler of what is on the pasteboard")
    }

    /// The river by name — its icon before it — the start page a tap away.
    private var name: some View {
        Button {
            rivers?.startTyping = false
            river.quickOpenShown = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: riverSymbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(river.color.map(RiverColor.color) ?? Ink.secondary.color)
                Text(river.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Ink.text.color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(.rect)
        }
        .accessibilityLabel("\(river.title): find a page or another river")
        .accessibilityHint("Swipe left or right for the next river, up for all of them")
    }

    /// Everything else done with the river, and the app.
    private var more: some View {
        let conflicts = store.conflicted()
        return Menu {
            if !conflicts.isEmpty {
                Button("\(conflicts.count) to Review", systemImage: "exclamationmark.triangle") { river.openConflicts() }
            }
            if !river.places.isEmpty {
                Menu("Back To", systemImage: "chevron.backward") {
                    ForEach(river.places, id: \.self) { place in
                        Button(store.shownTitle(place), systemImage: store.symbol(of: place)) { river.goBack(to: place) }
                    }
                }
            }
            if let rivers, rivers.rivers.count > 1 {
                Button("All Rivers", systemImage: "square.on.square") { rivers.overviewShown = true }
            }
            Section {
                Button("Today", systemImage: "calendar") { river.openToday() }
                Button("New Tiddler from Pasteboard", systemImage: "doc.on.clipboard") { river.newTiddlerFromPasteboard() }
                if river.allFolded {
                    Button("Unfold All", systemImage: "rectangle.expand.vertical") { withAnimation(.snappy) { river.unfoldAll() } }
                } else {
                    Button("Fold All", systemImage: "rectangle.compress.vertical") { withAnimation(.snappy) { river.foldAll() } }
                }
                Button("Close All Cards", systemImage: "rectangle.stack.badge.minus") { river.closeAll() }
            }
            if let rivers {
                Menu("River", systemImage: "square.stack") { RiverSetMenu(rivers: rivers) }
            }
            Section {
                if let sync = store.sync {
                    Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") { store.syncNow() }
                    Text(Self.syncState(sync))
                }
                Button("Recently Deleted…", systemImage: "trash") { river.deletedShown = true }
                Button("Settings…", systemImage: "gearshape") { settingsShown = true }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 46, height: 48)
                .overlay(alignment: .topTrailing) {
                    // Something to review: a dot on the menu that has it.
                    if !conflicts.isEmpty {
                        Circle().fill(.orange).frame(width: 7, height: 7).offset(x: -8, y: 10)
                    }
                }
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("More")
    }

    /// The name dragged aside: the river follows it, and let go far enough,
    /// slides away for the one beside it — at an end, it springs back.
    private var swipe: some Gesture {
        // Measured on the screen, not on the bar — which moves with the river under the finger.
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { drag in
                guard let rivers, abs(drag.translation.width) > abs(drag.translation.height) || rivers.swipe != 0 else { return }
                // Toward a river there is, or past the last toward a new one:
                // as far as the finger; before the first, held back.
                let toward = drag.translation.width < 0 ? 1 : -1
                let beside = rivers.rivers.indices.contains(rivers.currentIndex + toward) || toward > 0 && rivers.swipesToNew
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) {
                    rivers.swipe = beside ? drag.translation.width : drag.translation.width / 3
                }
            }
            .onEnded { drag in
                guard let rivers else { return }
                // Up, and more up than aside: the rivers all shown, as Safari's tabs.
                if drag.translation.height < -24, abs(drag.translation.height) > abs(drag.translation.width), rivers.swipe == 0 {
                    rivers.overviewShown = true
                    return
                }
                let moved = drag.predictedEndTranslation.width
                let toward = drag.translation.width < 0 ? 1 : -1
                let far = abs(drag.translation.width) > width * 0.4 || (abs(moved) > width * 0.5 && (moved < 0) == (toward > 0))
                if far, rivers.rivers.indices.contains(rivers.currentIndex + toward) {
                    Self.slide(rivers, by: toward, width: width)
                } else if far, toward > 0, rivers.swipesToNew {
                    Self.slideToNew(rivers, width: width)
                } else {
                    withAnimation(.interpolatingSpring(stiffness: 260, damping: 28)) { rivers.swipe = 0 }
                }
            }
    }

    /// The river beside this one slid the rest of the way in — the one
    /// shown going off the other side — and then the one shown.
    static func slide(_ rivers: RiverSet, by: Int, width: CGFloat) {
        let page = width + 28 + 14
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 30)) {
            rivers.swipe = by > 0 ? -page : page
        } completion: {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                rivers.step(by)
                rivers.swipe = 0
            }
        }
    }

    /// Past the last river: the new one slid in, and made — its start page
    /// in it, there at once, not risen over it.
    static func slideToNew(_ rivers: RiverSet, width: CGFloat) {
        let page = width + 28 + 14
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 30)) {
            rivers.swipe = -page
        } completion: {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                rivers.add(browsing: true)
                rivers.swipe = 0
            }
        }
    }

    static func syncState(_ sync: WikiSync) -> String {
        switch sync.status {
        case .idle: "Not synced yet"
        case .syncing: "Syncing…"
        case .synced(let date): "Synced \(date.formatted(.relative(presentation: .named)))"
        case .failed(let message): "Last sync failed: \(message)"
        }
    }
}

// MARK: The start page

/// Where everything is found, as Safari's start page is: at its foot the
/// field to find a page by, the keys up; over what it shows, glass to
/// choose among the rivers, what was written lately, the inbox and the
/// pinned, what is to be read, what is to do, and the wiki. Something typed: what it finds.
struct StartPage: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    let rivers: RiverSet?
    @State private var query = ""
    @State private var part: Part = .rivers
    @FocusState private var typing: Bool

    enum Part: String, CaseIterable, Identifiable {
        case rivers, recent, inbox, reading, tasks, wiki
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .rivers: "square.stack.3d.up"
            case .recent: "clock"
            case .inbox: "tray"
            case .reading: "eyeglasses"
            case .tasks: "checklist"
            case .wiki: "book.closed"
            }
        }
        var name: String {
            switch self {
            case .rivers: "Rivers"
            case .recent: "Recent"
            case .inbox: "Inbox and Pinned"
            case .reading: "Reading"
            case .tasks: "Tasks"
            case .wiki: "Wiki"
            }
        }
    }

    private var typed: String { query.trimmingCharacters(in: .whitespaces) }

    /// Asked from the bar's 🔍: only tiddlers, to add to this river — no
    /// parts to choose among, no rivers among what it finds.
    private var adding: Bool { rivers?.startTyping ?? true }

    var body: some View {
        NavigationStack {
            // One view round what it shows, not a Group: a Group gives each of
            // its parts the field below as its own, and the first letter
            // typed — what it finds shown, not what was written lately — made
            // the field anew, taking the keys away from it.
            ZStack {
                if !typed.isEmpty {
                    found
                } else if adding {
                    // Before a word is typed: what was written lately, to add.
                    List { section("Recent", Array(store.recent().prefix(30))) }
                } else {
                    chosen
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // On the page's own paper, as the river is: not a settings list's grey.
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top) { if typed.isEmpty, !adding { parts } }
            .safeAreaInset(edge: .bottom) { field }
            .background(Ink.paper.color)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            // Asked to find a page: the keys up as it opens, as Safari's field is.
            guard adding else { return }
            try? await Task.sleep(for: .milliseconds(150))
            typing = true
        }
    }

    // MARK: Its parts

    /// The parts, on glass at its top: their icons alone, the chosen lit.
    private var parts: some View {
        HStack(spacing: 2) {
            ForEach(Part.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { part = item }
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 17, weight: part == item ? .semibold : .regular))
                        .foregroundStyle(part == item ? Ink.accent.color : Ink.secondary.color)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(part == item ? Ink.accent.color.opacity(0.14) : .clear, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(part == item ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    /// At its foot: the field, and its ×, closing it.
    private var field: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Ink.secondary.color)
                TextField(adding ? "Add a tiddler to \(river.title)" : "Find a page, or name a new one", text: $query)
                    .focused($typing)
                    .submitLabel(.go)
                    .autocorrectionDisabled()
                    .onSubmit { if let first = results.first { open(first) } }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.faint.color) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .glassEffect(.regular.interactive(), in: .capsule)
            Button { close() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ink.text.color)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var chosen: some View {
        switch part {
        case .rivers: RiversGrid(rivers: rivers, close: close)
        case .recent:
            pages(store.recent(), empty: "Nothing written yet")
        case .inbox:
            List {
                section("Pinned", store.pinned())
                section("Inbox", store.inbox())
            }
            .overlay { if store.pinned().isEmpty && store.inbox().isEmpty { empty("Nothing pinned, and nothing in the inbox") } }
        case .reading:
            ReadingList().onChange(of: river.focusRequest) { close() }
        case .tasks:
            TaskList().onChange(of: river.focusRequest) { close() }
        case .wiki:
            List {
                section(nil, store.wikiPages())
                Section("More") {
                    NavigationLink { tags } label: { Label("Tags", systemImage: "tag") }
                    NavigationLink { pages(store.missing(), empty: "No links to missing tiddlers").navigationTitle("Missing") } label: {
                        Label("Missing Pages", systemImage: "questionmark.square.dashed")
                    }
                }
            }
        }
    }

    private var tags: some View {
        List(store.tags(), id: \.tag) { item in
            Button { open(item.tag) } label: {
                HStack {
                    TagPill(tag: item.tag)
                    Spacer()
                    Text("\(item.count)").foregroundStyle(.secondary).monospacedDigit()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Tags")
    }

    private func pages(_ titles: [String], empty words: String) -> some View {
        List { section(nil, titles) }
            .overlay { if titles.isEmpty { empty(words) } }
    }

    @ViewBuilder private func section(_ name: String?, _ titles: [String]) -> some View {
        if !titles.isEmpty {
            Section {
                ForEach(titles, id: \.self) { title in row(title) }
            } header: {
                if let name { Text(name) }
            }
        }
    }

    private func row(_ title: String) -> some View {
        Button { open(title) } label: {
            HStack(spacing: 10) {
                Image(systemName: store.symbol(of: title))
                    .font(.callout)
                    .foregroundStyle(Ink.secondary.color)
                    .frame(width: 22)
                Text(store.shownTitle(title)).lineLimit(1)
                Spacer()
                if river.cards.contains(title) {
                    Text("Open").font(.caption).foregroundStyle(Ink.secondary.color)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func empty(_ words: String) -> some View {
        Text(words).foregroundStyle(Ink.secondary.color).multilineTextAlignment(.center).padding()
    }

    // MARK: What is typed

    /// What the words typed find — and a new tiddler of them, when no page
    /// is called that.
    private var results: [LinkTarget] {
        var found = store.quickOpen(typed, limit: 30)
        // Adding to this river: tiddlers and days, not other rivers.
        if adding { found.removeAll { $0.kind == .river } }
        if !typed.isEmpty, !found.contains(where: { $0.title.caseInsensitiveCompare(typed) == .orderedSame }) {
            found.append(LinkTarget(title: typed, shown: typed, kind: .new))
        }
        return found
    }

    private var found: some View {
        List(results, id: \.self) { target in
            Button { open(target) } label: {
                HStack(spacing: 10) {
                    Image(systemName: target.symbol)
                        .font(.callout)
                        .foregroundStyle(target.kind == .new ? Ink.accent.color : Ink.secondary.color)
                        .frame(width: 22)
                    Text(target.kind == .new ? "New Tiddler “\(target.title)”" : target.shown)
                        .foregroundStyle(target.kind == .new ? Ink.accent.color : Ink.text.color)
                        .lineLimit(1)
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Going

    private func open(_ target: LinkTarget) {
        switch target.kind {
        case .new:
            close()
            withAnimation(.snappy(duration: 0.28)) { river.edit(target.title) }
        case .river:
            close()
            if let name = RiverLink.name(target.title) { river.replace(withSaved: name) }
        default:
            open(target.title)
        }
    }

    private func open(_ title: String) {
        close()
        withAnimation(.snappy(duration: 0.28)) { river.open(title) }
    }

    private func close() {
        typing = false
        river.quickOpenShown = false
    }
}

/// The saved rivers, as Safari's favourites: each its icon, in its
/// colour, on a tile, its name under it — those open marked.
private struct RiversGrid: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    let rivers: RiverSet?
    let close: () -> Void

    var body: some View {
        let saved = store.savedRivers()
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved Rivers")
                    .font(.title3.weight(.bold))
                    .padding(.horizontal, 4)
                if saved.isEmpty {
                    Text("A river saved under a name — from ⋯ ▸ River — is kept in the graph, synced, and brought back from here.")
                        .foregroundStyle(Ink.secondary.color)
                        .padding(.horizontal, 4)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4), spacing: 18) {
                    ForEach(saved, id: \.self) { name in tile(name) }
                    newQuery
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func tile(_ name: String) -> some View {
        let saved = store.savedRiver(name)
        let color = RiverColor.color(saved?.color ?? (saved?.query != nil ? "orange" : "blue"))
        let open = store.river(named: name) != nil
        // In this river's place, as a page chosen from Safari's start page
        // takes the tab's — a new river is a new tab's.
        return Button {
            close()
            withAnimation(.snappy(duration: 0.28)) { river.replace(withSaved: name) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: store.savedRiverIcon(name) ?? (saved?.query != nil ? "line.3.horizontal.decrease.circle" : "square.stack"))
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 64, height: 64)
                    .background(color.opacity(0.14), in: .rect(cornerRadius: 16))
                    .overlay(alignment: .topTrailing) {
                        if open { Circle().fill(Ink.accent.color).frame(width: 9, height: 9).offset(x: 2, y: -2) }
                    }
                Text(name)
                    .font(.caption)
                    .foregroundStyle(Ink.text.color)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.square") { close(); river.replace(withSaved: name) }
            Button("Open in New River", systemImage: "plus.square.on.square") {
                close()
                if let showing = store.river(named: name) { showing.present() } else {
                    river.openNew(River.State(graph: store.root?.path ?? "", name: name, cards: []))
                }
            }
            Button("Copy Link", systemImage: "link") { Platform.copy(RiverLink.link(name)) }
        }
        .accessibilityLabel(name + (open ? ", open" : ""))
    }

    private var newQuery: some View {
        newTile("Query River", "line.3.horizontal.decrease") {
            close()
            river.queryEditor = .newHere
        }
    }

    /// A tile for something new: its symbol faint, on grey.
    private func newTile(_ name: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Ink.secondary.color)
                    .frame(width: 64, height: 64)
                    .background(Ink.text.color.opacity(0.06), in: .rect(cornerRadius: 16))
                Text(name).font(.caption).foregroundStyle(Ink.secondary.color)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New " + name)
    }
}

// MARK: The rivers all at once

/// The rivers open, side by side, as Safari's tabs: each its icon and
/// name, and the first of its cards — tapped, shown; ×, closed. At the
/// foot: a new river, how many, and Done.
struct RiverOverview: View {
    @Environment(WikiStore.self) private var store
    let rivers: RiverSet

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(rivers.rivers) { river in
                        tile(river).id(river.id)
                            // Held and dragged: put elsewhere among them.
                            .draggable(river.id.uuidString) {
                                tile(river).frame(width: 170).opacity(0.9)
                            }
                            .dropDestination(for: String.self) { ids, _ in
                                guard let id = ids.first.flatMap(UUID.init(uuidString:)),
                                      let moved = rivers.rivers.first(where: { $0.id == id }), moved !== river,
                                      let to = rivers.rivers.firstIndex(where: { $0 === river }) else { return false }
                                withAnimation(.snappy(duration: 0.25)) { rivers.move(moved, to: to) }
                                return true
                            }
                    }
                }
                .padding(16)
                .animation(.snappy(duration: 0.25), value: rivers.rivers.map(\.id))
            }
            .onAppear { proxy.scrollTo(rivers.current.id, anchor: .center) }
        }
        .background(Color.river.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            HStack {
                // As Safari's: a new tab, its start page in it — a saved
                // river, a page, or a query to fill it with.
                Button {
                    rivers.add(browsing: true)
                    rivers.overviewShown = false
                } label: {
                    Image(systemName: "plus").font(.system(size: 19, weight: .medium)).frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("New River")
                Spacer()
                Text(rivers.rivers.count == 1 ? "1 River" : "\(rivers.rivers.count) Rivers")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Ink.text.color)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .glassEffect(.regular, in: .capsule)
                Spacer()
                Button { rivers.overviewShown = false } label: {
                    Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).frame(width: 48, height: 48)
                }
                .foregroundStyle(.white)
                .glassEffect(.regular.tint(Ink.accent.color).interactive(), in: .circle)
                .accessibilityLabel("Done")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ink.accent.color)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    private func tile(_ river: River) -> some View {
        let current = river === rivers.current
        let color = river.color.map(RiverColor.color) ?? Ink.secondary.color
        return Button {
            rivers.select(river)
            rivers.overviewShown = false
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: river.icon ?? (river.isQuery ? "line.3.horizontal.decrease.circle" : "square.stack"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                    Text(river.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Ink.text.color)
                        .lineLimit(1)
                    Spacer(minLength: 22)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(river.cards.prefix(5), id: \.self) { title in
                        HStack(spacing: 5) {
                            Image(systemName: store.symbol(of: title)).font(.system(size: 9)).foregroundStyle(Ink.faint.color)
                            Text(store.shownTitle(title)).font(.caption2).foregroundStyle(Ink.secondary.color).lineLimit(1)
                        }
                    }
                    if river.cards.isEmpty {
                        Text("No cards").font(.caption2).foregroundStyle(Ink.faint.color)
                    } else if river.cards.count > 5 {
                        Text("and \(river.cards.count - 5) more").font(.caption2).foregroundStyle(Ink.faint.color)
                    }
                }
                .padding(10)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 190, alignment: .topLeading)
            .background(Color.card)
            .clipShape(.rect(cornerRadius: 18))
            // Where it is, for its river to shrink into and grow out of.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rivers.tileFrames[river.id] = $0 }
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(current ? Ink.accent.color : Ink.rule.color, lineWidth: current ? 2.5 : 1))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if rivers.rivers.count > 1 {
                Button { withAnimation(.snappy(duration: 0.25)) { rivers.close(river) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Ink.secondary.color)
                        .frame(width: 22, height: 22)
                        .background(Ink.text.color.opacity(0.08), in: .circle)
                        .frame(width: 40, height: 40)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(river.title)")
            }
        }
        .contextMenu {
            Button(river.name == nil ? "Save River…" : "Rename River…", systemImage: "square.and.arrow.down") {
                rivers.select(river)
                rivers.overviewShown = false
                river.naming = river.name.map { .rename($0) } ?? .save
            }
            if rivers.rivers.count > 1 {
                Button("Close River", systemImage: "xmark", role: .destructive) { rivers.close(river) }
                Button("Close Other Rivers", systemImage: "xmark.square") { rivers.closeOthers(river) }
            }
        }
        .accessibilityLabel(river.title + (current ? ", shown" : ""))
    }
}
#endif
