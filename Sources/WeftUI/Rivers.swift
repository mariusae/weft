import ReflectCore
import SwiftUI
import WeftCore

extension FocusedValues {
    /// The river of the window in front, for the menus to act on.
    @Entry public var river: River?
    /// And the rivers of that window: its tabs, on the Mac.
    @Entry public var rivers: RiverSet?
}

/// A window's rivers, one shown at a time — on the phone, swiped between at
/// the river's foot; on the Mac, its tabs, in the title bar. Kept per graph,
/// on this device.
@MainActor @Observable
public final class RiverSet {
    let store: WikiStore
    public private(set) var rivers: [River] = []
    public private(set) var current: River {
        didSet {
            guard current !== oldValue else { return }
            oldValue.isShown = false
            current.isShown = true
        }
    }

    /// The window these are the rivers of, on the iPad: each keeps its
    /// own. Empty for the first, which keeps them as the phone does.
    public var scene = "" {
        didSet { if scene != oldValue { load() } }
    }

    public init(store: WikiStore) {
        self.store = store
        current = River(store: store)
        current.isShown = true
        rivers = [current]
        hook(current)
        store.adopt(current)
        // What is waiting to be kept, kept before the app goes.
        #if os(macOS)
        let leaving = NSApplication.willTerminateNotification
        #else
        let leaving = UIApplication.didEnterBackgroundNotification
        #endif
        leavingObserver = NotificationCenter.default.addObserver(forName: leaving, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepNow() }
        }
    }

    @ObservationIgnored private var leavingObserver: Any?

    private var key: String { "Rivers:\(store.root?.path ?? "")" + (scene.isEmpty ? "" : ":\(scene)") }
    /// While the rivers kept are put back: not kept again half put back.
    @ObservationIgnored private var loading = false

    private struct Kept: Codable {
        var rivers: [River.State]
        var current: Int
    }

    /// The graph's pages are read: its rivers as they were kept — or one,
    /// with the cards open last.
    public func load() {
        guard let root = store.loadedRoot else { return }
        loading = true
        // Kept under this graph's, or this window's, name: written whatever was last.
        kept = nil
        defer { loading = false; keep() }
        let kept = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Kept.self, from: $0) }
        let states = kept?.rivers.isEmpty == false ? kept!.rivers
            : [River.State(graph: root.path, cards: store.lastRiver ?? store.defaultCards())]
        for river in rivers { store.release(river) }
        rivers = states.map(make)
        current = rivers[min(max(kept?.current ?? 0, 0), rivers.count - 1)]
    }

    private func make(_ state: River.State?) -> River {
        let river = River(store: store)
        hook(river)
        store.adopt(river)
        if let state { river.restore(state) }
        return river
    }

    private func hook(_ river: River) {
        river.onChange = { [weak self] in self?.keep() }
        river.present = { [weak self, weak river] in if let river { self?.select(river) } }
        river.openNew = { [weak self] in self?.add($0) }
    }

    /// Another river, after this one: empty, with Quick Open showing — or
    /// a saved one recalled.
    public func add(_ state: River.State? = nil) {
        let river = make(state)
        let index = rivers.firstIndex { $0 === current }.map { $0 + 1 } ?? rivers.count
        rivers.insert(river, at: index)
        current = river
        if state == nil { river.quickOpenShown = true }
        keep()
    }

    public func select(_ river: River) {
        guard rivers.contains(where: { $0 === river }) else { return }
        current = river
        keep()
    }

    /// The river before or after this one.
    public func step(_ by: Int) {
        guard let index = rivers.firstIndex(where: { $0 === current }) else { return }
        let next = index + by
        guard rivers.indices.contains(next) else { return }
        select(rivers[next])
    }

    /// The window's rivers just this one: a tab moved to a window of its own.
    public func start(with state: River.State) {
        for river in rivers { store.release(river) }
        let river = make(state)
        rivers = [river]
        current = river
        keep()
    }

    /// A river dragged to another place among the tabs.
    public func move(_ river: River, to index: Int) {
        guard let from = rivers.firstIndex(where: { $0 === river }) else { return }
        rivers.remove(at: from)
        rivers.insert(river, at: min(max(0, index), rivers.count))
        keep()
    }

    /// The tabs closed, the last closed last: each as it was, and where
    /// it was — to be opened again, ⌘⇧T, as a browser's are.
    private var closed: [(state: River.State, index: Int)] = []

    public var canReopen: Bool { !closed.isEmpty }

    private func remember(_ river: River, at index: Int) {
        closed.append((river.state, index))
        if closed.count > 30 { closed.removeFirst() }
    }

    /// The tab closed last, open again where it was, in front.
    public func reopenClosed() {
        guard let last = closed.popLast() else { return }
        let river = make(last.state)
        rivers.insert(river, at: min(last.index, rivers.count))
        current = river
        keep()
    }

    /// The rivers but this one closed.
    public func closeOthers(_ kept: River) {
        for (index, river) in rivers.enumerated() where river !== kept { remember(river, at: index) }
        for river in rivers where river !== kept { store.release(river) }
        rivers = [kept]
        current = kept
        keep()
    }

    /// Closes a river — not the last. A saved river stays saved.
    public func close(_ river: River) {
        guard rivers.count > 1, let index = rivers.firstIndex(where: { $0 === river }) else { return }
        remember(river, at: index)
        rivers.remove(at: index)
        store.release(river)
        if current === river { current = rivers[min(index, rivers.count - 1)] }
        keep()
    }

    /// Kept a moment after the last change, not as each is made: a tab
    /// shown, a card scrolled to, are not held up writing every tab out.
    private func keep() {
        guard !keepWaiting else { return }
        keepWaiting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.keepNow() }
    }

    @ObservationIgnored private var keepWaiting = false
    /// What was last kept: not written again the same.
    @ObservationIgnored private var kept: (data: Data?, cards: [String])?

    private func keepNow() {
        keepWaiting = false
        guard store.loadedRoot != nil, !loading else { return }
        let data = try? JSONEncoder().encode(Kept(rivers: rivers.map(\.state), current: rivers.firstIndex { $0 === current } ?? 0))
        let cards = current.cards
        guard kept?.data != data || kept?.cards != cards else { return }
        if kept?.data != data { UserDefaults.standard.set(data, forKey: key) }
        if kept?.cards != cards { store.lastRiver = cards }
        kept = (data, cards)
    }
}

