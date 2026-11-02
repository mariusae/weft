#if os(macOS)
import AppKit
import ReflectCore
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
    static var textIndent: CGFloat { PageOutlineEditor.textIndent(fontSize: TextSettings.size + 1) }

    final class Coordinator {
        var revision = -1
        var onFocusChange: (Bool) -> Void = { _ in }
        /// The text last looked at, and whether it asks the graph anything.
        var checked: String?
        var asks = false
        /// The folds the river had for it, last looked: a change is from elsewhere.
        var folds: [OutlineFolds.Mark] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PageOutlineEditor {
        let editor = PageOutlineEditor(text: "", fontSize: TextSettings.size + 1, root: store.root)
        // Prism's keys, ⌘⇧K deleting rows and the rest: Weft has not its menus.
        editor.takesEditorKeys = true
        // Folded as it was left in this river.
        let coordinator = context.coordinator
        coordinator.folds = river.rowFolds(of: title)
        editor.load(text, folds: coordinator.folds)
        editor.onChange = { text = $0 }
        editor.onFoldsChange = { [river, title] in
            coordinator.folds = $0
            river.setRowFolds($0, of: title)
        }
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
        let folds = river.rowFolds(of: title)
        editor.load(text, folds: folds)
        // Folded elsewhere — a sync brought the river's file — and not being written in here.
        if folds != context.coordinator.folds {
            context.coordinator.folds = folds
            if !editor.isFocused { editor.refold(folds) }
        }
        if wantsCaret {
            DispatchQueue.main.async { [onCaretTaken] in
                if !editor.isFocused { editor.focus() }
                onCaretTaken()
            }
        }
        // Looked at again only when it changed: this runs for each key.
        let coordinator = context.coordinator
        if text != coordinator.checked {
            coordinator.checked = text
            coordinator.asks = text.contains("```query") || text.contains("![[")
        }
        // The graph again when it changed, for a card that asks it — what a
        // query finds, or an embed shows, may have. Other cards don't hear
        // of every save.
        if coordinator.asks {
            // An embed shows another page's words: every save, not only
            // what changes queries.
            let revision = store.graphVersion &+ store.textVersion &* 7919 &+ store.savedVersion &* 104_729
            if coordinator.revision != revision {
                coordinator.revision = revision
                editor.setGraph(store.pages, title: title, refreshing: true)
            }
        } else if coordinator.revision != -2 {
            coordinator.revision = -2
            editor.setGraph(nil, title: title, refreshing: false)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView editor: PageOutlineEditor, context: Context) -> CGSize? {
        // Its ideal width the one it has: measured at another, it is laid out again twice.
        let width = proposal.width ?? (editor.bounds.width > 0 ? editor.bounds.width : 600)
        return CGSize(width: width, height: editor.height(forWidth: width))
    }
}

enum OutlineEditing {
    /// Whether a body can be edited as an outline and written back as it was.
    static func canEdit(_ text: String) -> Bool { PageOutlineEditor.canEdit(text) }
}
#endif
