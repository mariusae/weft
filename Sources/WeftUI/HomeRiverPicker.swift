import ReflectCore
import SwiftUI
import WeftCore

/// A card's home river, found by typing its name — as Prism moves a row
/// to a note: the saved rivers whose names have what is typed, those
/// beginning with it first; Return sets the one chosen, a name no river
/// has a new river of the card, and nothing typed with a home already,
/// none. On the Mac a card of paper over the river, as Quick Open is; on
/// the phone a sheet.
struct HomeRiverPicker: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    let title: String
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool
    #if os(macOS)
    @State private var window: NSWindow?
    #endif

    enum Choice: Hashable {
        case river(String)
        case new(String)
        case none
    }

    /// What can be chosen for what is typed.
    var choices: [Choice] { Self.choices(for: query, saved: store.savedRivers(), home: store.homeRiver(of: title)) }

    static func choices(for query: String, saved: [String], home: String?) -> [Choice] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty {
            // Its home first, to keep with Return — or let go of, after it.
            let rest = saved.filter { $0.caseInsensitiveCompare(home ?? "") != .orderedSame }
            return (home.map { [.river($0)] } ?? []) + rest.map(Choice.river) + (home == nil ? [] : [.none])
        }
        let matching = saved.filter { $0.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        let starting = matching.filter { $0.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }
        var found = (starting + matching.filter { !starting.contains($0) }).map(Choice.river)
        if !saved.contains(where: { $0.caseInsensitiveCompare(typed) == .orderedSame }) { found.append(.new(typed)) }
        return found
    }

    private func choose(_ choice: Choice) {
        switch choice {
        case .river(let name): store.setHomeRiver(name, of: title)
        case .new(let name):
            // A river of its own, the card in it, and its home.
            if let made = store.addSavedRiver(name, SavedRiver(cards: [title])) { store.setHomeRiver(made, of: title) }
        case .none: store.setHomeRiver(nil, of: title)
        }
        river.homing = nil
    }

    private func name(_ choice: Choice) -> String {
        switch choice {
        case .river(let name): name
        case .new(let name): "New River “\(name)”"
        case .none: "No Home River"
        }
    }

    private func symbol(_ choice: Choice) -> String {
        switch choice {
        case .river(let name): store.savedRiverIcon(name) ?? RiverLink.symbol
        case .new: "plus.square.on.square"
        case .none: "minus.circle"
        }
    }

    private func isHome(_ choice: Choice) -> Bool {
        if case .river(let name) = choice { return name.caseInsensitiveCompare(store.homeRiver(of: title) ?? "") == .orderedSame }
        return false
    }

    private var prompt: String { "Home river for “\(store.shownTitle(title))”" }

    var body: some View {
        content
            .onChange(of: query) { selected = 0 }
            #if os(macOS)
            .background(WindowReader { window = $0 })
            .task {
                // The keys from the card being written in, which SwiftUI's
                // focus would not move them from.
                for _ in 0..<5 where window == nil { await Task.yield() }
                for _ in 0..<3 {
                    if let window, (window.firstResponder as? NSTextView)?.isFieldEditor != true { window.makeFirstResponder(nil) }
                    focused = true
                    try? await Task.sleep(for: .milliseconds(60))
                    if (window?.firstResponder as? NSTextView)?.isFieldEditor == true { break }
                }
            }
            #else
            .task {
                try? await Task.sleep(for: .milliseconds(100))
                focused = true
            }
            #endif
    }

    #if os(macOS)
    private static let shown = 8
    private static let rowHeight: CGFloat = 36

    private var content: some View {
        let results = choices
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: RiverLink.symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(Ink.secondary.color)
                TextField(prompt, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19))
                    .foregroundStyle(Ink.text.color)
                    .focused($focused)
                    .onSubmit { if results.indices.contains(selected) { choose(results[selected]) } }
                Text("↩ Set")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Ink.faint.color)
                    .fixedSize()
            }
            .padding(.horizontal, 20)
            .frame(height: 54)
            if !results.isEmpty {
                Rectangle().fill(Ink.rule.color).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element) { index, choice in
                                row(choice, chosen: index == selected)
                                    .id(index)
                                    .onContinuousHover { if case .active = $0, selected != index { selected = index } }
                                    .onTapGesture { choose(choice) }
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: CGFloat(min(results.count, Self.shown)) * Self.rowHeight + 16)
                    .onChange(of: selected) { proxy.scrollTo(selected) }
                }
            }
        }
        .frame(maxWidth: 480)
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
            river.homing = nil
            return .handled
        }
    }

    private func row(_ choice: Choice, chosen: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(choice))
                .font(.system(size: 13))
                .foregroundStyle(Ink.secondary.color)
                .frame(width: 20)
            Text(name(choice))
                .font(.system(size: 15))
                .foregroundStyle(chosen ? Ink.text.color : Ink.secondary.color)
                .lineLimit(1)
            Spacer(minLength: 12)
            if isHome(choice) {
                Text("Home now")
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.faint.color)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.rowHeight)
        .background(chosen ? Ink.hover.color : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
    #else
    private var content: some View {
        let results = choices
        return NavigationStack {
            List {
                ForEach(results, id: \.self) { choice in
                    Button { choose(choice) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(choice)).foregroundStyle(Ink.secondary.color).frame(width: 24)
                            Text(name(choice)).foregroundStyle(Ink.text.color)
                            Spacer(minLength: 0)
                            if isHome(choice) { Image(systemName: "checkmark").foregroundStyle(Ink.accent.color) }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "River name")
            .searchFocused($focused)
            .onSubmit(of: .search) { if let first = results.first { choose(first) } }
            .navigationTitle("Home River")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { river.homing = nil } }
            }
        }
    }
    #endif
}
