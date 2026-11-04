#if os(macOS)
import ReflectCore
import SwiftUI
import UniformTypeIdentifiers
import WeftCore

/// How wide each tab is, in the room the title bar gives: all alike while
/// each can show its name; past that, the others bunched to their icons —
/// the one under the pointer opened out to its name, as Safari does — but a
/// saved river's showing its name while there is room for it, cut short
/// before it too is bunched; and the one shown taking what is left.
enum TabLayout {
    static let spacing: CGFloat = 4
    /// A bunched tab: its icon alone.
    static let bunched: CGFloat = 34
    /// The narrowest a tab still shows its name.
    static let readable: CGFloat = 112
    /// The one shown, never narrower; a bunched tab under the pointer, this wide.
    static let shownMin: CGFloat = 150
    static let pointed: CGFloat = 150
    /// A bunched tab at its tightest.
    static let tightest: CGFloat = 24

    /// A saved river's tab: at its widest, its name cut short past it; at
    /// its narrowest still showing the start of it — narrower, bunched.
    static let namedMax: CGFloat = 170
    static let namedMin: CGFloat = 96

    /// `named`: for each tab, the room a saved river's name needs — nil for one not saved.
    static func widths(count: Int, current: Int, pointed hovered: Int?, named: [CGFloat?] = [], in width: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        let gaps = spacing * CGFloat(count - 1)
        let alike = (width - gaps) / CGFloat(count)
        if alike >= readable { return Array(repeating: alike, count: count) }
        // What a saved river's name would have, the others' room aside.
        func wanted(_ index: Int) -> CGFloat? {
            guard named.indices.contains(index), let needed = named[index] else { return nil }
            return min(namedMax, max(needed, namedMin))
        }
        let hover = hovered.flatMap { $0 != current && (0..<count).contains($0) ? $0 : nil }
        let rest = (0..<count).filter { $0 != current && $0 != hover }
        // Left after the one shown and the one under the pointer.
        let room = width - gaps - shownMin - (hover.map { max(pointed, wanted($0) ?? 0) } ?? 0)
        // Saved rivers' names, nearest the one shown first, as many as there
        // is room for at their narrowest with the rest bunched.
        var names = rest.filter { wanted($0) != nil }.sorted { abs($0 - current) < abs($1 - current) }
        let fits = max(0, Int(((room - CGFloat(rest.count) * bunched) / (namedMin - bunched)).rounded(.down)))
        names = Array(names.prefix(fits))
        var widths = [CGFloat](repeating: 0, count: count)
        // Their room shared out: each as much as its name wants, none less than the narrowest.
        var left = room - CGFloat(rest.count - names.count) * bunched
        var unsettled = names
        while !unsettled.isEmpty {
            let share = left / CGFloat(unsettled.count)
            let settled = unsettled.filter { wanted($0)! <= share }
            if settled.isEmpty {
                for index in unsettled { widths[index] = max(namedMin, share) }
                break
            }
            for index in settled { widths[index] = wanted(index)!; left -= wanted(index)! }
            unsettled.removeAll { settled.contains($0) }
        }
        // The rest bunched, tighter down to an icon's width before any scroll.
        let bunchedOnes = rest.filter { !names.contains($0) }
        let each = min(bunched, max(tightest, (room - names.reduce(0) { $0 + widths[$1] }) / CGFloat(max(1, bunchedOnes.count))))
        for index in bunchedOnes { widths[index] = each }
        if let hover { widths[hover] = max(pointed, wanted(hover) ?? 0) }
        let others = widths.enumerated().filter { $0.offset != current }.reduce(0) { $0 + $1.element }
        widths[current] = max(shownMin, width - gaps - others)
        return widths
    }

    static func isBunched(count: Int, in width: CGFloat) -> Bool {
        count > 0 && (width - spacing * CGFloat(count - 1)) / CGFloat(count) < readable
    }
}

/// A window's rivers as tabs in its title bar, as Safari has them, filling
/// what the toolbar's buttons leave of it: each a capsule with its river's
/// name — the one shown standing as the window's title, a click on it Quick
/// Open — closed from its ×, dragged to another place among the others, and
/// from its menu saved, closed, or moved to a window of its own. Many, the
/// others bunch to their icons; the pointer run over them opens each out.
/// Dragged into a card, a tab is written there as a link to its river.
struct RiverTabs: View {
    @Environment(WikiStore.self) private var store
    let rivers: RiverSet
    /// The room the title bar gives the tabs.
    var width: CGFloat
    /// A tab moved to a window of its own: the window to open with it.
    var moveToWindow: (River) -> Void = { _ in }
    @State private var dragged: River?
    /// The tab under the pointer. `WEFT_TAB_HOVER=<n>`, for a snapshot.
    @State private var pointed: Int? = ProcessInfo.processInfo.environment["WEFT_TAB_HOVER"].flatMap(Int.init)

