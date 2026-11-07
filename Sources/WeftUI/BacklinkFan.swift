import SwiftUI
import WeftCore

/// What links to a card, at its foot, as Manifold shows a block's links:
/// each a small face — a tiddler's, a note's, a day's — bunched, the most
/// recent in front and the edges of two more behind it. The pointer on
/// them deals them out in a row; resting on one shows its summary above
/// it, with the words around its link; a click opens it beside the card.
/// More than fit, the last is a stack of the rest, a menu of them. On the
/// phone, with no pointer, a tap deals them out, and another opens one.
/// Dealt out, Open All opens every one of them beside the card.
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
                        .onTapGesture {
                            #if os(iOS)
                            // Bunched, a tap deals them out; dealt out, it opens the one tapped.
                            guard fanned else { return withAnimation(.snappy(duration: 0.25)) { fanned = true } }
                            #endif
                            river.open(link.title, from: card)
                        }
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
                    .pointing()
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
            ZStack(alignment: .leading) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Ink.secondary.color)
                    .opacity(fanned ? 0 : 1)
                // Dealt out, every one of them a tap away.
                if fanned, links.count > 1 {
                    Button(action: openAll) {
                        Label("Open All", systemImage: "rectangle.stack")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .foregroundStyle(Ink.accent.color)
                            .background(Ink.accent.color.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointing()
                    .help("Open every page linking here, after this card")
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        #if os(iOS)
        // On the phone: a tap by them, dealt out, gathers them again; bunched, deals them out.
        .onTapGesture { withAnimation(.snappy(duration: 0.25)) { fanned.toggle() } }
        #endif
        .onHover { inside in
            withAnimation(.snappy(duration: inside ? 0.25 : 0.2)) { fanned = inside }
            if !inside { rest(nil) }
        }
        .zIndex(resting == nil ? 0 : 1)
    }

    /// Every page linking here, opened after the card, in their order.
    private func openAll() {
        withAnimation(.snappy(duration: 0.28)) {
            for link in links.reversed() { river.open(link.title, from: card) }
            fanned = false
        }
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
    fileprivate struct Face: View {
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

#if os(iOS)
/// On the phone, what links to a card — where nothing rests on a face to
/// say which page it is. Gathered, its foot names them: “Linked from
/// Garden, Reading and 2 more”. Tapped, they open out under it, a list:
/// each one's icon, its name, and the words around its link to the card;
/// tapped, opened after it. Held, one shows itself, to be read without
/// opening it.
struct PhoneBacklinks: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    let card: String
    let links: [LinkTarget]
    /// `WEFT_FAN` opens them out, for a snapshot.
    @State private var open = ProcessInfo.processInfo.environment["WEFT_FAN"] != nil
    @State private var all = false
    /// How many are listed before the rest are asked for.
    private let first = 5

    private var listed: [LinkTarget] { all ? links : Array(links.prefix(first)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    open.toggle()
                    if !open { all = false }
                }
            } label: {
                HStack(spacing: 10) {
                    bunch
                    names
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Ink.faint.color)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Hide the pages linking here" : "Show the pages linking here")
            if open {
                VStack(spacing: 0) {
                    ForEach(Array(listed.enumerated()), id: \.element) { index, link in
                        if index > 0 { Divider().padding(.leading, 42) }
                        row(link)
                    }
                    if links.count > listed.count {
                        Divider().padding(.leading, 42)
                        Button { withAnimation(.snappy(duration: 0.25)) { all = true } } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "ellipsis")
                                    .frame(width: 20)
                                Text("\(links.count - listed.count) more")
                                Spacer(minLength: 0)
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Ink.accent.color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Ink.text.color.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .transition(.opacity)
                if links.count > 1 {
                    Button(action: openAll) {
                        Label("Open All", systemImage: "rectangle.stack")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .foregroundStyle(Ink.accent.color)
                            .background(Ink.accent.color.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
        }
    }

    /// The first three faces, bunched, the most recent in front.
    private var bunch: some View {
        let shown = Array(links.prefix(3))
        return ZStack(alignment: .leading) {
            ForEach(Array(shown.enumerated()), id: \.element) { index, link in
                BacklinkFan.Face(target: link, depth: index, highlighted: false)
                    .offset(x: CGFloat(index) * 5)
                    .zIndex(Double(shown.count - index))
            }
        }
        .frame(width: 26 + CGFloat(shown.count - 1) * 5, height: 26, alignment: .leading)
    }

    /// Who links here, by name: the first two, and how many more.
    private var names: some View {
        let a = Self.short(links[0].shown)
        let text: Text = switch links.count {
        case 1: Text("Linked from \(Text(a).foregroundStyle(Ink.text.color))")
        case 2: Text("Linked from \(Text(a).foregroundStyle(Ink.text.color)) and \(Text(Self.short(links[1].shown)).foregroundStyle(Ink.text.color))")
        default: Text("Linked from \(Text(a).foregroundStyle(Ink.text.color)), \(Text(Self.short(links[1].shown)).foregroundStyle(Ink.text.color)) and \(links.count - 2) more")
        }
        return text
            .font(.footnote)
            .foregroundStyle(Ink.secondary.color)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    /// A name cut short enough for two of them to fit beside each other.
    private static func short(_ name: String) -> String {
        name.count <= 28 ? name : String(name.prefix(26)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// One page linking here: its icon, its name, the words around its link.
    private func row(_ link: LinkTarget) -> some View {
        let context = store.context(of: link, linkingTo: card)?.trimmingCharacters(in: .whitespaces)
        let says = context.flatMap { words in
            // Only the link, and nothing around it, says nothing more.
            words.isEmpty || words.caseInsensitiveCompare(store.shownTitle(card)) == .orderedSame ? nil : words
        }
        return Button { river.open(link.title, from: card) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: link.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.accent.color)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.shown)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ink.text.color)
                        .lineLimit(1)
                    if let says {
                        Text(says)
                            .font(.footnote)
                            .foregroundStyle(Ink.secondary.color)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.square") { river.open(link.title, from: card) }
            if links.count > 1 {
                Button("Open All", systemImage: "rectangle.stack") { openAll() }
            }
            Button("Copy Link", systemImage: "link") { UIPasteboard.general.string = "[[\(link.title)]]" }
        } preview: {
            LinkPreview(target: link)
                .environment(store)
                .environment(river)
        }
    }

    /// Every page linking here, opened after the card, in their order.
    private func openAll() {
        withAnimation(.snappy(duration: 0.28)) {
            for link in links.reversed() { river.open(link.title, from: card) }
            open = false
            all = false
        }
    }

    /// A page linking here, held: itself, as far as fits, to be read
    /// without being opened.
    private struct LinkPreview: View {
        @Environment(WikiStore.self) private var store
        let target: LinkTarget

        var body: some View {
            let text = (store.draft(target.title) ?? store.tiddler(target.title))?.text ?? ""
            VStack(alignment: .leading, spacing: 12) {
                Label(target.shown, systemImage: target.symbol)
                    .font(.headline)
                    .foregroundStyle(Ink.text.color)
                    .lineLimit(2)
                MarkdownView(blocks: MarkdownCache.blocks(text), card: target.title, editable: false)
                    .allowsHitTesting(false)
            }
            .padding(18)
            .frame(width: 340, alignment: .topLeading)
            .frame(maxHeight: 480, alignment: .top)
            .clipped()
            .background(Color.card)
        }
    }
}
#endif
