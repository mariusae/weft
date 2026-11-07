import SwiftUI
#if os(macOS)
import AppKit

/// A cursor for the room it is laid over, clicks going through it to what
/// is under it. Its own: a text view under it — a card's words, under a
/// control floating over them, or under the rail — would otherwise give
/// its I-beam through it.
struct CursorArea: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorAreaView {
        let view = CursorAreaView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ view: CursorAreaView, context: Context) {
        guard view.cursor != cursor else { return }
        view.cursor = cursor
        view.window?.invalidateCursorRects(for: view)
    }
}

final class CursorAreaView: NSView {
    var cursor = NSCursor.arrow

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }
}
#endif

extension View {
    /// Under the pointer, a hand: a click here does something — a control,
    /// a link, a chip.
    func pointing() -> some View {
        #if os(macOS)
        overlay { CursorArea(cursor: .pointingHand).allowsHitTesting(false) }
        #else
        self
        #endif
    }

    /// Under the pointer, the arrow: what is over a text view — the rail —
    /// not its I-beam.
    func arrowCursor() -> some View {
        #if os(macOS)
        background { CursorArea(cursor: .arrow).allowsHitTesting(false) }
        #else
        self
        #endif
    }
}
