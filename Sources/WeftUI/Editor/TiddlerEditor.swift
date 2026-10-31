import SwiftUI
import WeftCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What the formatting bar does to the text being edited: wraps the
/// selection in markup, starts lines with it, puts blocks in, starts links.
@MainActor @Observable
final class EditorController {
    #if os(macOS)
    weak var textView: TiddlerTextView?
    #else
    weak var textView: TiddlerTextView?
    #endif
    /// Titles completing the `[[` being typed, on the phone, where they are
    /// offered above the keyboard.
    var suggestions: [String] = []

    private var text: NSString { (textView?.text ?? "") as NSString }

    /// Wraps the selection — or puts a pair at the caret — in `marker`.
    func wrap(_ marker: String) {
        guard let view = textView else { return }
        let selection = view.selection
        let selected = text.substring(with: selection)
        view.replace(selection, with: marker + selected + marker)
        let length = (marker as NSString).length
        view.selection = selected.isEmpty
            ? NSRange(location: selection.location + length, length: 0)
            : NSRange(location: selection.location + length, length: selection.length)
    }

    /// Starts every line the selection touches with `prefix`, or takes it
    /// off when they all have it.
    func prefixLines(_ prefix: String) {
        guard let view = textView else { return }
        let lines = text.lineRange(for: view.selection)
        let block = text.substring(with: lines)
        var parts = block.components(separatedBy: "\n")
        let trailing = parts.last == "" ? parts.removeLast() : nil
        let all = parts.allSatisfy { $0.hasPrefix(prefix) }
        parts = parts.map { all ? String($0.dropFirst(prefix.count)) : prefix + $0 }
        let replaced = parts.joined(separator: "\n") + (trailing != nil ? "\n" : "")
        view.replace(lines, with: replaced)
        view.selection = NSRange(location: lines.location + (replaced as NSString).length - (trailing != nil ? 1 : 0), length: 0)
    }

    /// Puts a block — a query, a callout — in a paragraph of its own at the caret.
    func insertBlock(_ block: String) {
        guard let view = textView else { return }
        let caret = view.selection.location
        let before = caret == 0 ? "" : text.substring(to: caret)
        let lead = before.isEmpty || before.hasSuffix("\n\n") ? "" : before.hasSuffix("\n") ? "\n" : "\n\n"
        let insertion = lead + block + "\n"
        view.replace(view.selection, with: insertion)
        view.selection = NSRange(location: caret + (insertion as NSString).length, length: 0)
    }

    /// Starts a link — or an embed — at the caret, and offers titles for it.
    func startLink(embed: Bool = false) {
        guard let view = textView else { return }
        let selection = view.selection
        let selected = text.substring(with: selection)
        if selected.isEmpty {
            view.replace(selection, with: embed ? "![[" : "[[")
            view.offerCompletions()
        } else {
            view.replace(selection, with: (embed ? "![[" : "[[") + selected + "]]")
        }
    }

    /// Finishes the `[[` being typed with a title.
    func complete(with title: String) {
        textView?.complete(with: title)
    }
}

/// The range from just after an unclosed `[[` on the caret's line to the
/// caret: the title being typed. Nil when the caret is in no link.
func linkPartialRange(in text: NSString, caret: Int) -> NSRange? {
    guard caret <= text.length else { return nil }
    let line = text.lineRange(for: NSRange(location: caret, length: 0))
    let before = text.substring(with: NSRange(location: line.location, length: caret - line.location)) as NSString
    let open = before.range(of: "[[", options: .backwards)
    guard open.location != NSNotFound else { return nil }
    let typed = before.substring(from: open.upperBound)
    guard !typed.contains("]"), !typed.contains("|") else { return nil }
    return NSRange(location: line.location + open.upperBound, length: caret - line.location - open.upperBound)
}

/// Titles for a partial one: those starting with it, then those containing it.
func completions(for partial: String, among titles: [String], limit: Int = 30) -> [String] {
    let query = partial.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return Array(titles.prefix(limit)) }
    var starts: [String] = [], contains: [String] = []
    for title in titles {
        if title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
            starts.append(title)
        } else if title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            contains.append(title)
        }
        if starts.count >= limit { break }
    }
    return Array((starts + contains).prefix(limit))
}

