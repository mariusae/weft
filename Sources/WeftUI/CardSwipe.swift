#if os(iOS)
import SwiftUI
import UIKit

/// A card's actions under it, revealed by swiping it aside, as Overcast's
/// and Tweetbot's rows have them: a short swipe opens it to show two, to
/// tap; a long one does the outer — the first given — at once.
struct SwipeAction {
    let name: String
    let symbol: String
    let tint: Color
    let run: () -> Void
}

extension View {
    /// Swiped from the leading edge, `leading`'s; from the trailing, `trailing`'s
    /// — each list the outer first. Not while `enabled` is false.
    func cardSwipe(leading: [SwipeAction], trailing: [SwipeAction], enabled: Bool) -> some View {
        modifier(CardSwipe(leading: leading, trailing: trailing, enabled: enabled))
    }
}

private struct CardSwipe: ViewModifier {
    let leading: [SwipeAction]
    let trailing: [SwipeAction]
    let enabled: Bool
    /// How far the card is swiped: right of where it rests, positive.
    @State private var offset: CGFloat = 0
    /// Where it rests between swipes: closed, or open on a side.
    @State private var rest: CGFloat = 0
    @State private var width: CGFloat = 360
    /// Past the point a long swipe does the outer action: told once, with a tick.
    @State private var committing = false

    private static let button: CGFloat = 76
    private static let gap: CGFloat = 6
    private var opened: CGFloat { Self.button * 2 + Self.gap }
    /// How far a long swipe goes before letting go does the outer action.
    private var commit: CGFloat { max(opened + 40, width * 0.55) }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .leading) { if offset > 0 { actions(leading, side: .leading) } }
            .background(alignment: .trailing) { if offset < 0 { actions(trailing, side: .trailing) } }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .gesture(HorizontalPan(enabled: enabled) { dx in
                drag(dx)
            } ended: { dx, velocity in
                end(dx, velocity: velocity)
            })
            // Open, a tap on the card closes it again — not what the tap would do.
            .overlay {
                if rest != 0 {
                    Color.clear.contentShape(Rectangle()).onTapGesture { settle(0) }
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: committing) { _, now in now }
            .onChange(of: enabled) { _, now in if !now { settle(0) } }
    }

    private enum Side { case leading, trailing }

    /// The actions on a side, at their own width behind the card, the
    /// outer at the edge — uncovered as the card slides off them. Swiped
    /// past the point of doing it, the outer takes all the room.
    private func actions(_ list: [SwipeAction], side: Side) -> some View {
        let shown = abs(offset)
        let ordered = side == .leading ? list : Array(list.reversed())
        return HStack(spacing: Self.gap) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { index, action in
                let outer = side == .leading ? index == 0 : index == ordered.count - 1
                if !committing || outer {
                    Button {
                        settle(0)
                        action.run()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: action.symbol).font(.system(size: 20, weight: .semibold))
                            Text(action.name).font(.caption2.weight(.semibold)).lineLimit(1).fixedSize()
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(action.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(width: committing ? max(Self.button, shown - Self.gap) : Self.button)
                    .accessibilityLabel(action.name)
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: committing)
    }

    private func drag(_ dx: CGFloat) {
        var next = rest + dx
        // Nothing to show on a side: barely moves.
        if next > 0, leading.isEmpty { next *= 0.15 }
        if next < 0, trailing.isEmpty { next *= 0.15 }
        offset = next
        let past = (next > 0 && !leading.isEmpty || next < 0 && !trailing.isEmpty) && abs(next) > commit
        if past != committing { committing = past }
    }

    private func end(_ dx: CGFloat, velocity: CGFloat) {
        let final = rest + dx
        if committing {
            let action = final > 0 ? leading.first : trailing.first
            committing = false
            settle(0)
            action?.run()
            return
        }
        // Flung or let go far enough: open on that side; else closed.
        let flung = abs(velocity) > 600
        if final > 40 || (flung && velocity > 0 && final > 0), !leading.isEmpty {
            settle(opened)
        } else if final < -40 || (flung && velocity < 0 && final < 0), !trailing.isEmpty {
            settle(-opened)
        } else {
            settle(0)
        }
    }

    private func settle(_ to: CGFloat) {
        rest = to
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { offset = to }
    }
}

/// A pan that begins only when it goes across more than down — so the
/// river still scrolls under a finger moving down a card.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let enabled: Bool
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = enabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dx = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .changed: changed(dx)
        case .ended, .cancelled, .failed: ended(dx, recognizer.velocity(in: recognizer.view).x)
        default: break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.4
        }
    }
}
#endif
