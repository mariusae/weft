#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import WeftCore

/// A window's rivers as tabs in its title bar, as Safari has them: each a
/// capsule with its river's name — the one shown wider, standing as the
/// window's title, a click on it Quick Open — closed from its ×, dragged to
/// another place among the others, and from its menu saved, closed, or
/// moved to a window of its own.
struct RiverTabs: View {
    @Environment(WikiStore.self) private var store
    let rivers: RiverSet
    /// A tab moved to a window of its own: the window to open with it.
    var moveToWindow: (River) -> Void = { _ in }
    @State private var dragged: River?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(rivers.rivers) { river in
                RiverTab(river: river, isCurrent: river === rivers.current, closable: rivers.rivers.count > 1) {
                    if river === rivers.current { river.quickOpenShown = true } else { withAnimation(.snappy(duration: 0.2)) { rivers.select(river) } }
                } close: {
                    withAnimation(.snappy(duration: 0.2)) { rivers.close(river) }
                }
                .contextMenu { menu(river) }
                .onDrag {
                    dragged = river
                    return NSItemProvider(object: river.id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: TabDrop(target: river, rivers: rivers, dragged: $dragged))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.2), value: rivers.rivers.map(\.id))
    }

    @ViewBuilder private func menu(_ river: River) -> some View {
        Button(river.name == nil ? "Save River…" : "Rename River…") {
            rivers.select(river)
            river.naming = river.name.map { .rename($0) } ?? .save
        }
        Divider()
        Button("Move Tab to New Window") { moveToWindow(river) }
            .disabled(rivers.rivers.count < 2)
        Button("Close Other Tabs") { withAnimation(.snappy(duration: 0.2)) { rivers.closeOthers(river) } }
            .disabled(rivers.rivers.count < 2)
        Button("Close Tab") { withAnimation(.snappy(duration: 0.2)) { rivers.close(river) } }
            .disabled(rivers.rivers.count < 2)
    }
}

/// One river's tab: its name — slanted for one not saved, named by the card
/// at its top — and, under the pointer, its ×.
private struct RiverTab: View {
    let river: River
    let isCurrent: Bool
    let closable: Bool
    let choose: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            Button(action: choose) {
                HStack(spacing: 6) {
                    if river.name != nil {
                        Image(systemName: "square.stack")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Ink.secondary.color)
                    }
                    Text(river.title)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .italic(river.name == nil && !isCurrent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, closable ? 20 : 12)
                .frame(maxWidth: .infinity, minHeight: 26)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isCurrent ? Ink.text.color : Ink.secondary.color)
            .help(isCurrent ? "\(river.title) — click for Quick Open" : river.title)
            if closable, hovering || isCurrent {
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 18, height: 18)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Ink.secondary.color)
                    .opacity(hovering ? 1 : 0)
                    .help("Close Tab (⌘W)")
                    Spacer()
                }
                .padding(.leading, 3)
            }
        }
        // The one shown, wider: the window's title.
        .frame(minWidth: isCurrent ? 84 : 40, maxWidth: isCurrent ? 300 : 220)
        .background(Capsule().fill(isCurrent ? Ink.text.color.opacity(0.09) : (hovering ? Ink.text.color.opacity(0.05) : .clear)))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// A tab dropped on another: put where that one is.
private struct TabDrop: DropDelegate {
    let target: River
    let rivers: RiverSet
    @Binding var dragged: River?

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged !== target, let index = rivers.rivers.firstIndex(where: { $0 === target }) else { return }
        withAnimation(.snappy(duration: 0.18)) { rivers.move(dragged, to: index) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}
#endif
