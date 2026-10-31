#if os(macOS)
import AppKit
import ReflectUI
import SwiftUI
import WeftCore

/// A card's body in Prism's outline editor: each line a row, indented,
/// folded and moved as rows — its queries, embeds and callouts drawn as
/// Prism draws them.
struct OutlineCardEditor: NSViewRepresentable {
    @Environment(WikiStore.self) private var store
    @Binding var text: String
    /// The page it is, which `{this}` stands for.
    let title: String

    final class Coordinator {
        var revision = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PageOutlineEditor {
        let editor = PageOutlineEditor(text: text, root: store.root)
        editor.onChange = { text = $0 }
        editor.onOpenTitle = { [store] title in
            withAnimation(.snappy(duration: 0.28)) { store.open(title) }
        }
        editor.onOpenURL = { NSWorkspace.shared.open($0) }
        editor.onHeightChange = { [weak editor] in editor?.invalidateIntrinsicContentSize() }
        store.prepareLinkNotes { PageOutlineEditor.completeLinks(from: $0) }
        DispatchQueue.main.async { editor.focus() }
        return editor
    }

    func updateNSView(_ editor: PageOutlineEditor, context: Context) {
        editor.load(text)
        // The graph again when it changed: what a query finds may have.
        let revision = store.revision
        let asks = text.contains("```query") || text.contains("![[")
        if context.coordinator.revision != revision {
            context.coordinator.revision = revision
            editor.setGraph(asks ? store.pages : nil, title: title, refreshing: asks)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView editor: PageOutlineEditor, context: Context) -> CGSize? {
        let width = proposal.width ?? 600
        return CGSize(width: width, height: editor.height(forWidth: width))
    }
}

enum OutlineEditing {
    /// Whether a body can be edited as an outline and written back as it was.
    static func canEdit(_ text: String) -> Bool { PageOutlineEditor.canEdit(text) }
}
#endif