/// The body being edited, styled as it is typed, as tall as what it holds.
struct TiddlerEditor: View {
    @Binding var text: String
    let controller: EditorController
    let titles: () -> [String]
    let exists: (String) -> Bool
    var focusOnAppear = false

    var body: some View {
        EditorRepresentable(text: $text, controller: controller, titles: titles,
                            styler: MarkdownStyler(size: MarkdownStyler.defaultSize, exists: exists), focusOnAppear: focusOnAppear)
    }
}

#if os(macOS)

/// The Mac's text view: completion of the `[[` being typed, through the
/// system's own completion list.
final class TiddlerTextView: NSTextView {
    var titles: () -> [String] = { [] }
    private var completing = false

    var text: String { string }

    var selection: NSRange {
        get { selectedRange() }
        set { setSelectedRange(newValue) }
    }

    func replace(_ range: NSRange, with text: String) {
        insertText(text, replacementRange: range)
    }

    override var rangeForUserCompletion: NSRange {
        linkPartialRange(in: string as NSString, caret: selectedRange().location) ?? super.rangeForUserCompletion
    }

    func offerCompletions() {
        guard !completing, linkPartialRange(in: string as NSString, caret: selectedRange().location) != nil else { return }
        completing = true
        complete(nil)
        completing = false
    }

    override func didChangeText() {
        super.didChangeText()
        if !completing { offerCompletions() }
    }

    override func insertCompletion(_ word: String, forPartialWordRange range: NSRange, movement: Int, isFinal: Bool) {
        completing = true
        defer { completing = false }
        super.insertCompletion(word, forPartialWordRange: range, movement: movement, isFinal: isFinal)
        if isFinal, movement == NSTextMovement.return.rawValue || movement == NSTextMovement.tab.rawValue {
            closeLink()
        }
    }

    func complete(with title: String) {
        guard let range = linkPartialRange(in: string as NSString, caret: selectedRange().location) else { return }
        insertText(title, replacementRange: range)
        closeLink()
    }

    /// Steps past the link's `]]`, writing it when it is not there.
    private func closeLink() {
        let text = string as NSString
        let caret = selectedRange().location
        if caret + 2 <= text.length, text.substring(with: NSRange(location: caret, length: 2)) == "]]" {
            setSelectedRange(NSRange(location: caret + 2, length: 0))
        } else {
            insertText("]]", replacementRange: selectedRange())
        }
    }
}

