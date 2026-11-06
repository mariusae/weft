import Observation
#if os(macOS)
import AppKit

/// While typing, the controls that come under the pointer put away — till
/// the pointer moves again, as the Mac hides the pointer itself: the pointer
/// resting by the words is not asking for them.
@MainActor @Observable
final class TypingQuiet {
    static let shared = TypingQuiet()

    /// Typed since the pointer last moved.
    private(set) var quiet = false
    /// How many clicks there have been: a control's tip not shown after one.
    @ObservationIgnored private(set) var clicks = 0
    @ObservationIgnored private var moved: CGFloat = 0
    @ObservationIgnored private var monitor: Any?

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.take(event) }
            return event
        }
    }

    private func take(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            // A command is not typing: ⌘N, ⌘W.
            guard !event.modifierFlags.contains(.command) else { return }
            if !quiet {
                quiet = true
                moved = 0
                // Told the pointer moves, to know when it does.
                event.window?.acceptsMouseMovedEvents = true
            }
        case .mouseMoved:
            guard quiet else { return }
            // More than a nudge of the hand on the trackpad.
            moved += abs(event.deltaX) + abs(event.deltaY)
            if moved > 6 { quiet = false }
        default:
            if event.type == .leftMouseDown || event.type == .rightMouseDown { clicks += 1 }
            if quiet { quiet = false }
        }
    }
}
#endif
