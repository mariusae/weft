import SwiftUI
import WeftCore

extension FocusedValues {
    /// The river of the window in front, for the menus to act on.
    @Entry public var river: River?
}

/// The phone's rivers, one shown at a time — on the Mac each is a tab of
/// its own. Kept per graph, on this device.
@MainActor @Observable
public final class RiverSet {
    let store: WikiStore
    public private(set) var rivers: [River] = []
    public private(set) var current: River

    public init(store: WikiStore) {
        self.store = store
        current = River(store: store)
        rivers = [current]
        hook(current)
        store.adopt(current)
    }

    private var key: String { "Rivers:\(store.root?.path ?? "")" }
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

    /// Closes a river — not the last. A saved river stays saved.
    public func close(_ river: River) {
        guard rivers.count > 1, let index = rivers.firstIndex(where: { $0 === river }) else { return }
        rivers.remove(at: index)
        store.release(river)
        if current === river { current = rivers[min(index, rivers.count - 1)] }
        keep()
    }

    private func keep() {
        guard store.loadedRoot != nil, !loading else { return }
        let kept = Kept(rivers: rivers.map(\.state), current: rivers.firstIndex { $0 === current } ?? 0)
        UserDefaults.standard.set(try? JSONEncoder().encode(kept), forKey: key)
        store.lastRiver = current.cards
    }
}

// MARK: The phone's rivers

#if os(iOS)
/// Under the title: the rivers open, a new one, saving this one, the saved ones.
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
            Button("Saved Rivers…", systemImage: "tray.full") { current.riversShown = true }
        }
        if rivers.rivers.count > 1 {
            Button("Close River", systemImage: "xmark", role: .destructive) { rivers.close(current) }
        }
    }
}

/// At the foot of the river, with more than one open: which it is, and a
/// swipe to the one beside it.
struct RiverSwitcher: View {
    let rivers: RiverSet

    var body: some View {
        let index = rivers.rivers.firstIndex { $0 === rivers.current } ?? 0
        HStack(spacing: 6) {
            Button { withAnimation(.snappy) { rivers.step(-1) } } label: {
                Image(systemName: "chevron.left").frame(width: 30, height: 30)
            }
            .disabled(index == 0)
            VStack(spacing: 4) {
                Text(rivers.current.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    ForEach(rivers.rivers.indices, id: \.self) { at in
                        Circle()
                            .fill(at == index ? Ink.accent.color : Ink.faint.color)
                            .frame(width: 5, height: 5)
                    }
                }
            }
            .frame(minWidth: 120, maxWidth: 220)
            Button { withAnimation(.snappy) { rivers.step(1) } } label: {
                Image(systemName: "chevron.right").frame(width: 30, height: 30)
            }
            .disabled(index == rivers.rivers.count - 1)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(.capsule)
        // Over its buttons too: a tap is theirs, a swipe the bar's.
        .highPriorityGesture(DragGesture(minimumDistance: 16).onEnded { drag in
            guard abs(drag.translation.width) > max(36, abs(drag.translation.height)) else { return }
            withAnimation(.snappy) { rivers.step(drag.translation.width < 0 ? 1 : -1) }
        })
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
        .confirmationDialog("Delete the river “\(deleting ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting { store.deleteSavedRiver(deleting) }
            }
        } message: {
            Text("Its cards stay as they are; only the saved river goes. The graph's history keeps it.")
        }
    }

    private func row(_ name: String) -> some View {
        let count = store.savedRiver(name)?.count ?? 0
        let open = store.river(named: name) != nil
        return Button {
            river.riversShown = false
            river.recall(name)
        } label: {
            HStack {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(Ink.accent.color)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).lineLimit(1)
                    Text(count == 1 ? "1 card" : "\(count) cards")
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
            Button("Duplicate…", systemImage: "plus.square.on.square") { ask(.clone(name)) }
            Button("Rename…", systemImage: "pencil") { ask(.rename(name)) }
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
