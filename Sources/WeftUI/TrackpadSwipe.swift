#if os(macOS)
import AppKit
import SwiftUI

/// Two fingers swiped across the trackpad over a card: the card follows
/// them, as a finger moves it on the phone. Told across how far, and as
/// they lift, how fast — not while it is not to be swiped.
struct TrackpadSwipe: NSViewRepresentable {
    let enabled: Bool
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> Area {
        let area = Area()
        update(area)
        TrackpadSwipes.watch()
        return area
    }

    func updateNSView(_ area: Area, context: Context) { update(area) }

    private func update(_ area: Area) {
        area.enabled = enabled
        area.changed = changed
        area.ended = ended
    }

    /// Where a card is, to swipe it: under it, never in the way of a click.
    final class Area: NSView {
        var enabled = true
        var changed: (CGFloat) -> Void = { _ in }
        var ended: (CGFloat, CGFloat) -> Void = { _, _ in }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { TrackpadSwipes.forget(self) } else { TrackpadSwipes.areas.add(self) }
        }

        /// Whether a point in its window is on it.
        func contains(_ point: NSPoint) -> Bool {
            window != nil && !isHiddenOrHasHiddenAncestor && convert(bounds, to: nil).contains(point)
        }
    }
}

/// The trackpad's swipes over cards, for every window: a swipe that starts
/// over a card and goes across more than down is that card's, all of it —
/// not the river's to scroll, nor to change rivers by.
@MainActor
public enum TrackpadSwipes {
    static let areas = NSHashTable<TrackpadSwipe.Area>.weakObjects()
    private static var monitor: Any?
    /// The card a swipe is over, and how it has gone so far.
    private static weak var swiping: TrackpadSwipe.Area?
    private static var across: CGFloat = 0
    private static var down: CGFloat = 0
    /// Decided: the card's (true), the river's (false); nil, not yet.
    private static var cards: Bool?
    private static var velocity: CGFloat = 0
    private static var last: TimeInterval = 0

    static func watch() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { handle(event) }
        }
    }

    static func forget(_ area: TrackpadSwipe.Area) {
        areas.remove(area)
        if swiping === area { swiping = nil }
    }

    /// The card a swipe from here would be: enabled, under the point.
    static func area(at point: NSPoint, in window: NSWindow) -> TrackpadSwipe.Area? {
        areas.allObjects.first { $0.window === window && $0.enabled && $0.contains(point) }
    }

    /// Whether a scroll is a card's to swipe — so nothing else takes it.
    public static func claims(_ event: NSEvent) -> Bool {
        guard let (window, point) = place(of: event) else { return false }
        // Begun over a card: its, whoever is asked first.
        if event.phase.contains(.began) { return area(at: point, in: window) != nil }
        return swiping != nil && cards != false
    }

    /// The window a scroll is in, and where in it: one the window server did
    /// not route — sent by the app itself — by the window under it.
    private static func place(of event: NSEvent) -> (NSWindow, NSPoint)? {
        if let window = event.window { return (window, event.locationInWindow) }
        let screen = event.locationInWindow
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.contains(screen) }) else { return nil }
        return (window, window.convertPoint(fromScreen: screen))
    }

    private static func handle(_ event: NSEvent) -> NSEvent? {
        guard event.hasPreciseScrollingDeltas, let (window, point) = place(of: event) else { return event }
        // The fingers lifted: what follows on is not the card's to move.
        if !event.momentumPhase.isEmpty { return cards == true ? nil : event }
        if event.phase.contains(.began) {
            swiping = area(at: point, in: window)
            across = 0
            down = 0
            cards = swiping == nil ? false : nil
            velocity = 0
            last = event.timestamp
        }
        guard let area = swiping else { return event }
        // Which way the fingers went, whichever way scrolling goes.
        let fingers = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        if event.phase.contains(.changed) || event.phase.contains(.began) {
            across += fingers
            down += abs(event.scrollingDeltaY)
            let elapsed = max(0.001, event.timestamp - last)
            velocity = velocity * 0.6 + (fingers / elapsed) * 0.4
            last = event.timestamp
            if cards == nil, abs(across) + down > 6 {
                // More across than down: the card's; else the river scrolls.
                cards = abs(across) > down * 1.3
            }
            guard cards == true else { return event }
            area.changed(across)
            return nil
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            defer { swiping = nil }
            guard cards == true else { return event }
            area.ended(across, velocity)
            return nil
        }
        return cards == true ? nil : event
    }
}
#endif
