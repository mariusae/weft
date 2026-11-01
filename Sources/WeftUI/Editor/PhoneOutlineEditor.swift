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

    final class Coordinator {
        /// What is around the rows — front matter, the title — written back with them.
        var shell = OutlineMarkdown.parse("")
        /// The text last loaded, or written: a change from elsewhere is one that differs.
        var loaded: String?
        var write: (String) -> Void = { _ in }
        var onFocusChange: (Bool) -> Void = { _ in }

        func load(_ text: String, into editor: OutlineEditor) {
            loaded = text
            shell = OutlineMarkdown.parse(text)
            editor.load(shell.rows.isEmpty ? [.blank] : shell.rows)
        }

        /// The rows written back as Markdown, around what is not rows.
        func save(_ editor: OutlineEditor) {
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
        let editor = OutlineEditor(metrics: PhoneMetrics(face: .system, size: MarkdownStyler.defaultSize))
        let coordinator = context.coordinator
        coordinator.write = { text = $0 }
        coordinator.onFocusChange = onFocusChange
        editor.onChange = { [weak editor] in
            guard let editor else { return }
            coordinator.save(editor)
        }
        editor.onOpenLink = { [river, title] in followOutline($0, in: river, from: title) }
        editor.onHeightChange = { [weak editor] in editor?.invalidateIntrinsicContentSize() }
        editor.onFocusChange = { coordinator.onFocusChange($0) }
        // `[[` completes from the graph's notes, as Prism's does.
        store.prepareLinkNotes { notes in
            OutlineEditor.suggest = { LinkSuggestions.candidates($0, index: notes) }
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
