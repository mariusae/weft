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
    @Environment(River.self) private var river
    @Binding var text: String
    /// The page it is, which `{this}` stands for.
    let title: String
    /// Whether to take the caret, and what to say once it has.
    var wantsCaret = false
    var onCaretTaken: () -> Void = {}
    /// Told when the caret comes in, and when it leaves.
    var onFocusChange: (Bool) -> Void = { _ in }

    /// Where a top-level row's words start.
    static var textIndent: CGFloat { PageOutlineEditor.textIndent() }

    final class Coordinator {
        var revision = -1
        var onFocusChange: (Bool) -> Void = { _ in }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PageOutlineEditor {
        let editor = PageOutlineEditor(text: text, root: store.root)
        editor.onChange = { text = $0 }
        editor.onOpenTitle = { [river] title in
            withAnimation(.snappy(duration: 0.28)) { river.open(title) }
        }
        editor.onOpenURL = { NSWorkspace.shared.open($0) }
        editor.onHeightChange = { [weak editor] in editor?.invalidateIntrinsicContentSize() }
        editor.onFocusChange = { [coordinator = context.coordinator] in coordinator.onFocusChange($0) }
        store.prepareLinkNotes { PageOutlineEditor.completeLinks(from: $0) }
        return editor
    }

    func updateNSView(_ editor: PageOutlineEditor, context: Context) {
        context.coordinator.onFocusChange = onFocusChange
        editor.load(text)
        if wantsCaret {
            DispatchQueue.main.async { [onCaretTaken] in
                if !editor.isFocused { editor.focus() }
                onCaretTaken()
            }
        }
        // The graph again when it changed: what a query finds may have.
        let revision = store.graphVersion
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
