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
    weak var textView: TiddlerTextView?
    /// What completes the `[[` being typed, on the phone, where it is
    /// offered above the keyboard.
    var suggestions: [LinkTarget] = []

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

/// What a link being typed would read with the best suggestion: the rest of
/// its title, when it starts with what is typed.
func ghostText(typed: String, best: LinkTarget?) -> String? {
    guard let best, best.kind != .new, !typed.isEmpty,
          best.title.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil,
          best.title.count > typed.count else { return nil }
    return String(best.title.dropFirst(typed.count))
}

/// The body being edited, styled as it is typed, as tall as what it holds.
struct TiddlerEditor: View {
    @Binding var text: String
    let controller: EditorController
    let suggest: (String) -> [LinkTarget]
    let exists: (String) -> Bool
    var onEscape: () -> Void = {}
    var focusOnAppear = false

    var body: some View {
        EditorRepresentable(text: $text, controller: controller, suggest: suggest,
                            styler: MarkdownStyler(size: MarkdownStyler.defaultSize, exists: exists),
                            onEscape: onEscape, focusOnAppear: focusOnAppear)
    }
}

/// The titles offered for a link being typed: each with what it is, the
/// chosen one marked.
@MainActor @Observable
final class SuggestionModel {
    var items: [LinkTarget] = []
    var selected = 0
    var typed = ""
    var pick: (LinkTarget) -> Void = { _ in }

    var current: LinkTarget? { items.indices.contains(selected) ? items[selected] : nil }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + delta + items.count) % items.count
    }
}

/// The list under the caret.
struct SuggestionList: View {
    let model: SuggestionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(model.items.enumerated()), id: \.element) { index, item in
                Button { model.pick(item) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.kind.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 18)
                            .foregroundStyle(index == model.selected ? .white : Ink.accent.color)
                        Text(item.kind == .new ? "New tiddler “\(item.title)”" : item.shown)
                            .lineLimit(1)
                            .foregroundStyle(index == model.selected ? .white : Ink.text.color)
                        Spacer(minLength: 8)
                        Text(item.kind == .new ? "" : item.kind.label)
                            .font(.caption)
                            .foregroundStyle(index == model.selected ? .white.opacity(0.8) : Ink.secondary.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(index == model.selected ? Ink.accent.color : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
        .padding(5)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Ink.rule.color))
    }
}

#if os(macOS)

/// The Mac's text view: a link being typed is finished inline — the rest
/// of the best title shown faint after the caret, Tab or → taking it — and
/// the titles that fit are listed under the caret, ↑ and ↓ choosing,
/// Return taking one, Escape putting them away.
final class TiddlerTextView: NSTextView {
    var suggest: (String) -> [LinkTarget] = { _ in [] }
    var onEscape: () -> Void = {}
    private let model = SuggestionModel()
    private lazy var panel = SuggestionPanel(model: model)
    private let ghost = NSTextField(labelWithString: "")
    /// The link put away with Escape, not offered again until it changes.
    private var dismissed: String?
    private var scrollObserver: Any?

    var text: String { string }

    var selection: NSRange {
        get { selectedRange() }
        set { setSelectedRange(newValue) }
    }

