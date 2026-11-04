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
        // A `[[link]]`'s card: the page it is to, as the graph has it; a
        // link to an untitled page, what it begins with — told before the
        // editor first styles its text.
        PageOutlineEditor.findNotes { [store] linked in store.noteFile(linked) }
        PageOutlineEditor.nameUntitled { [store] name in store.untitledName(name) }
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
        // A link followed: its card opened after this one, as the text editor's are.
        editor.onOpenTitle = { [river, title] linked in
            withAnimation(.snappy(duration: 0.28)) { river.open(linked, from: title) }
        }
        // A file in the graph — a picture double-clicked, a PDF's pill — by
        // its place in it; any other address, as it says.
        editor.onOpenURL = { [store] url in
            guard url.scheme?.isEmpty ?? true else {
                NSWorkspace.shared.open(url)
                return
            }
            let path = url.path.removingPercentEncoding ?? url.path
            guard path.hasPrefix("assets/"), !path.contains(".."), let root = store.root else { return NSSound.beep() }
            NSWorkspace.shared.open(root.appendingPathComponent(path))
        }
        // A day's card: today's shows the time now among its blocks; its
        // tasks offered Do Today and Later — moved into that day's page.
        editor.day = Day(title)
        editor.dayName = { [store] day in store.shownTitle(day.description) }
        editor.onMoveToDay = { [store] rows, day, undo in store.add(rows, toDay: day, undo: undo ?? UndoManager()) }
        editor.onHeightChange = { [weak editor] in editor?.invalidateIntrinsicContentSize() }
        // Untitled: its first row offered as its title, while the caret is on it.
        editor.isUntitled = { [store, title] in Untitled.isName(store.draftHead(title)?.title ?? title) }
        editor.onTitle = { [store, title] name in store.change(title) { $0.title = name } }
        editor.onAskTitle = { [river, title] in river.edit(title, inTitle: true) }
        editor.onFocusChange = { [coordinator = context.coordinator] in coordinator.onFocusChange($0) }
        store.prepareLinkNotes { PageOutlineEditor.completeLinks(from: $0) }
        return editor
    }

    func updateNSView(_ editor: PageOutlineEditor, context: Context) {
        context.coordinator.onFocusChange = onFocusChange
        // A private page's links are not looked up on the web.
        editor.isPrivate = store.isPrivate(title)
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
        if !text.isSameText(as: coordinator.checked ?? "") || coordinator.checked == nil {
            coordinator.checked = text
            coordinator.asks = text.containsText("```query") || text.containsText("![[")
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

/// What the outline editor keeps of how pages are shown — a picture's
/// size, a PDF's page, a carousel's place — kept in Weft's own folder,
/// not another app's: a snapshot's apart. Set as the app starts, before
/// any card; written as it quits.
@MainActor
public enum OutlineState {
    public static func prepare(snapshot: Bool) {
        if snapshot {
            PageOutlineEditor.keepState(in: "Weft/Snapshot State")
        } else {
            // Kept, until now, as Reflect Mac keeps its: taken from there, once.
            PageOutlineEditor.keepState(in: "Weft", taking: "Reflect Mac")
        }
    }

    public static func save() { PageOutlineEditor.saveState() }
}

enum OutlineEditing {
    /// Whether a body can be edited as an outline and written back as it was.
    static func canEdit(_ text: String) -> Bool { PageOutlineEditor.canEdit(text) }
}
#endif
