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

    /// Where a top-level row's words start.
    static var textIndent: CGFloat { PhoneMetrics(face: TextSettings.face, size: TextSettings.size).textIndent(for: .blank) }

    final class Coordinator {
        /// What is around the rows — front matter, the title — written back with them.
        var shell = OutlineMarkdown.parse("")
        /// The text last loaded, or written: a change from elsewhere is one that differs.
        var loaded: String?
        var write: (String) -> Void = { _ in }
        var onFocusChange: (Bool) -> Void = { _ in }
        /// The rows folded, as kept for the page, and keeping them.
        var folds: () -> [OutlineFolds.Mark] = { [] }
        var keepFolds: ([OutlineFolds.Mark]) -> Void = { _ in }
        private var shownFolds: [OutlineFolds.Mark] = []

        func load(_ text: String, into editor: OutlineEditor) {
            loaded = text
            shell = OutlineMarkdown.parse(text)
            // Folded as it was left.
            let marks = folds()
            editor.load(shell.rows.isEmpty ? [.blank] : marks.isEmpty ? shell.rows : OutlineFolds.apply(marks, to: shell.rows))
            shownFolds = OutlineFolds.marks(editor.rows)
        }

        /// The rows written back as Markdown, around what is not rows — and
        /// which are folded, kept apart from them.
        func save(_ editor: OutlineEditor) {
            let marks = OutlineFolds.marks(editor.rows)
            if marks != shownFolds {
                shownFolds = marks
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
        let editor = OutlineEditor(metrics: PhoneMetrics(face: TextSettings.face, size: TextSettings.size))
        editor.isFindInteractionEnabled = true
        let coordinator = context.coordinator
        coordinator.write = { text = $0 }
        coordinator.onFocusChange = onFocusChange
        coordinator.folds = { [store, title] in store.folds(of: title) }
        coordinator.keepFolds = { [store, title] in store.setFolds($0, of: title) }
        editor.onChange = { [weak editor] in
            guard let editor else { return }
            coordinator.save(editor)
        }
        editor.onOpenLink = { [river, title] in followOutline($0, in: river, from: title) }
        editor.onHeightChange = { [weak editor] in editor?.invalidateIntrinsicContentSize() }
        editor.onFocusChange = { coordinator.onFocusChange($0) }
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

    func updateUIView(_ editor: OutlineEditor, context: Context) {
        let coordinator = context.coordinator
        coordinator.write = { text = $0 }
        coordinator.onFocusChange = onFocusChange
        // Changed elsewhere — another river, a sync — and not being written in here.
        if text != coordinator.loaded, !editor.isFirstResponder {
            coordinator.load(text, into: editor)
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
        return CGSize(width: width, height: max(editor.fittingHeight(width: width), 30))
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
