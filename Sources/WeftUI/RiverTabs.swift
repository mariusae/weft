#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import WeftCore

/// How wide each tab is, in the room the title bar gives: all alike while
/// each can show its name; past that, the others bunched to their icons —
/// the one under the pointer opened out to its name, as Safari does — and
/// the one shown taking what is left.
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

    static func widths(count: Int, current: Int, pointed hovered: Int?, in width: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        let gaps = spacing * CGFloat(count - 1)
        let alike = (width - gaps) / CGFloat(count)
        if alike >= readable { return Array(repeating: alike, count: count) }
        // Bunched tighter, down to an icon's width, before any scroll.
        let fit = (width - gaps - shownMin - (hovered == nil ? 0 : pointed - bunched)) / CGFloat(max(1, count - 1))
        let each = min(bunched, max(tightest, fit))
        var widths = Array(repeating: each, count: count)
        if let hovered, hovered != current, widths.indices.contains(hovered) { widths[hovered] = pointed }
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
        let widths = TabLayout.widths(count: all.count, current: current, pointed: pointed, in: width)
        let bunched = TabLayout.isBunched(count: all.count, in: width)
        let strip = HStack(spacing: TabLayout.spacing) {
            ForEach(Array(all.enumerated()), id: \.element.id) { index, river in
                RiverTab(river: river, isCurrent: index == current, closable: all.count > 1,
                         bunched: bunched && index != current && pointed != index) {
                    if river === rivers.current { river.quickOpenShown = true } else { withAnimation(.snappy(duration: 0.2)) { rivers.select(river) } }
                } close: {
                    withAnimation(.snappy(duration: 0.2)) { rivers.close(river) }
                } hover: { inside in
                    if inside { pointed = index } else if pointed == index { pointed = nil }
                }
                .frame(width: widths.indices.contains(index) ? widths[index] : TabLayout.bunched)
                .id(river.id)
                .contextMenu { menu(river) }
                .onDrag {
                    dragged = river
                    return NSItemProvider(object: river.id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: TabDrop(target: river, rivers: rivers, dragged: $dragged))
            }
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
    let choose: () -> Void
    let close: () -> Void
    let hover: (Bool) -> Void
    @State private var hovering = false

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
        .onHover {
            hovering = $0
            hover($0)
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
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