    var body: some View {
        let all = rivers.rivers
        let current = all.firstIndex { $0 === rivers.current } ?? 0
        let widths = TabLayout.widths(count: all.count, current: current, pointed: pointed,
                                      named: all.map { $0.name.map(RiverTab.nameWidth) }, in: width)
        let bunched = TabLayout.isBunched(count: all.count, in: width)
        let strip = HStack(spacing: TabLayout.spacing) {
            ForEach(Array(all.enumerated()), id: \.element.id) { index, river in
                RiverTab(river: river, isCurrent: index == current, closable: all.count > 1,
                         bunched: bunched && index != current && pointed != index && (widths.indices.contains(index) ? widths[index] : 0) < TabLayout.namedMin,
                         hovering: pointed == index) {
                    // At once: no animation to wait out.
                    if river === rivers.current { river.quickOpenShown = true } else { rivers.select(river) }
                } close: {
                    withAnimation(.snappy(duration: 0.2)) { rivers.close(river) }
                }
                .frame(width: widths.indices.contains(index) ? widths[index] : TabLayout.bunched)
                .id(river.id)
                .contextMenu { menu(river) }
                .onDrag {
                    dragged = river
                    // Into a card: a link to the river saved, else its cards' links.
                    return NSItemProvider(object: river.dropped as NSString)
                }
                .onDrop(of: [.text], delegate: TabDrop(target: river, rivers: rivers, dragged: $dragged))
            }
        }
        // The tab under the pointer, as it is run along them: opened out to
        // its name, there to be clicked.
        .overlay {
            PointerTracker { x in
                pointed = x.flatMap { x in
                    var start: CGFloat = 0
                    return widths.indices.first { index in
                        defer { start += widths[index] + TabLayout.spacing }
                        return x < start + widths[index] + TabLayout.spacing / 2
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .animation(.snappy(duration: 0.18), value: pointed)
        .animation(.snappy(duration: 0.2), value: all.map(\.id))
        // More than the room holds, even bunched: scrolled.
        Group {
            if widths.reduce(0, +) + TabLayout.spacing * CGFloat(max(0, all.count - 1)) > width + 1 {
                // The one shown kept in view.
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) { strip }
                        .onAppear { proxy.scrollTo(rivers.current.id) }
                        .onChange(of: rivers.current.id) { withAnimation { proxy.scrollTo(rivers.current.id) } }
                }
            } else {
                strip
            }
        }
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder private func menu(_ river: River) -> some View {
        Button(river.name == nil ? "Save River…" : "Rename River…") {
            rivers.select(river)
            river.naming = river.name.map { .rename($0) } ?? .save
        }
        if let name = river.name {
            Button("Copy Link to River") { Platform.copy(RiverLink.link(name)) }
            Button("Copy River Address") { Platform.copy(RiverLink.url(name).absoluteString) }
        }
        Divider()
        Button("Move Tab to New Window") { moveToWindow(river) }
            .disabled(rivers.rivers.count < 2)
        Button("Close Other Tabs") { withAnimation(.snappy(duration: 0.2)) { rivers.closeOthers(river) } }
            .disabled(rivers.rivers.count < 2)
        Button("Close Tab") { withAnimation(.snappy(duration: 0.2)) { rivers.close(river) } }
            .disabled(rivers.rivers.count < 2)
    }
}

/// One river's tab: its name — slanted for one not saved, named by the card
/// at its top — and, under the pointer, its ×.
private struct RiverTab: View {
    @Environment(WikiStore.self) private var store
    let river: River
    let isCurrent: Bool
    let closable: Bool
    /// Bunched up with the others: its icon alone.
    let bunched: Bool
    /// Under the pointer.
    let hovering: Bool
    let choose: () -> Void
    let close: () -> Void

    /// The room a saved river's tab needs to show its name whole: its
    /// stack, the name, and the room kept for its ×.
    static func nameWidth(_ name: String) -> CGFloat {
        let text = (name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
        return ceil(text) + 12 + 6 + 2 * 20
    }

    /// A saved river's stack; else what its top card is — a day, a wiki page, a note.
    private var symbol: String {
        if river.name != nil { return "square.stack" }
        return river.cards.first.map { store.kind($0).symbol } ?? "rectangle.stack"
    }

    var body: some View {
        ZStack {
            Button(action: choose) {
                HStack(spacing: 6) {
                    if river.name != nil || bunched {
                        Image(systemName: symbol)
                            .font(.system(size: bunched ? 12 : 10, weight: .semibold))
                            .foregroundStyle(Ink.secondary.color)
                    }
                    if !bunched {
                    Text(river.title)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .italic(river.name == nil && !isCurrent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }
                }
                .padding(.horizontal, bunched ? 0 : closable ? 20 : 12)
                .frame(maxWidth: .infinity, minHeight: 26)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isCurrent ? Ink.text.color : Ink.secondary.color)
            .help(isCurrent ? "\(river.title) — click for Quick Open" : river.title)
            if closable, !bunched, hovering || isCurrent {
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 18, height: 18)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Ink.secondary.color)
                    .opacity(hovering ? 1 : 0)
                    .help("Close Tab (⌘W)")
                    Spacer()
                }
                .padding(.leading, 3)
            }
        }
        .background(Capsule().fill(isCurrent ? Ink.text.color.opacity(0.09) : (hovering ? Ink.text.color.opacity(0.05) : .clear)))
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Where the pointer is over a view, followed by AppKit — SwiftUI's hover
/// is not told of it in the title bar — and clicks let through to what is
/// under it.
private struct PointerTracker: NSViewRepresentable {
    /// Its x, or nil once it has left.
    let moved: (CGFloat?) -> Void

    final class Tracker: NSView {
        var moved: (CGFloat?) -> Void = { _ in }

        override init(frame: NSRect) {
            super.init(frame: frame)
            // Once: `.inVisibleRect` keeps it as big as the view, whatever its size.
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func mouseEntered(with event: NSEvent) { moved(convert(event.locationInWindow, from: nil).x) }
        override func mouseMoved(with event: NSEvent) { moved(convert(event.locationInWindow, from: nil).x) }
        override func mouseExited(with event: NSEvent) { moved(nil) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> Tracker { Tracker() }

    func updateNSView(_ view: Tracker, context: Context) { view.moved = moved }
}

/// A tab dropped on another: put where that one is.
private struct TabDrop: DropDelegate {
    let target: River
    let rivers: RiverSet
    @Binding var dragged: River?

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged !== target, let index = rivers.rivers.firstIndex(where: { $0 === target }) else { return }
        withAnimation(.snappy(duration: 0.18)) { rivers.move(dragged, to: index) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}
#endif
