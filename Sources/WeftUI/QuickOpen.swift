import ReflectCore
import SwiftUI
import WeftCore
#if os(iOS)
import PhoneUI
#endif

/// ⌘O: a tiddler, a Reflect note or a day, found by what is typed and
/// opened in the river — or, when nothing is called that, a new tiddler.
/// Set as Prism's Go to is: on the Mac a card of paper over the river, the
/// field in large type, each row a name and when it was written; on the
/// phone a sheet, its field at the top, each row its kind's symbol, its
/// name, and under it when.
struct QuickOpen: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool
    /// On a start page, not over the river: what it finds shown only once
    /// something is typed, the page under it showing till then.
    let inline: Bool

    init(inline: Bool = false) { self.inline = inline }

    #if os(macOS)
    /// The window it is in: what has the keys there — a card being written
    /// in, whose text is in a view of the river's own — is made to let go.
    @State private var window: NSWindow?
    #endif

    var body: some View {
        content
            .onChange(of: query) { selected = 0 }
            #if os(macOS)
            .background(WindowReader { window = $0 })
            #endif
            // Each time it is asked for — shown already or not, in this tab or
            // another's — its field takes the keys.
            .task(id: "\(river.id) \(river.quickOpenAsked)") {
                // Once it is on screen: on the phone, asked at once, the keys don't come.
                #if os(iOS)
                try? await Task.sleep(for: .milliseconds(100))
                focused = true
                #else
                for _ in 0..<5 where window == nil { await Task.yield() }
                // Asked again, should what had the keys keep them.
                for _ in 0..<3 {
                    takeKeys()
                    try? await Task.sleep(for: .milliseconds(60))
                    if hasKeys { break }
                }
                #endif
            }
    }

    #if os(macOS)
    /// Whether its field has the keys: the window's field editor is its.
    private var hasKeys: Bool {
        (window?.firstResponder as? NSTextView)?.isFieldEditor == true && focused
    }

    /// The keys to its field: what had them — a card being written in, in a
    /// view of the river's own, which SwiftUI's focus would not move them
    /// from — let go first.
    private func takeKeys() {
        if let window, (window.firstResponder as? NSTextView)?.isFieldEditor != true { window.makeFirstResponder(nil) }
        focused = false
        focused = true
    }
    #endif

    /// What is found, and a new tiddler of the name typed when none has it.
    private var found: [LinkTarget] {
        var results = store.quickOpen(query)
        let typed = query.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty, !results.contains(where: { $0.title.caseInsensitiveCompare(typed) == .orderedSame }) {
            results.append(LinkTarget(title: typed, shown: typed, kind: .new))
        }
        return results
    }

    private func name(_ target: LinkTarget) -> String {
        target.kind == .new ? "New page “\(target.title)”" : target.shown
    }

    /// What is said of a row beside its name: a day's name for it, and
    /// whether it has a page yet; when a page was written — and that it is
    /// open in the river already.
    private func detail(_ target: LinkTarget) -> String {
        if target.kind == .new { return "New page" }
        if target.kind == .river, let name = RiverLink.name(target.title) {
            let count = store.savedCards(name)?.count ?? 0
            let showing = store.river(named: name) != nil
            return (showing ? "Open · " : "") + "Saved river · \(count == 1 ? "1 card" : "\(count) cards")"
        }
        let entry = store.pages?.entries[target.title]
        var words: [String] = []
        if river.cards.contains(target.title) { words.append("Open") }
        if target.kind == .day, let day = Day(target.title) {
            let names = [0: "Today", -1: "Yesterday", 1: "Tomorrow"]
            if let named = (-1...1).first(where: { Day.today.adding($0) == day }).flatMap({ names[$0] }) { words.append(named) }
            if entry == nil { words.append("no page yet") }
        } else if let modified = entry?.modified {
            words.append(Self.relative.localizedString(for: modified, relativeTo: Date()))
        }
        return words.joined(separator: " · ")
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func open(_ target: LinkTarget, inNewTab: Bool = false) {
        river.quickOpenShown = false
        river.startShown = false
        if inNewTab, target.kind != .new, target.kind != .river {
            river.openNew(River.State(graph: store.root?.path ?? "", cards: [target.title]))
            return
        }
        withAnimation(.snappy(duration: 0.28)) {
            if target.kind == .new {
                river.edit(target.title)
            } else {
                river.open(target.title)
            }
        }
    }

    #if os(macOS)
    /// How many rows show at once: the rest scrolled to.
    private static let shown = 9
    private static let rowHeight: CGFloat = 40

    private var content: some View {
        let results = found
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Go to a page or a day", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21))
                    .foregroundStyle(Ink.text.color)
                    .focused($focused)
                    .onSubmit { if results.indices.contains(selected) { open(results[selected]) } }
                    // ⌘↩: a tab of its own. The menu's ⌘↩ stands aside while this shows.
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command), results.indices.contains(selected) else { return .ignored }
                        open(results[selected], inNewTab: true)
                        return .handled
                    }
                Text("↩ Open   ⌘↩ New Tab")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Ink.faint.color)
                    .fixedSize()
            }
            .padding(.horizontal, 22)
            .frame(height: 60)
            if !results.isEmpty, !inline || !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Rectangle().fill(Ink.rule.color).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element) { index, target in
                                row(target, chosen: index == selected)
                                    .id(index)
                                    // Only the pointer moved chooses: not a row come under a still one.
                                    .onContinuousHover { if case .active = $0, selected != index { selected = index } }
                                    .onTapGesture { open(target, inNewTab: NSEvent.modifierFlags.contains(.command)) }
                            }
                        }
                        .padding(8)
                    }
                    .scrollIndicators(.automatic)
                    .frame(height: CGFloat(min(results.count, Self.shown)) * Self.rowHeight + 16)
                    .onChange(of: selected) { proxy.scrollTo(selected) }
                }
            }
        }
        .frame(maxWidth: 600)
        .background(Ink.paper.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.rule.color, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 15, y: 8)
        .padding(.horizontal, 24)
        .onKeyPress(.upArrow) {
            selected = max(0, selected - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selected = min(results.count - 1, selected + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            // On the start page, what was typed let go — nothing typed, the
            // page put away, asked for over the river; over the river, put away.
            if inline, !query.isEmpty { query = "" } else if inline { river.startShown = false } else { river.quickOpenShown = false }
            return .handled
        }
    }

    private func row(_ target: LinkTarget, chosen: Bool) -> some View {
        HStack(spacing: 12) {
            Text(name(target))
                .font(.system(size: 15.5))
                .foregroundStyle(chosen ? Ink.text.color : Ink.secondary.color)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Text(detail(target))
                .font(.system(size: 12.5))
                .foregroundStyle(Ink.faint.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.rowHeight)
        .background(chosen ? Ink.hover.color : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
    #else
    private var face: Typeface { TextSettings.face }

    private var content: some View {
        let results = found
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Ink.secondary.color)
                    TextField("Go to a page or a day", text: $query)
                        .font(Font(face.body(17)))
                        .foregroundStyle(Ink.text.color)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit { if let first = results.first { open(first) } }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.faint.color)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Ink.rule.color, in: Capsule())
                Button("Cancel") { river.quickOpenShown = false }
                    .font(Font(face.body(17)))
                    .foregroundStyle(Ink.accent.color)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 8)
            List {
                ForEach(Array(results.enumerated()), id: \.element) { index, target in
                    Button { open(target) } label: { row(target, first: index == 0) }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Ink.rule.color)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Ink.paper.color)
    }

    private func row(_ target: LinkTarget, first: Bool) -> some View {
        let detail = detail(target)
        return HStack(spacing: 14) {
            Image(systemName: target.symbol)
                .font(.system(size: 17))
                .foregroundStyle(Ink.secondary.color)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(name(target))
                    .font(Font(face.body(17, weight: first ? .semibold : .regular)))
                    .foregroundStyle(Ink.text.color)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(Font(face.body(14)))
                        .foregroundStyle(Ink.secondary.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    #endif
}
