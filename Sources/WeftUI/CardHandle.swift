#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A card's handle, in its title's gutter — where the outline's marks are
/// — what it is at a glance: a thing to do's ring; else its own icon, a
/// day's calendar, or a note. Clicked, its menu, as a right-click gives — a
/// ring, checked off instead, its menu a right-click; dragged, the card goes
/// with the pointer to elsewhere in the river. The menu is the
/// `contextMenu` put on it.
struct CardHandle<Face: View>: View {
    let title: String
    /// What it is called, as dragged.
    let shown: String
    /// Its column's width.
    var width: CGFloat = Measures.gutter
    var help = "Click for what can be done with it, double-click to fold it — drag to move it"
    /// A click's, if not its menu.
    var onClick: (() -> Void)? = nil
    /// Two clicks': with it, one click's waits to see whether a second follows.
    var onDoubleClick: (() -> Void)? = nil
    /// What it shows, under the pointer or not.
    @ViewBuilder var face: (_ hovered: Bool) -> Face
    @State private var hovered = false

    var body: some View {
        face(hovered)
            .frame(width: width, height: Measures.markSize + 8)
            .background {
                RoundedRectangle(cornerRadius: Measures.controlRadius)
                    .fill(Ink.text.color.opacity(hovered && onClick == nil ? 0.08 : 0))
                    .frame(width: Measures.markSize + 8)
            }
            .overlay { HandlePointer(title: title, shown: shown, onClick: onClick, onDoubleClick: onDoubleClick) }
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
            .help(help)
            .accessibilityElement()
            .accessibilityLabel("\(shown): More")
            .accessibilityAddTraits(.isButton)
    }
}

extension CardHandle where Face == HandleGlyph {
    /// A handle showing a symbol: faint till the pointer is on it.
    init(symbol: String, title: String, shown: String, width: CGFloat = Measures.gutter, onDoubleClick: (() -> Void)? = nil) {
        self.init(title: title, shown: shown, width: width, onDoubleClick: onDoubleClick) { HandleGlyph(symbol: symbol, hovered: $0) }
    }
}

struct HandleGlyph: View {
    let symbol: String
    let hovered: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: Measures.markSize * 0.92))
            .foregroundStyle(Ink.secondary.color)
            .opacity(hovered ? 1 : 0.65)
    }
}

/// What the pointer does with a handle: a click its menu — as a right-click
/// would show it, from the `contextMenu` round it — a drag, its card.
private struct HandlePointer: NSViewRepresentable {
    let title: String
    let shown: String
    let onClick: (() -> Void)?
    let onDoubleClick: (() -> Void)?

    func makeNSView(context: Context) -> HandlePointerView { HandlePointerView() }

    func updateNSView(_ view: HandlePointerView, context: Context) {
        view.title = title
        view.shown = shown
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
    }
}

final class HandlePointerView: NSView, NSDraggingSource {
    var title = ""
    var shown = ""
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    /// How long one click waits for a second: the system's, but not so
    /// long that the menu is slow to come.
    private var doubleClickWait: TimeInterval { min(NSEvent.doubleClickInterval, 0.3) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: onClick == nil ? .pointingHand : .arrow) }

    /// The menu a click shows, waiting to see whether a second click comes.
    private var pendingMenu: DispatchWorkItem?

    override func mouseDown(with event: NSEvent) {
        // The second click of two: its double-click's, not the menu the first
        // was about to show.
        if event.clickCount >= 2, let onDoubleClick, let pending = pendingMenu {
            pending.cancel()
            pendingMenu = nil
            _ = window?.nextEvent(matching: [.leftMouseUp])
            onDoubleClick()
            return
        }
        let start = event.locationInWindow
        // Held till it is let go, or moved far enough to be a drag.
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                if let onClick { onClick(); return }
                guard onDoubleClick != nil else { showMenu(for: event); return }
                // A second click may come — its double-click's, not the menu,
                // which shown at once it would land in: the menu a moment
                // later, the app going on meanwhile, not held waiting.
                let menu = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    pendingMenu = nil
                    showMenu(for: event)
                }
                pendingMenu = menu
                DispatchQueue.main.asyncAfter(deadline: .now() + doubleClickWait, execute: menu)
                return
            }
            let point = next.locationInWindow
            if hypot(point.x - start.x, point.y - start.y) > 3 {
                drag(from: event)
                return
            }
        }
    }

    /// Its menu: what a right-click there shows — the `contextMenu` the
    /// handle is in, which is the card's.
    private func showMenu(for event: NSEvent) {
        guard let right = NSEvent.mouseEvent(with: .rightMouseDown, location: event.locationInWindow,
                                             modifierFlags: event.modifierFlags, timestamp: event.timestamp,
                                             windowNumber: event.windowNumber, context: nil,
                                             eventNumber: event.eventNumber, clickCount: 1, pressure: 1) else { return }
        rightMouseDown(with: right)
    }

    /// The card dragged, as by its title: only weft takes what is dragged.
    private func drag(from event: NSEvent) {
        let item = NSPasteboardItem()
        item.setData(Data(title.utf8), forType: NSPasteboard.PasteboardType(UTType.weftCard.identifier))
        let dragging = NSDraggingItem(pasteboardWriter: item)
        let picture = preview
        let at = convert(event.locationInWindow, from: nil)
        dragging.setDraggingFrame(NSRect(x: at.x - 12, y: at.y - picture.size.height / 2,
                                         width: picture.size.width, height: picture.size.height), contents: picture)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }

    /// What is seen going with the pointer: the card's name, on a card.
    private var preview: NSImage {
        let name = shown.count > 48 ? shown.prefix(47) + "…" : shown
        let renderer = ImageRenderer(content: Text(name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Ink.text.color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 9)))
        renderer.scale = window?.backingScaleFactor ?? 2
        return renderer.nsImage ?? NSImage(size: NSSize(width: 1, height: 1))
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
}
#endif
