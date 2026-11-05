#if os(macOS)
import ReflectCore
import SwiftUI
import WeftCore

/// An empty river's start page, as a new tab's in Safari — or, its tab
/// clicked, over the river: at its top the field to go to a page by, taking
/// the keys; under it the saved rivers to put in the tab, in place of what
/// it shows, a new query river there, and the pages pinned and written
/// lately — clicked, opened here; ⌘-clicked, a tab of their own.
struct MacStartPage: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river

    /// The field's height: what is under it starts below, its results over them.
    private static let field: CGFloat = 60

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Color.clear.frame(height: Self.field)
                rivers
                pages("Pinned", Array(store.pinned().prefix(8)))
                pages("Recent", Array(store.recent().prefix(10)))
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        // The field, and what it finds, over the rest.
        .overlay(alignment: .top) {
            QuickOpen(inline: true)
                .frame(maxWidth: 640 + 48)
                .padding(.top, 28)
        }
    }

    // MARK: Rivers

    private var rivers: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Rivers")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 120), spacing: 10, alignment: .top)], alignment: .leading, spacing: 14) {
                ForEach(store.savedRivers(), id: \.self) { name in riverTile(name) }
                newTile("Query River", "line.3.horizontal.decrease") {
                    river.quickOpenShown = false
                    river.queryEditor = .newHere
                }
            }
        }
    }

    private func riverTile(_ name: String) -> some View {
        let saved = store.savedRiver(name)
        let color = RiverColor.color(saved?.color ?? (saved?.query != nil ? "orange" : "blue"))
        let open = store.river(named: name) != nil
        return StartTile(name: name, help: open ? "Open in another tab: shown" : "In this tab") {
            Image(systemName: store.savedRiverIcon(name) ?? (saved?.query != nil ? "line.3.horizontal.decrease.circle" : "square.stack"))
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 58, height: 58)
                .background(color.opacity(0.14), in: .rect(cornerRadius: 14))
                .overlay(alignment: .topTrailing) {
                    if open { Circle().fill(Ink.accent.color).frame(width: 8, height: 8).offset(x: 2, y: -2) }
                }
        } action: {
            river.quickOpenShown = false
            withAnimation(.snappy(duration: 0.28)) { river.replace(withSaved: name) }
        }
    }

    private func newTile(_ name: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        StartTile(name: name, help: "A new query river", faint: true, picture: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Ink.secondary.color)
                .frame(width: 58, height: 58)
                .background(Ink.text.color.opacity(0.06), in: .rect(cornerRadius: 14))
        }, action: action)
    }

    // MARK: Pages

    @ViewBuilder private func pages(_ name: String, _ titles: [String]) -> some View {
        if !titles.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                heading(name)
                VStack(spacing: 0) {
                    ForEach(titles, id: \.self) { title in PageRow(title: title) { open(title, inNewTab: $0) } }
                }
            }
        }
    }

    private func heading(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Ink.secondary.color)
            .padding(.leading, 4)
    }

    private func open(_ title: String, inNewTab: Bool) {
        river.quickOpenShown = false
        river.startShown = false
        if inNewTab {
            river.openNew(River.State(graph: store.root?.path ?? "", cards: [title]))
        } else {
            withAnimation(.snappy(duration: 0.28)) { river.open(title) }
        }
    }
}

/// A tile on the start page: its picture, its name under it, lit under the pointer.
private struct StartTile<Picture: View>: View {
    let name: String
    let help: String
    var faint = false
    @ViewBuilder let picture: () -> Picture
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                picture()
                Text(name)
                    .font(.system(size: 12))
                    .foregroundStyle(faint ? Ink.secondary.color : Ink.text.color)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(hovered ? Ink.hover.color : .clear, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(name)
    }
}

/// A page on the start page: its kind's symbol, its name, when it was written.
private struct PageRow: View {
    @Environment(WikiStore.self) private var store
    let title: String
    let open: (_ inNewTab: Bool) -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: store.symbol(of: title))
                .font(.system(size: 13))
                .foregroundStyle(Ink.secondary.color)
                .frame(width: 20)
            Text(store.shownTitle(title))
                .font(.system(size: 14.5))
                .foregroundStyle(Ink.text.color)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let modified = store.pages?.entries[title]?.modified {
                Text(Self.relative.localizedString(for: modified, relativeTo: Date()))
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.faint.color)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(hovered ? Ink.hover.color : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onHover { hovered = $0 }
        .onTapGesture { open(NSEvent.modifierFlags.contains(.command)) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
#endif
