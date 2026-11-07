#if os(iOS)
import PhoneUI
import PrismCore
import ReflectCore
import SwiftUI
import UIKit
import WeftCore

/// A card's body in Prism's outline editor, as Prism writes on the phone:
/// each line a row, indented, folded and moved as rows, its links pills,
/// and over the keys Prism's bar of glass.
struct OutlineCardEditor: UIViewRepresentable {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    @Binding var text: String
    /// The page it is.
    let title: String
    /// Whether to take the caret, and what to say once it has.
    var wantsCaret = false
    var onCaretTaken: () -> Void = {}
    /// Told when the caret comes in, and when it leaves.
    var onFocusChange: (Bool) -> Void = { _ in }
    /// An untitled page that is a thing to do: its ring as its first row's
    /// mark, that row's own not shown; tapped, `onLead`.
    var lead: Tiddler.TaskState? = nil
    var onLead: () -> Void = {}
    /// Told where its first line's middle is, down from its top: where its
    /// first words are, or will be.
    var onFirstLine: (CGFloat) -> Void = { _ in }

    /// Where a top-level row's words start.
    static var textIndent: CGFloat { PhoneMetrics(face: TextSettings.face, size: TextSettings.size).textIndent(for: .blank) }

    final class Coordinator {
        /// What is around the rows — front matter, the title — written back with them.
        var shell = OutlineMarkdown.parse("")
        /// The text last loaded, or written: a change from elsewhere is one that differs.
        var loaded: String?
        /// The store's count of the page's words replaced, as last taken.
        var replaced = 0
        var write: (String) -> Void = { _ in }
        /// Where its first line's middle was last told to be.
        var firstLine: CGFloat?
        var onFirstLine: (CGFloat) -> Void = { _ in }

        /// Its first line's middle told, once laid out, when it moved: where
        /// the caret goes at its start — an empty row's, where its words will.
        func tellFirstLine(_ editor: OutlineEditor) {
            DispatchQueue.main.async { [self] in
                let caret = editor.caretRect(for: editor.beginningOfDocument)
                guard caret.height > 0, !caret.isNull else { return }
                let middle = caret.midY
                guard middle != firstLine else { return }
                firstLine = middle
                onFirstLine(middle)
            }
        }
        var onFocusChange: (Bool) -> Void = { _ in }
        /// The rows folded, as the river keeps them for the card, and keeping them.
        var folds: () -> [OutlineFolds.Mark] = { [] }
        var keepFolds: ([OutlineFolds.Mark]) -> Void = { _ in }
        private var shownFolds: [OutlineFolds.Mark] = []
        /// The folds the river had, last looked: a change is from elsewhere.
        private(set) var asked: [OutlineFolds.Mark] = []

        /// What was typed, not yet written back: written a moment after typing stops.
        private var pending: DispatchWorkItem?
        private weak var editing: OutlineEditor?
        private var flushing: NSObjectProtocol?

        init() {
            flushing = NotificationCenter.default.addObserver(forName: .weftFlushEdits, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush() }
            }
        }

