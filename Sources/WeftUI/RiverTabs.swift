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
    /// Inside the title bar's glass round them, at its ends: as much as it
    /// leaves over and under them, so the one shown sits in it evenly.
    static let inset: CGFloat = 5
    /// Between the tabs and the toolbar's buttons, their glass and all.
    static let gap: CGFloat = 8
    /// After the toolbar's buttons, to the window's edge.
    static let trailing: CGFloat = 20
    /// A bunched tab: its icon alone.
    static let bunched: CGFloat = 34
    /// The narrowest a tab still shows its name.
    static let readable: CGFloat = 112
    /// The one shown, never narrower; a bunched tab under the pointer, this wide.
    static let shownMin: CGFloat = 150
    static let pointed: CGFloat = 150
    /// A bunched tab at its tightest.
    static let tightest: CGFloat = 24
    /// What the toolbar puts round each of its buttons besides the button:
    /// its glass, and the space between.
    static let buttonSlot: CGFloat = 12
    /// A toolbar button not yet measured — or measured, then put away in
    /// the toolbar's overflow, where it is not.
    static let buttonGuess: CGFloat = 32

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
    /// The room the title bar should give the tabs, as reckoned from the
    /// window: at most what they take — less, when the toolbar has less.
    var width: CGFloat
    /// A tab moved to a window of its own: the window to open with it.
    var moveToWindow: (River) -> Void = { _ in }
    @State private var dragged: River?
    /// The tab under the pointer. `WEFT_TAB_HOVER=<n>`, for a snapshot.
    @State private var pointed: Int? = ProcessInfo.processInfo.environment["WEFT_TAB_HOVER"].flatMap(Int.init)
    /// Where in the window the strip is, as laid out.
    @State private var spot: WindowPlace.Spot?
    /// What the toolbar has been found to want besides what is reckoned:
    /// grown each time the tabs, given the room reckoned, were put away in
    /// its overflow — else they'd come back, be given it again, and go
    /// again, over and over: the tabs shaking.
    @State private var slack: CGFloat = 0
    /// The same, given the room the buttons were found to take: for this
    /// width of window only — at another, found again.
    @State private var fitSlack: CGFloat = 0

    /// Placed, or put away. Put away by the toolbar, with no change in the
    /// window's width: they were given too much.
    private func placed(_ new: WindowPlace.Spot?) {
        if let new, new.window != spot?.window { fitSlack = 0 }
        if new == nil, spot != nil { overflowed() }
        spot = new
    }

    /// Something put away in the toolbar's overflow: less asked for next time.
    private func overflowed() {
        // Given the room the buttons were found to take: that was too much,
        // at this width. Else, as reckoned, the reckoning was.
        if spot?.buttons != nil {
            fitSlack = min(fitSlack + 8, 120)
        } else {
            slack = min(slack + 16, 240)
        }
    }

    /// The room the window leaves the tabs: from where they begin to its
    /// right edge, all but what the toolbar's buttons after them take and
    /// a margin — the buttons as the toolbar placed them, from the first to
    /// the last; one put away in its overflow, each as wide as it says and
    /// the space reckoned round it. Else, till the strip is placed, as
    /// reckoned.
    private var room: CGFloat {
        guard let spot, !rivers.toolbarButtons.isEmpty else { return width }
        // The buttons found where the toolbar put them: from the first's
        // left to the last's right, their glass and the space between.
        if let buttons = spot.buttons {
            return max(TabLayout.shownMin, (spot.window - spot.minX - TabLayout.gap - buttons - TabLayout.trailing - fitSlack).rounded(.down))
        }
        // Every button the toolbar has, shown or not: one put away in its
        // overflow counted still, so the tabs give its room back.
        var shown = ["new", "inspector"]
        if !store.conflicted().isEmpty { shown.append("review") }
        let buttons = shown.reduce(0) { $0 + (rivers.toolbarButtons[$1] ?? TabLayout.buttonGuess) + TabLayout.buttonSlot }
        // In whole points: else half a point either way moves the toolbar's
        // items, which moves the strip, which gives it the other half again.
        return max(TabLayout.shownMin, (spot.window - spot.minX - TabLayout.gap - buttons - TabLayout.trailing - slack).rounded(.down))
    }

    var body: some View {
        let width = room - 2 * TabLayout.inset
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
                    // At once: no animation to wait out. The tab in front
                    // clicked: its start page, to put another river in its
                    // place — clicked again, put away.
                    if river === rivers.current { river.startShown.toggle() } else { rivers.select(river) }
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
        .padding(.horizontal, TabLayout.inset)
        // Out of the window — put in the toolbar's overflow — its room
        // reckoned again, from the window, till it is placed once more.
        .background(WindowPlace { placed($0) })
        // Saved Rivers (⇧⌘R): from the tabs, now the title bar has no button of its own for them.
        .popover(isPresented: Binding(get: { rivers.current.riversShown }, set: { rivers.current.riversShown = $0 }), arrowEdge: .bottom) {
            RiversPanel().frame(width: 320).environment(rivers.current)
        }
        // The last button found, or put away in the overflow.

    }

    @ViewBuilder private func menu(_ river: River) -> some View {
        Button(river.name == nil ? "Save River…" : "Rename River…") {
            rivers.select(river)
            river.naming = river.name.map { .rename($0) } ?? .save
        }
        if let name = river.name {
            Button("Choose River Icon…") {
                rivers.select(river)
                river.choosingIcon = true
            }
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

    private var symbol: String { river.symbol(in: store) }

    var body: some View {
        ZStack {
            Button(action: choose) {
                HStack(spacing: 6) {
                    if river.name != nil || bunched {
                        Image(systemName: symbol)
                            .font(.system(size: bunched ? 12 : 10, weight: .semibold))
                            .foregroundStyle(river.color == nil ? Ink.secondary.color : RiverColor.color(river.color))
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
                    .pointing()
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
/// Where a view is in its window, from its left — told as the window
/// changes size, as the view is laid out, and nil once it leaves: for
/// views in different parts of the toolbar, which SwiftUI can't compare.
struct WindowPlace: NSViewRepresentable {
    /// Its left and right in its window, and the window's width.
    struct Spot: Equatable {
        var minX: CGFloat
        var maxX: CGFloat
        var window: CGFloat
        /// What the toolbar's items after it take, as placed: nil, one of
        /// them put away in its overflow.
        var buttons: CGFloat? = nil
    }
    let told: (Spot?) -> Void

    final class Place: NSView {
        var told: (Spot?) -> Void = { _ in }
        private var last: Spot?
        private var resizing: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let resizing { NotificationCenter.default.removeObserver(resizing) }
            resizing = nil
            guard let window else {
                last = nil
                told(nil)
                return
            }
            resizing = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.tell() }
            }
            tell()
        }

        override func layout() {
            super.layout()
            tell()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// How wide the toolbar's items after a frame are, as placed — from
        /// the first's left to the last's right: nil, one of them put away.
        static func buttons(after frame: NSRect, in window: NSWindow) -> CGFloat? {
            var placed: [NSRect] = []
            for item in window.toolbar?.items ?? [] where item.isVisible {
                guard let view = item.view else { continue }
                // In the overflow: out of the window.
                guard view.window === window else { return nil }
                let found = view.convert(view.bounds, to: nil)
                if found.width > 0, found.minX >= frame.maxX - 1 { placed.append(found) }
            }
            guard let first = placed.map(\.minX).min(), let last = placed.map(\.maxX).max() else { return nil }
            return last - first
        }

        func tell() {
            guard window != nil else { return }
            // Once the toolbar has placed it.
            DispatchQueue.main.async { [self] in
                guard let window else { return }
                let frame = convert(bounds, to: nil)
                let spot = Spot(minX: frame.minX, maxX: frame.maxX, window: window.frame.width,
                                buttons: Self.buttons(after: frame, in: window))
                // Moved by less than a point and a half, not moved: a strip
                // placed a half point off as it is resized, and back as it
                // is again, would never be still.
                if let last, last.window == spot.window, abs(last.minX - spot.minX) < 1.5, abs(last.maxX - spot.maxX) < 1.5,
                   (last.buttons == nil) == (spot.buttons == nil), abs((last.buttons ?? 0) - (spot.buttons ?? 0)) < 1.5 { return }
                last = spot
                told(spot)
            }
        }
    }

    func makeNSView(context: Context) -> Place {
        let place = Place()
        place.told = told
        return place
    }

    func updateNSView(_ place: Place, context: Context) {
        place.told = told
        place.tell()
    }
}

extension View {
    /// Says how wide it is, as one of the toolbar's buttons after the tabs:
    /// what they take of the room — gone, nothing.
    func toolbarButton(_ name: String, in rivers: RiverSet?) -> some View {
        // Kept when it goes — into the overflow, say — to give it its room back.
        onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rivers?.toolbarButtons[name] = $0 }
    }
}
#endif