private struct EditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    let controller: EditorController
    let titles: () -> [String]
    let styler: MarkdownStyler
    let focusOnAppear: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TiddlerTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let view = TiddlerTextView(frame: .zero, textContainer: container)
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.textContainerInset = NSSize(width: 4, height: 6)
        view.font = PlatformFont.systemFont(ofSize: styler.size)
        view.titles = titles
        view.delegate = context.coordinator
        storage.delegate = context.coordinator
        view.string = text
        controller.textView = view
        if focusOnAppear {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        return view
    }

    func updateNSView(_ view: TiddlerTextView, context: Context) {
        context.coordinator.parent = self
        view.titles = titles
        controller.textView = view
        if view.string != text { view.string = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: TiddlerTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 600
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        container.containerSize = NSSize(width: max(50, width - view.textContainerInset.width * 2), height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let height = layout.usedRect(for: container).height + view.textContainerInset.height * 2
        return CGSize(width: width, height: max(160, ceil(height) + 20))
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: EditorRepresentable

        init(_ parent: EditorRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        func textStorage(_ storage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range: NSRange, changeInLength: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            parent.styler.style(storage)
        }

        func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange range: NSRange,
                      indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            guard let view = textView as? TiddlerTextView,
                  linkPartialRange(in: view.string as NSString, caret: view.selectedRange().location) != nil else { return words }
            index?.pointee = -1
            return completions(for: (view.string as NSString).substring(with: range), among: view.titles())
        }
    }
}

#else

/// The phone's text view: titles completing the `[[` being typed are
/// offered in the bar above the keyboard.
final class TiddlerTextView: UITextView {
    var titles: () -> [String] = { [] }
    weak var controller: EditorController?

    var selection: NSRange {
        get { selectedRange }
        set { selectedRange = newValue }
    }

    func replace(_ range: NSRange, with text: String) {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = textRange(from: start, to: end) else { return }
        replace(textRange, withText: text)
    }

    func offerCompletions() {
        guard let range = linkPartialRange(in: text as NSString, caret: selectedRange.location) else {
            if controller?.suggestions.isEmpty == false { controller?.suggestions = [] }
            return
        }
        controller?.suggestions = completions(for: (text as NSString).substring(with: range), among: titles(), limit: 20)
    }

    func complete(with title: String) {
        guard let range = linkPartialRange(in: text as NSString, caret: selectedRange.location) else { return }
        replace(range, with: title)
        let caret = selectedRange.location
        let text = self.text as NSString
        if caret + 2 <= text.length, text.substring(with: NSRange(location: caret, length: 2)) == "]]" {
            selectedRange = NSRange(location: caret + 2, length: 0)
        } else {
            replace(selectedRange, with: "]]")
        }
        controller?.suggestions = []
    }
}

private struct EditorRepresentable: UIViewRepresentable {
    @Binding var text: String
    let controller: EditorController
    let titles: () -> [String]
    let styler: MarkdownStyler
    let focusOnAppear: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TiddlerTextView {
        let view = TiddlerTextView(usingTextLayoutManager: false)
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.font = PlatformFont.systemFont(ofSize: styler.size)
        view.autocorrectionType = .default
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        view.titles = titles
        view.controller = controller
        view.delegate = context.coordinator
        view.textStorage.delegate = context.coordinator
        view.text = text
        let bar = UIHostingController(rootView: KeyboardBar(controller: controller))
        bar.view.frame = CGRect(x: 0, y: 0, width: 400, height: 46)
        bar.view.backgroundColor = .clear
        bar.sizingOptions = []
        view.inputAccessoryView = bar.view
        context.coordinator.bar = bar
        controller.textView = view
        if focusOnAppear {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        }
        return view
    }

    func updateUIView(_ view: TiddlerTextView, context: Context) {
        context.coordinator.parent = self
        view.titles = titles
        controller.textView = view
        if view.text != text { view.text = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: TiddlerTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 350
        let size = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(140, size.height + 12))
    }

    final class Coordinator: NSObject, UITextViewDelegate, NSTextStorageDelegate {
        var parent: EditorRepresentable
        var bar: UIHostingController<KeyboardBar>?

        init(_ parent: EditorRepresentable) {
            self.parent = parent
        }

        func textViewDidChange(_ view: UITextView) {
            parent.text = view.text
            (view as? TiddlerTextView)?.offerCompletions()
        }

        func textViewDidChangeSelection(_ view: UITextView) {
            (view as? TiddlerTextView)?.offerCompletions()
        }

        func textStorage(_ storage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions, range: NSRange, changeInLength: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            parent.styler.style(storage)
        }
    }
}

/// Above the phone's keyboard: titles for the link being typed, or else
/// the formatting buttons.
struct KeyboardBar: View {
    let controller: EditorController

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if controller.suggestions.isEmpty {
                    FormattingButtons(controller: controller, compact: true)
                } else {
                    ForEach(controller.suggestions, id: \.self) { title in
                        Button(title) { controller.complete(with: title) }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 46)
        .background(.bar)
    }
}

#endif

/// Bold, italic, code, heading, list, link, embed, callout: the buttons of
/// the formatting bar, above the editor on the Mac, above the keyboard on
/// the phone.
struct FormattingButtons: View {
    let controller: EditorController
    var compact = false

    var body: some View {
        Group {
            button("bold", "Bold (⌘B)") { controller.wrap("**") }.keyboardShortcut("b")
            button("italic", "Italic (⌘I)") { controller.wrap("*") }.keyboardShortcut("i")
            button("chevron.left.forwardslash.chevron.right", "Code") { controller.wrap("`") }
            button("number", "Heading") { controller.prefixLines("## ") }
            button("list.bullet", "List") { controller.prefixLines("- ") }
            button("link", "Link to a Tiddler (⌘K)") { controller.startLink() }.keyboardShortcut("k")
            button("square.on.square", "Embed a Tiddler") { controller.startLink(embed: true) }
            button("lightbulb", "Callout") { controller.insertBlock("> [!NOTE]\n> ") }
        }
    }

    private func button(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: compact ? 30 : 24, height: compact ? 30 : 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
