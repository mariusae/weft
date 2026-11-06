#if os(macOS)
import AppKit

/// Keys typed after asking for a card to be written in — ⌘N, then the words
/// at once — before its editor has the caret: held, not lost or given to the
/// card the caret was in, and typed into it once it has the caret. Never
/// for long: given up on, what was held goes where the keys are then.
@MainActor
enum TypeAhead {
    private static var monitor: Any?
    private static var held: [NSEvent] = []
    private static var waitingFor: String?
    private static var deadline: DispatchWorkItem?

    /// A card asked to be written in: what is typed till it is, held for it.
    static func hold(for title: String) {
        waitingFor = title
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                MainActor.assumeIsolated { take(event) }
            }
        }
        deadline?.cancel()
        let work = DispatchWorkItem { release() }
        deadline = work
        // A little longer than an editor tries for the caret.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    /// The card has the caret: what was typed, typed into it.
    static func arrived(_ title: String) {
        guard waitingFor == title else { return }
        release()
    }

    private static func take(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Commands go on as they would — ⌘N again, ⌘W: only typing is held.
        if flags.contains(.command) || flags.contains(.control) { return event }
        // Escape: what was asked for given up, as it would be.
        if event.keyCode == 53 {
            release(replaying: false)
            return event
        }
        held.append(event)
        return nil
    }

    private static func release(replaying: Bool = true) {
        deadline?.cancel()
        deadline = nil
        waitingFor = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        let events = held
        held = []
        guard replaying, !events.isEmpty else { return }
        // Once the caret is settled where it went: typed there, in order.
        DispatchQueue.main.async {
            for event in events { NSApp.sendEvent(event) }
        }
    }
}
#endif