// MARK: The phone's rivers

#if os(iOS)
/// The bar's menu: the rivers open, a new one, saving this one, the saved ones.
struct RiverSetMenu: View {
    let rivers: RiverSet

    var body: some View {
        let current = rivers.current
        Section {
            ForEach(rivers.rivers) { river in
                Button { rivers.select(river) } label: {
                    if river === current {
                        Label(river.title, systemImage: "checkmark")
                    } else {
                        Text(river.title)
                    }
                }
            }
        }
        Section {
            Button("New River", systemImage: "plus") { rivers.add() }
            Button(current.name == nil ? "Save River…" : "Rename River…", systemImage: "square.and.arrow.down") {
                current.naming = current.name.map { .rename($0) } ?? .save
            }
            if let name = current.name {
                Button("Choose River Icon…", systemImage: current.icon ?? "square.grid.3x3") { current.choosingIcon = true }
                Button("Copy Link to River", systemImage: "link") { Platform.copy(RiverLink.link(name)) }
                Button("Copy River Address", systemImage: "safari") { Platform.copy(RiverLink.url(name).absoluteString) }
            }
            Button("Saved Rivers…", systemImage: "tray.full") { current.riversShown = true }
        }
        Section {
            Button("New Query River…", systemImage: "line.3.horizontal.decrease.circle") { current.queryEditor = .new }
            Button(current.isQuery ? "Edit River Query…" : "Fill from Query…", systemImage: "slider.horizontal.3") { current.queryEditor = .edit }
        }
        if rivers.rivers.count > 1 {
            Button("Close River", systemImage: "xmark", role: .destructive) { rivers.close(current) }
        }
    }
}

/// At the foot of the river: which it is — its menu the rivers open, a
/// new one, the saved ones — and, with more than one, a swipe to the one
/// beside it. Read down into the river, gathered to its name.
struct RiverSwitcher: View {
    let rivers: RiverSet
    var small = false

