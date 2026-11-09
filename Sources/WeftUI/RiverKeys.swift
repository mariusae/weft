#if os(macOS)
import AppKit
import SwiftUI

/// The river by its keys, when nothing is being typed in — as Mail's list
/// and Things' are: ↑ and ↓ choose the card before or after, Space folds
/// it or opens it again, Return writes in it, ⌘⌫ deletes it. Keys that
/// something else wants — a field, a list, the outline — go on to it.
struct RiverKeys: NSViewRepresentable {
    let river: River

    func makeNSView(context: Context) -> RiverKeysView { RiverKeysView() }

    func updateNSView(_ view: RiverKeysView, context: Context) { view.river = river }

    static func dismantleNSView(_ view: RiverKeysView, coordinator: ()) { view.stop() }
}

final class RiverKeysView: NSView {
    weak var river: River?
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.take(event) ?? event }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Whether the keys belong to something else: words being typed, a
    /// list or a field with a selection of its own.
    private static func busy(_ responder: NSResponder?) -> Bool {
        responder is NSText || responder is NSTableView || responder is NSCollectionView
            || (responder is NSControl && !(responder is NSButton))
    }

    private func take(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, let river, !Self.busy(window.firstResponder) else { return event }
        // Over the river, something asked: its keys.
        if river.quickOpenShown || river.homing != nil || river.riversShown || river.startShown { return event }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        // ⌘⌫, as the Finder's: the selected card's tiddler deleted — Undo
        // brings it back. In words being written, the line's start, as ever.
        if flags == .command, event.keyCode == 51 {
            // Only a card chosen — shown so — never the one that happens to
            // be at the top of the river.
            guard let card = river.chosen, river.store.tiddler(card) != nil, !river.store.isShadow(card) else { return event }
            withAnimation { river.store.delete(card) }
            return nil
        }
        guard flags.isEmpty else { return event }
        switch event.keyCode {
        case 126: // ↑
            river.step(-1)
        case 125: // ↓
            river.step(1)
        case 49: // Space
            guard let card = river.selected else { return event }
            river.select(card)
            withAnimation(.snappy(duration: 0.22)) { river.toggleFold(card) }
        case 36, 76: // Return
            guard let card = river.selected else { return event }
            withAnimation(.snappy(duration: 0.22)) {
                if river.isFolded(card) { river.toggleFold(card) }
                river.edit(card)
            }
        default:
            return event
        }
        return nil
    }
}
#endif
