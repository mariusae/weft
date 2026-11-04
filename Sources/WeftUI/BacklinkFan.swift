import SwiftUI
import WeftCore

/// What links to a card, at its foot, as Manifold shows a block's links:
/// each a small face — a tiddler's, a note's, a day's — bunched, the most
/// recent in front and the edges of two more behind it. The pointer on
/// them deals them out in a row; resting on one shows its summary above
/// it, with the words around its link; a click opens it beside the card.
/// More than fit, the last is a stack of the rest, a menu of them.
struct BacklinkFan: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    let card: String
    let links: [LinkTarget]
    /// `WEFT_FAN=<n>` deals them out and rests on the nth, for a snapshot.
    @State private var fanned = ProcessInfo.processInfo.environment["WEFT_FAN"] != nil
    @State private var resting: Int? = ProcessInfo.processInfo.environment["WEFT_FAN"].flatMap { Int($0) }
    @State private var restTask: Task<Void, Never>?

    /// A face's side, how far each one behind peeks out folded, and the
    /// step between them dealt out.
    private let face: CGFloat = 26
    private let peek: CGFloat = 5
    private let step: CGFloat = 32
    /// The most dealt out one by one: past that, the last is a stack.
    private let mostShown = 8

    private var singles: Int { links.count <= mostShown ? links.count : mostShown - 1 }
    private var overflow: Int { links.count - singles }
    private var places: Int { singles + (overflow > 0 ? 1 : 0) }

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                ForEach(Array(links.prefix(singles).enumerated()), id: \.element) { index, link in
                    Face(target: link, depth: fanned ? 0 : min(index, 2), highlighted: resting == index)
                        .offset(x: fanned ? CGFloat(index) * step : CGFloat(min(index, 2)) * peek)
                        .opacity(fanned || index < 3 ? 1 : 0)
                        .zIndex(Double(links.count - index))
                        .onHover { inside in rest(inside ? index : nil) }
                        .onTapGesture { river.open(link.title, from: card) }
                        .help(link.shown)
                }
                if overflow > 0 {
                    Menu {
                        ForEach(links.suffix(overflow), id: \.self) { link in
                            Button { river.open(link.title, from: card) } label: { Label(link.shown, systemImage: link.symbol) }
                        }
                    } label: {
                        Text("+\(overflow)")
                            .font(.caption2.weight(.semibold))
                            .frame(width: face, height: face)
                            .background(Ink.shelf.color, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Ink.rule.color))
                    }
                    #if os(macOS)
                    .menuStyle(.button)
                    #endif
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .offset(x: fanned ? CGFloat(singles) * step : CGFloat(min(singles, 2)) * peek)
                    .opacity(fanned ? 1 : 0)
                }
            }
            .frame(width: fanned ? face + CGFloat(places - 1) * step : face + CGFloat(min(links.count - 1, 2)) * peek,
                   height: face, alignment: .leading)
            .overlay(alignment: .bottomLeading) {
                if let resting, resting < links.count {
                    Summary(target: links[resting], context: store.context(of: links[resting], linkingTo: card))
                        .alignmentGuide(.bottom) { $0[.bottom] + face + 8 }
                        .offset(x: CGFloat(resting) * step)
                        .transition(.opacity.combined(with: .offset(y: 4)))
                        .allowsHitTesting(false)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(Ink.secondary.color)
                .opacity(fanned ? 0 : 1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.snappy(duration: inside ? 0.25 : 0.2)) { fanned = inside }
            if !inside { rest(nil) }
        }
        .zIndex(resting == nil ? 0 : 1)
    }

    private var label: String {
        links.count == 1 ? "1 link here" : "\(links.count) links here"
    }

    /// The pointer on a face: its summary after a moment's rest — at once
    /// when one shows already, moving along the faces.
    private func rest(_ index: Int?) {
        restTask?.cancel()
        guard let index else {
            withAnimation(.easeOut(duration: 0.12)) { resting = nil }
            return
        }
        if resting != nil {
            resting = index
            return
        }
        restTask = Task {
            try? await Task.sleep(for: .seconds(0.15))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { resting = index }
        }
    }

    /// One linking tiddler, note or day: its kind's symbol on a small
    /// rounded square, a shade darker for each one behind, so the front leads.
    private struct Face: View {
        let target: LinkTarget
        let depth: Int
        let highlighted: Bool

        var body: some View {
            Image(systemName: target.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(depth == 0 ? Ink.accent.color : .clear)
                .frame(width: 26, height: 26)
                .background(depth == 0 ? Ink.card.color : Ink.shelf.color.opacity(1 - Double(depth) * 0.15),
                            in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(highlighted ? Ink.accent.color : Ink.rule.color, lineWidth: highlighted ? 1.5 : 1))
                .shadow(color: .black.opacity(depth == 0 ? 0.08 : 0), radius: 2, y: 1)
                .contentShape(Rectangle())
        }
    }

    /// A linking tiddler's summary: its title, what it is, and the words
    /// around its link.
    private struct Summary: View {
        let target: LinkTarget
        let context: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Label(target.shown, systemImage: target.symbol)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(target.kind.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Ink.secondary.color)
                    .textCase(.uppercase)
                if let context, !context.isEmpty {
                    Text(context)
                        .font(.callout)
                        .foregroundStyle(Ink.secondary.color)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(width: 280, alignment: .leading)
            .background(Ink.card.color, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.rule.color))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }
}