    var body: some View {
        let index = rivers.rivers.firstIndex { $0 === rivers.current } ?? 0
        let many = rivers.rivers.count > 1
        HStack(spacing: 6) {
            if many, !small {
                Button { withAnimation(.snappy) { rivers.step(-1) } } label: {
                    Image(systemName: "chevron.left").frame(width: 30, height: 30)
                }
                .disabled(index == 0)
            }
            Menu {
                RiverSetMenu(rivers: rivers)
            } label: {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text(rivers.current.title)
                            .font(small ? .footnote.weight(.medium) : .callout.weight(.medium))
                            .lineLimit(1)
                        if !small {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Ink.secondary.color)
                        }
                    }
                    if many, !small {
                        HStack(spacing: 5) {
                            ForEach(rivers.rivers.indices, id: \.self) { at in
                                Circle()
                                    .fill(at == index ? Ink.accent.color : Ink.faint.color)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                }
                .frame(minWidth: small ? nil : 120, maxWidth: small ? nil : 220)
                .fixedSize(horizontal: small, vertical: false)
                .contentShape(.rect)
            }
            .accessibilityLabel("River: \(rivers.current.title)")
            if many, !small {
                Button { withAnimation(.snappy) { rivers.step(1) } } label: {
                    Image(systemName: "chevron.right").frame(width: 30, height: 30)
                }
                .disabled(index == rivers.rivers.count - 1)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, small ? 12 : 8)
        .padding(.vertical, small ? 6 : 6)
        .contentShape(.capsule)
        // Over its buttons too: a tap is theirs, a swipe the bar's.
        .highPriorityGesture(DragGesture(minimumDistance: 16).onEnded { drag in
            guard many, abs(drag.translation.width) > max(36, abs(drag.translation.height)) else { return }
            withAnimation(.snappy) { rivers.step(drag.translation.width < 0 ? 1 : -1) }
        })
        .animation(.spring(duration: 0.32, bounce: 0.14), value: small)
        .sensoryFeedback(.selection, trigger: index)
        .glassEffect(.regular, in: .capsule)
    }
}
#endif

// MARK: Saved rivers

#if os(macOS)
/// In the toolbar: this river — saved or not — and the saved ones.
struct RiversButton: View {
    @Environment(River.self) private var river

    var body: some View {
        @Bindable var river = river
        Button("Rivers", systemImage: "square.stack.3d.up") { river.riversShown.toggle() }
            .help("Saved Rivers (⇧⌘R)")
            .popover(isPresented: $river.riversShown, arrowEdge: .bottom) {
                RiversPanel().frame(width: 320)
            }
    }
}
#endif

/// This river, saved or not, and every saved river — to recall, duplicate,
/// rename or delete.
struct RiversPanel: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    @State private var deleting: String?
    /// The saved river whose icon is being chosen.
    @State private var choosingIcon: String?

    var body: some View {
        let saved = store.savedRivers()
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(river.name ?? "This river").font(.headline)
                        Text(river.name == nil ? "Kept on this device only" : "Saved in the graph, and synced")
                            .font(.caption)
                            .foregroundStyle(Ink.secondary.color)
                    }
                    Spacer()
                    Button(river.name == nil ? "Save…" : "Rename…") {
                        ask(river.name.map { .rename($0) } ?? .save)
                    }
                }
            }
            Section("Saved Rivers") {
                if saved.isEmpty {
                    Text("None yet. A river saved under a name is kept in the graph, synced, and brought back from here.")
                        .font(.callout)
                        .foregroundStyle(Ink.secondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(saved, id: \.self) { name in row(name) }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        // As tall as its rows, up to a point.
        .frame(height: min(130 + CGFloat(max(saved.count, 1)) * 40, 460))
        #endif
        .sheet(isPresented: Binding(get: { choosingIcon != nil }, set: { if !$0 { choosingIcon = nil } })) {
            if let name = choosingIcon {
                RiverIconSheet(name: name, current: store.savedRiverIcon(name), color: store.savedRiver(name)?.color) { symbol in
                    store.setSavedRiverIcon(name, symbol)
                }
            }
        }
        .confirmationDialog("Delete the river “\(deleting ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting { store.deleteSavedRiver(deleting) }
            }
        } message: {
            Text("Its cards stay as they are; only the saved river goes. The graph's history keeps it.")
        }
    }

    private func row(_ name: String) -> some View {
        let count = store.savedCards(name)?.count ?? 0
        let open = store.river(named: name) != nil
        let linking = store.linking(toRiver: name)
        return Button {
            river.riversShown = false
            river.recall(name)
        } label: {
            HStack {
                Image(systemName: store.savedRiverIcon(name) ?? "square.stack.3d.up")
                    .foregroundStyle(Ink.accent.color)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).lineLimit(1)
                    Text((count == 1 ? "1 card" : "\(count) cards") + (linking.isEmpty ? "" : " · linked from \(linking.count)"))
                        .font(.caption)
                        .foregroundStyle(Ink.secondary.color)
                }
                Spacer()
                if open {
                    Text(river.name == name ? "Here" : "Open")
                        .font(.caption)
                        .foregroundStyle(Ink.secondary.color)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.square") {
                river.riversShown = false
                river.recall(name)
            }
            Button("Copy Link", systemImage: "link") { Platform.copy(RiverLink.link(name)) }
            Button("Copy Address", systemImage: "safari") { Platform.copy(RiverLink.url(name).absoluteString) }
            if !linking.isEmpty {
                Menu("Linked From", systemImage: "arrow.turn.down.left") {
                    ForEach(linking, id: \.self) { page in
                        Button(store.shownTitle(page)) {
                            river.riversShown = false
                            river.open(page)
                        }
                    }
                }
            }
            Button("Duplicate…", systemImage: "plus.square.on.square") { ask(.clone(name)) }
            Button("Rename…", systemImage: "pencil") { ask(.rename(name)) }
            Button("Choose Icon…", systemImage: store.savedRiverIcon(name) ?? "square.grid.3x3") { choosingIcon = name }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive) { deleting = name }
        }
        .swipeActions {
            // Red and grey, not the app's accent.
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = name }
                .tint(.red)
            Button("Duplicate", systemImage: "plus.square.on.square") { ask(.clone(name)) }
                .tint(.gray)
        }
    }

    /// Asks for a name: over the window on the Mac, the popover closed;
    /// over the sheet on the phone.
    private func ask(_ naming: River.Naming) {
        #if os(macOS)
        river.riversShown = false
        #endif
        river.naming = naming
    }
}