    func replace(_ range: NSRange, with text: String) {
        insertText(text, replacementRange: range)
    }

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        ghost.textColor = Palette.faint
        ghost.isHidden = true
        addSubview(ghost)
        model.pick = { [weak self] target in self?.accept(target) }
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        scrollObserver = nil
        // Scrolled, the list would be left behind: it goes.
        if let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hideCompletions() }
            }
        }
        if window == nil { hideCompletions() }
    }

    override func resignFirstResponder() -> Bool {
        hideCompletions()
        return super.resignFirstResponder()
    }

    override func didChangeText() {
        super.didChangeText()
        offerCompletions()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting, panel.isVisible || !ghost.isHidden { offerCompletions() }
    }

    /// The titles for the link being typed, under the caret, and the best
    /// one's rest after it — or neither, out of a link.
    func offerCompletions() {
        guard let range = linkPartialRange(in: string as NSString, caret: selectedRange().location), selectedRange().length == 0 else {
            dismissed = nil
            return hideCompletions()
        }
        let typed = (string as NSString).substring(with: range)
        guard typed != dismissed else { return hideCompletions() }
        dismissed = nil
        let items = suggest(typed)
        guard !items.isEmpty, let caret = caretRect() else { return hideCompletions() }
        if model.typed != typed || model.items != items {
            model.items = items
            model.selected = 0
            model.typed = typed
        }
        showGhost(ghostText(typed: typed, best: model.current), at: caret)
        if let window {
            let onScreen = window.convertToScreen(convert(caret, to: nil))
            panel.show(below: onScreen, in: window)
        }
    }

    func hideCompletions() {
        ghost.isHidden = true
        panel.hide()
    }

    /// Where the caret is, in this view.
    private func caretRect() -> NSRect? {
        guard let window else { return nil }
        var actual = NSRange()
        let onScreen = firstRect(forCharacterRange: NSRange(location: selectedRange().location, length: 0), actualRange: &actual)
        guard onScreen.origin.x.isFinite else { return nil }
        return convert(window.convertFromScreen(onScreen), from: nil)
    }

    private func showGhost(_ rest: String?, at caret: NSRect) {
        guard let rest else {
            ghost.isHidden = true
            return
        }
        let location = max(0, selectedRange().location - 1)
        let font = (textStorage?.length ?? 0) > location
            ? (textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont) : nil
        ghost.font = font ?? self.font
        ghost.stringValue = rest
        ghost.sizeToFit()
        // A label draws its text two points in; the caret's line, its height.
        ghost.frame.origin = NSPoint(x: caret.minX - 2, y: caret.minY + (caret.height - ghost.frame.height) / 2)
        ghost.isHidden = false
    }

    override func doCommand(by selector: Selector) {
        if panel.isVisible {
            switch selector {
            case #selector(moveUp(_:)): return moveSelection(-1)
            case #selector(moveDown(_:)): return moveSelection(1)
            case #selector(insertNewline(_:)), #selector(insertTab(_:)):
                if let current = model.current { return accept(current) }
            case #selector(moveRight(_:)):
                if !ghost.isHidden, let current = model.current { return accept(current) }
            case #selector(cancelOperation(_:)):
                dismissed = linkPartialRange(in: string as NSString, caret: selectedRange().location)
                    .map { (string as NSString).substring(with: $0) }
                return hideCompletions()
            default: break
            }
        } else if selector == #selector(cancelOperation(_:)) {
            return onEscape()
        }
        super.doCommand(by: selector)
    }

    private func moveSelection(_ delta: Int) {
        model.move(delta)
        if let caret = caretRect() { showGhost(ghostText(typed: model.typed, best: model.current), at: caret) }
    }

    /// A title chosen: the link finished with it, and closed.
    private func accept(_ target: LinkTarget) {
        complete(with: target.title)
    }

    func complete(with title: String) {
        guard let range = linkPartialRange(in: string as NSString, caret: selectedRange().location) else { return }
        hideCompletions()
        insertText(title, replacementRange: range)
        let text = string as NSString
        let caret = selectedRange().location
        if caret + 2 <= text.length, text.substring(with: NSRange(location: caret, length: 2)) == "]]" {
            setSelectedRange(NSRange(location: caret + 2, length: 0))
        } else {
            insertText("]]", replacementRange: selectedRange())
        }
        hideCompletions()
    }
}

/// The list of titles, in a window of its own beside the editor's, so the
/// card it is in does not cut it off.
@MainActor
final class SuggestionPanel {
    private let panel: NSPanel
    private let host: NSHostingView<SuggestionList>

    init(model: SuggestionModel) {
        host = NSHostingView(rootView: SuggestionList(model: model))
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.contentView = host
    }

    var isVisible: Bool { panel.isVisible }

    /// Under the caret's rect, on screen; above it when there is no room below.
    func show(below caret: NSRect, in window: NSWindow) {
        let size = host.fittingSize
        var origin = NSPoint(x: caret.minX - 14, y: caret.minY - size.height - 6)
        if let screen = window.screen?.visibleFrame, origin.y < screen.minY { origin.y = caret.maxY + 6 }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}

private struct EditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    let controller: EditorController
    let suggest: (String) -> [LinkTarget]
    let styler: MarkdownStyler
    let onEscape: () -> Void
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
        view.insertionPointColor = Palette.accent
        view.suggest = suggest
        view.onEscape = onEscape
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
        view.suggest = suggest
        view.onEscape = onEscape
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

        /// Fence lines in the text as last styled.
        var fences = -1

        func textStorage(_ storage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range: NSRange, changeInLength: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            let count = MarkdownStyler.fences(in: storage.string as NSString)
            // A fence come or gone changes what is inside a block below it: all of it styled again.
            parent.styler.style(storage, around: count == fences ? range : nil)
            fences = count
        }
    }
}

#else

/// The phone's text view: what completes the `[[` being typed is offered
/// in the bar above the keyboard.
final class TiddlerTextView: UITextView {
    var suggest: (String) -> [LinkTarget] = { _ in [] }
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
        controller?.suggestions = suggest((text as NSString).substring(with: range))
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
    let suggest: (String) -> [LinkTarget]
    let styler: MarkdownStyler
    let onEscape: () -> Void
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
        view.tintColor = Palette.accent
        view.suggest = suggest
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
        view.suggest = suggest
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

        /// Fence lines in the text as last styled.
        var fences = -1

        func textStorage(_ storage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions, range: NSRange, changeInLength: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            let count = MarkdownStyler.fences(in: storage.string as NSString)
            // A fence come or gone changes what is inside a block below it: all of it styled again.
            parent.styler.style(storage, around: count == fences ? range : nil)
            fences = count
        }
    }
}

/// Above the phone's keyboard: what completes the link being typed, or
/// else the formatting buttons.
struct KeyboardBar: View {
    let controller: EditorController

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if controller.suggestions.isEmpty {
                    FormattingButtons(controller: controller, compact: true)
                } else {
                    ForEach(controller.suggestions, id: \.self) { target in
                        Button { controller.complete(with: target.title) } label: {
                            Label(target.kind == .new ? "New “\(target.title)”" : target.shown, systemImage: target.kind.symbol)
                        }
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