        /// Typed: written back once typing stops — the whole body read and
        /// written as Markdown, and all that hears of it — not for each key.
        func scheduleSave(_ editor: OutlineEditor) {
            editing = editor
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flush() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        /// What was typed written back now, if anything is waiting.
        func flush() {
            guard let work = pending else { return }
            work.cancel()
            pending = nil
            if let editing { save(editing) }
        }

        func load(_ text: String, into editor: OutlineEditor) {
            // Another body: what was typed in this one goes with it.
            pending?.cancel()
            pending = nil
            loaded = text
            shell = OutlineMarkdown.parse(text)
            // Folded as it was left.
            let marks = folds()
            asked = marks
            editor.load(shell.rows.isEmpty ? [.blank] : marks.isEmpty ? shell.rows : OutlineFolds.apply(marks, to: shell.rows))
            shownFolds = OutlineFolds.marks(editor.rows)
        }

        /// Its rows folded as the river now says, the words left as they are.
        func refold(_ marks: [OutlineFolds.Mark], in editor: OutlineEditor) {
            asked = marks
            guard marks != shownFolds else { return }
            editor.load(OutlineFolds.apply(marks, to: Row.unfold(editor.rows)))
            shownFolds = OutlineFolds.marks(editor.rows)
            editor.invalidateIntrinsicContentSize()
        }

        /// The rows written back as Markdown, around what is not rows — and
        /// which are folded, kept apart from them.
        func save(_ editor: OutlineEditor) {
            let marks = OutlineFolds.marks(editor.rows)
            if marks != shownFolds {
                shownFolds = marks
                asked = marks
                keepFolds(marks)
            }
            var outline = shell
            outline.rows = Row.unfold(editor.rows)
            let text = outline.isBlank ? "" : OutlineMarkdown.serialize(outline)
            guard text != loaded else { return }
            loaded = text
            write(text)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> OutlineEditor {
        // Pictures shown from the graph's `assets/`, and pasted ones kept there.
        PhoneImages.root = store.root
        // Links shown with their pages' and rivers' own icons.
        PhoneLayoutManager.targetIcon = { [store] name in store.linkIcon(name) }
        // Links to untitled pages shown as what they begin with.
        PhoneLayoutManager.untitledName = { [store] name in store.untitledName(name) }
        let editor = OutlineEditor(metrics: PhoneMetrics(face: TextSettings.face, size: TextSettings.size))
        editor.isFindInteractionEnabled = true
        let coordinator = context.coordinator
        coordinator.write = { text = $0 }
        coordinator.onFocusChange = onFocusChange
        coordinator.folds = { [river, title] in river.rowFolds(of: title) }
        coordinator.keepFolds = { [river, title] in river.setRowFolds($0, of: title) }
        editor.onChange = { [weak editor] in
            guard let editor else { return }
            coordinator.scheduleSave(editor)
        }
        editor.onOpenLink = { [river, title] in followOutline($0, in: river, from: title) }
        // Untitled and new: its first row offered as its title, quietly, once
        // written — or taken, typed as a heading and Return pressed.
        editor.isUntitled = { [store, title] in Untitled.isName(store.draftHead(title)?.title ?? title) }
        editor.offersTitleChip = true
        editor.offersTitle = { [store, title] in store.offersTitle(title) }
        editor.titlesByHeading = true
        editor.onTitle = { [store, title] name in store.change(title) { $0.title = name } }
        editor.onHeightChange = { [weak editor] in
            guard let editor else { return }
            editor.invalidateIntrinsicContentSize()
            coordinator.tellFirstLine(editor)
        }
        editor.onFocusChange = { focused in
            // Leaving: what was typed written back first.
            if !focused { coordinator.flush() }
            coordinator.onFocusChange(focused)
        }
        // `[[` completes from the graph's notes, as Prism's does; dictation
        // listens for their names.
        store.prepareLinkNotes { notes in
            OutlineEditor.suggest = { LinkSuggestions.candidates($0, index: notes) }
            OutlineEditor.dictationTerms = { Dictation.terms(notes) }
        }
        // A day's card: today's shows the time now among its blocks, and its
        // tasks aren't offered to it.
        editor.day = Day(title)
        // A task's menu: Do Today, Later… — moved into that day's page.
        OutlineEditor.moveTo = { [store] editor, index, path in
            guard let day = GraphPaths.day(fromDailyPath: path) else { return }
            let name = day == .today ? "Today" : day == Day.today.adding(1) ? "Tomorrow" : store.shownTitle(day.description)
            editor.moveRows(at: index, named: name) { rows, undo in store.add(rows, toDay: day, undo: undo) }
        }
        coordinator.load(text, into: editor)
        return editor
    }

    static func dismantleUIView(_ editor: OutlineEditor, coordinator: Coordinator) { coordinator.flush() }

    func updateUIView(_ editor: OutlineEditor, context: Context) {
        let coordinator = context.coordinator
        CardTextViews.shown(editor, for: title)
        coordinator.write = { text = $0 }
        coordinator.onFocusChange = onFocusChange
        coordinator.onFirstLine = onFirstLine
        coordinator.tellFirstLine(editor)
        // The page's ring standing for its first row's mark.
        editor.leadMark = lead.map { $0 == .done }
        editor.onLeadMark = lead == nil ? nil : onLead
        // Changed elsewhere — another river, a sync — and not being written in
        // here; or replaced, its first line made its title, even while it is.
        let replaced = store.replacements[title] ?? 0
        if text != coordinator.loaded, !editor.isFirstResponder || replaced != coordinator.replaced {
            coordinator.load(text, into: editor)
        }
        coordinator.replaced = replaced
        // Folded elsewhere — a sync brought the river's file.
        let folds = river.rowFolds(of: title)
        if folds != coordinator.asked, !editor.isFirstResponder {
            coordinator.refold(folds, in: editor)
        }
        if wantsCaret {
            DispatchQueue.main.async { [onCaretTaken] in
                if !editor.isFirstResponder { editor.becomeFirstResponder() }
                onCaretTaken()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView editor: OutlineEditor, context: Context) -> CGSize? {
        let width = proposal.width ?? 350
        // As tall as its rows: not the empty line after the last one's
        // break, which the caret never goes to — room under every card.
        return CGSize(width: width, height: max(editor.rowsHeight(width: width), 30))
    }
}

/// Following a link the outline editor reports: `[[Title]]` opens its card
/// after this one, `#tag` its tag's, an address the browser.
@MainActor
private func followOutline(_ link: String, in river: River, from card: String) {
    if link.hasPrefix("[["), link.hasSuffix("]]") {
        let title = String(link.dropFirst(2).dropLast(2)).components(separatedBy: "|")[0].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        follow(InlineMarkdown.url(for: title), in: river, from: card)
    } else if link.hasPrefix("#"), link.count > 1 {
        follow(InlineMarkdown.url(for: String(link.dropFirst())), in: river, from: card)
    } else if let url = URL(string: link), url.scheme != nil {
        follow(url, in: river, from: card)
    }
}
#endif