/// The phone's saved rivers, as a sheet.
struct SavedRiversSheet: View {
    @Environment(River.self) private var river

    var body: some View {
        NavigationStack {
            RiversPanel()
                .navigationTitle("Rivers")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { river.riversShown = false }
                    }
                }
        }
        // A name asked for from the sheet is asked over it.
        .riverNaming(river)
    }
}

extension View {
    /// Asks for a river's name — to save it, or to rename or duplicate a
    /// saved one — when the river asks for one.
    /// `asking`: false while another view over this one asks instead.
    func riverNaming(_ river: River, asking: Bool = true) -> some View { modifier(RiverNaming(river: river, asking: asking)) }
}

private struct RiverNaming: ViewModifier {
    @Environment(WikiStore.self) private var store
    let river: River
    let asking: Bool
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: Binding(get: { asking && river.naming != nil }, set: { if !$0 { river.naming = nil } })) {
                TextField("Name", text: $text)
                Button("Cancel", role: .cancel) {}
                Button(confirm) { commit() }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text(message)
            }
            .onChange(of: river.naming) { _, naming in
                switch naming {
                case .save: text = river.cards.first.map(store.shownTitle) ?? ""
                case .rename(let name): text = name
                case .clone(let name): text = store.cloneName(name)
                case nil: break
                }
            }
    }

    private var title: String {
        switch river.naming {
        case .save, nil: "Save River"
        case .rename: "Rename River"
        case .clone: "Duplicate River"
        }
    }

    private var confirm: String {
        switch river.naming {
        case .save, nil: "Save"
        case .rename: "Rename"
        case .clone: "Duplicate"
        }
    }

    private var message: String {
        switch river.naming {
        case .save, nil: "A saved river is kept in the graph and synced, its cards as they change. Bring it back from Saved Rivers."
        case .rename(let name): "A new name for “\(name)”."
        case .clone(let name): "A copy of “\(name)”, under a name of its own."
        }
    }

    private func commit() {
        switch river.naming {
        case .save: river.save(as: text)
        case .rename(let name):
            if river.name == name { river.save(as: text) } else { store.renameSavedRiver(name, to: text) }
        case .clone(let name): store.cloneSavedRiver(name, as: text)
        case nil: break
        }
    }
}

/// `weft://river/Name`, opened from anywhere: that saved river brought back
/// from this window's rivers — once the graph is read, for an address that
/// opened Weft.
struct RiverAddresses: ViewModifier {
    @Environment(WikiStore.self) private var store
    let rivers: RiverSet
    @State private var waiting: String?

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                guard let name = RiverLink.name(from: url) else { return }
                waiting = name
                follow()
            }
            .onChange(of: store.loadedRoot) { follow() }
    }

    private func follow() {
        guard waiting != nil, store.loadedRoot != nil else { return }
        // After the window's rivers are put back, which the graph read also asks.
        DispatchQueue.main.async {
            guard let name = waiting else { return }
            waiting = nil
            rivers.current.follow(river: name)
        }
    }
}

extension View {
    /// Brings back the saved river a `weft://river/…` address names.
    public func followingRiverAddresses(_ rivers: RiverSet) -> some View {
        modifier(RiverAddresses(rivers: rivers))
    }
}
