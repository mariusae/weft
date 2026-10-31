import SwiftUI
import WeftCore

/// ⌘O: a tiddler, a Reflect note or a day, found by what is typed and
/// opened in the river — or, when nothing is called that, a new tiddler.
struct QuickOpen: View {
    @Environment(WikiStore.self) private var store
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    var body: some View {
        let results = found
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Ink.secondary.color)
                TextField("Open a page or a day", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19))
                    .focused($focused)
                    .onSubmit { open(results) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            if !results.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(Array(results.enumerated()), id: \.element) { index, target in
                                row(target, chosen: index == selected)
                                    .id(index)
                                    .onTapGesture {
                                        selected = index
                                        open(results)
                                    }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 380)
                    .onChange(of: selected) { proxy.scrollTo(selected) }
                }
            }
        }
        // As wide as the Mac's window allows it; on the phone, its width.
        .frame(maxWidth: 580)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Ink.rule.color))
        .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
        .padding(.horizontal, 12)
        .onKeyPress(.upArrow) {
            selected = max(0, selected - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selected = min(results.count - 1, selected + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            store.quickOpenShown = false
            return .handled
        }
        .onChange(of: query) { selected = 0 }
        .onAppear { focused = true }
    }

    /// What is found, and a new tiddler of the name typed when none has it.
    private var found: [LinkTarget] {
        var results = store.quickOpen(query)
        let typed = query.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty, !results.contains(where: { $0.title.caseInsensitiveCompare(typed) == .orderedSame }) {
            results.append(LinkTarget(title: typed, shown: typed, kind: .new))
        }
        return results
    }

    private func row(_ target: LinkTarget, chosen: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: target.kind.symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 20)
                .foregroundStyle(chosen ? .white : Ink.accent.color)
            Text(target.kind == .new ? "New page “\(target.title)”" : target.shown)
                .lineLimit(1)
                .foregroundStyle(chosen ? .white : Ink.text.color)
            Spacer(minLength: 8)
            if store.river.contains(target.title) {
                Text("Open")
                    .font(.caption)
                    .foregroundStyle(chosen ? .white.opacity(0.8) : Ink.secondary.color)
            }
            Text(target.kind == .new ? "" : target.kind.label)
                .font(.caption)
                .foregroundStyle(chosen ? .white.opacity(0.8) : Ink.secondary.color)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(chosen ? Ink.accent.color : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private func open(_ results: [LinkTarget]) {
        guard results.indices.contains(selected) else { return }
        let target = results[selected]
        store.quickOpenShown = false
        withAnimation(.snappy(duration: 0.28)) {
            if target.kind == .new {
                store.edit(target.title)
            } else {
                store.open(target.title)
            }
        }
    }
}
