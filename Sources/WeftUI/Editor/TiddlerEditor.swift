import SwiftUI
import WeftCore
#if os(macOS)
import AppKit
#else
import PhoneUI
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

    /// The lines the selection touches: where they are, and what they say,
    /// without the newline after the last.
    private func selectedLines() -> (range: NSRange, lines: [String])? {
        guard let view = textView else { return nil }
        var range = text.lineRange(for: view.selection)
        if range.length > 0, text.character(at: NSMaxRange(range) - 1) == 10 { range.length -= 1 }
        return (range, text.substring(with: range).components(separatedBy: "\n"))
    }

    /// Puts lines in place of those the selection touched, the caret
    /// moved with them by `shift`.
    private func replaceLines(_ range: NSRange, with lines: [String], shift: Int) {
        guard let view = textView else { return }
        let selection = view.selection
        view.replace(range, with: lines.joined(separator: "\n"))
        view.selection = NSRange(location: max(range.location, selection.location + shift), length: selection.length)
    }

    /// A heading, a step at a time: `#`, `##`, `###`, then none — after a
    /// list item's marker, when the line is one.
    func cycleHeading() {
        guard let (range, lines) = selectedLines(), let first = lines.first else { return }
        let marker = MarkdownStyler.matches(#"^[ \t]*(?:[-*+]|\d+[.)])\s(?:\[[ xX]\]\s)?"#, in: first).first
            .map { (first as NSString).substring(with: $0.range) } ?? ""
        let body = String(first.dropFirst(marker.count))
        let hashes = body.prefix { $0 == "#" }.count
        let level = body.dropFirst(hashes).hasPrefix(" ") ? hashes : 0
        let next = level >= 3 ? 0 : level + 1
        let rest = level > 0 ? String(body.dropFirst(level + 1)) : body
        let line = marker + (next == 0 ? rest : String(repeating: "#", count: next) + " " + rest)
        replaceLines(range, with: [line] + lines.dropFirst(), shift: (line as NSString).length - (first as NSString).length)
    }

    /// A line to check off: a list item becomes one, an open one done, a
    /// done one a plain item again.
    func cycleChecklist() { cycleBox("-") }

    /// A task, as Reflect writes them — `+ [ ]` — the same way round.
    func cycleTask() { cycleBox("+") }

    private func cycleBox(_ marker: String) {
        guard let (range, lines) = selectedLines() else { return }
        var shift = 0
        let changed = lines.enumerated().map { index, line -> String in
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            let body = line.dropFirst(indent.count)
            let next: String
            if body.hasPrefix("\(marker) [ ] ") {
                next = indent + "\(marker) [x] " + body.dropFirst(6)
            } else if body.hasPrefix("\(marker) [x] ") || body.hasPrefix("\(marker) [X] ") {
                next = indent + "- " + body.dropFirst(6)
            } else if let item = ["- [ ] ", "- [x] ", "- [X] ", "+ [ ] ", "+ [x] ", "+ [X] ", "- ", "* ", "+ "].first(where: body.hasPrefix) {
                next = indent + "\(marker) [ ] " + body.dropFirst(item.count)
            } else {
                next = indent + "\(marker) [ ] " + body
            }
            if index == 0 { shift = (next as NSString).length - (line as NSString).length }
            return next
        }
        replaceLines(range, with: changed, shift: shift)
    }

    /// The lines moved a level in, or out: two spaces more at their start, or fewer.
    func shiftLines(by levels: Int) {
        guard let (range, lines) = selectedLines() else { return }
        var shift = 0
        let changed = lines.enumerated().map { index, line -> String in
            let next: String
            if levels > 0 {
                next = line.isEmpty ? line : "  " + line
            } else {
                let spaces = min(line.prefix { $0 == " " }.count, 2)
                next = spaces > 0 ? String(line.dropFirst(spaces)) : line.hasPrefix("\t") ? String(line.dropFirst()) : line
            }
            if index == 0 { shift = (next as NSString).length - (line as NSString).length }
            return next
        }
        replaceLines(range, with: changed, shift: shift)
    }

    /// The lines the selection touches moved past the line above, or below.
    func moveLines(by step: Int) {
        guard let view = textView, let (range, lines) = selectedLines() else { return }
        let whole = text as NSString
        if step < 0 {
            guard range.location > 0 else { return }
            let above = whole.lineRange(for: NSRange(location: range.location - 1, length: 0))
            let line = whole.substring(with: NSRange(location: above.location, length: above.length - 1))
            let selection = view.selection
            view.replace(NSRange(location: above.location, length: NSMaxRange(range) - above.location),
                         with: (lines + [line]).joined(separator: "\n"))
            view.selection = NSRange(location: selection.location - above.length, length: selection.length)
        } else {
            guard NSMaxRange(range) < whole.length else { return }
            let below = whole.lineRange(for: NSRange(location: NSMaxRange(range) + 1, length: 0))
            var line = whole.substring(with: below)
            if line.hasSuffix("\n") { line.removeLast() }
            let selection = view.selection
            view.replace(NSRange(location: range.location, length: NSMaxRange(below) - range.location - (whole.substring(with: below).hasSuffix("\n") ? 1 : 0)),
                         with: ([line] + lines).joined(separator: "\n"))
            view.selection = NSRange(location: selection.location + (line as NSString).length + 1, length: selection.length)
        }
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

/// A card's body, written in where it is: Markdown that reads as what it
/// says — its markup showing only on the caret's lines, its pictures, link
/// cards, embeds and queries drawn under their lines — as tall as it is.
struct TiddlerEditor: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    @Binding var text: String
    let controller: EditorController
    /// The card it is in, for links opened from what it draws.
    let card: String
    let suggest: (String) -> [LinkTarget]
    let exists: (String) -> Bool
    var onEscape: () -> Void = {}
    /// Whether to take the caret, and what to say once it has.
    var wantsCaret = false
    var onCaretTaken: () -> Void = {}
    /// Told when the caret comes in, and when it leaves.
    var onFocusChange: (Bool) -> Void = { _ in }

    var body: some View {
        EditorRepresentable(text: $text, controller: controller, store: store, river: river, card: card, suggest: suggest,
                            styler: MarkdownStyler(size: MarkdownStyler.defaultSize, exists: exists, describe: { store.riverNote($0) }),
                            onEscape: onEscape, wantsCaret: wantsCaret, onCaretTaken: onCaretTaken,
                            onFocusChange: onFocusChange)
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
    var onFocusChange: (Bool) -> Void = { _ in }
    /// Told when it is made another size: what is under its lines placed again.
    var onResize: () -> Void = {}
    weak var controller: EditorController?
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

    /// Pictures pasted, with no words with them: kept in the graph, shown
    /// where the caret is.
    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        if board.string(forType: .string) == nil, let shown = PastedPictures.keep(PastedPictures.pictures(on: board)) {
            insertText(shown, replacementRange: selectedRange())
        } else {
            super.paste(sender)
        }
    }

    /// Pictures dropped: kept in the graph, shown where they were let go.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let shown = PastedPictures.keep(PastedPictures.pictures(on: sender.draggingPasteboard)) else {
            return super.performDragOperation(sender)
        }
        let at = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
        insertText(shown, replacementRange: NSRange(location: at, length: 0))
        return true
    }

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        // Pictures taken when dropped, besides words and files.
        registerForDraggedTypes([.fileURL, .png, .tiff])
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

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        hideCompletions()
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange(false) }
        return resigned
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { onResize() }
    }

    // MARK: Links

    /// Follows a link clicked.
    var onOpenLink: (URL) -> Void = { _ in }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self && area.userInfo?["links"] != nil { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: ["links": true]))
    }

    /// Over a link, the pointer is a hand: it is to be clicked.
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if link(at: convert(event.locationInWindow, from: nil)) != nil { NSCursor.pointingHand.set() }
    }

    override func cursorUpdate(with event: NSEvent) {
        if link(at: convert(event.locationInWindow, from: nil)) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    /// A click on a link follows it — once the button comes up without the
    /// pointer having moved off to drag.
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 1, !event.modifierFlags.contains(.shift),
              let url = link(at: convert(event.locationInWindow, from: nil)) else { return super.mouseDown(with: event) }
        let start = event.locationInWindow
        while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            let moved = hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y)
            if next.type == .leftMouseUp {
                if moved < 4 { onOpenLink(url) }
                return
            }
            if moved >= 4 { return }
        }
    }

    /// A link's menu: to open it, or copy it.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let url = link(at: convert(event.locationInWindow, from: nil)) else { return super.menu(for: event) }
        let menu = NSMenu(title: "Link")
        let title = InlineMarkdown.title(from: url)
        menu.addItem(ActionItem(title: title == nil ? "Open Link" : "Open") { [weak self] in self?.onOpenLink(url) })
        menu.addItem(.separator())
        menu.addItem(ActionItem(title: "Copy Link") { Platform.copy(title.map { "[[\($0)]]" } ?? url.absoluteString) })
        return menu
    }

    /// Format ▸ Checklist Item and Task, ⌘↩ and ⇧⌘↩: as the outline's.
    @objc func cycleChecklist(_ sender: Any?) { controller?.cycleChecklist() }
    @objc func cycleTask(_ sender: Any?) { controller?.cycleTask() }

    /// ⌘B, ⌘I, ⌘K: bold, italic, a link — there being no bar of buttons.
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, let controller {
            switch event.charactersIgnoringModifiers {
            case "b": return controller.wrap("**")
            case "i": return controller.wrap("*")
            case "k": return controller.startLink()
            default: break
            }
        }
        super.keyDown(with: event)
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
/// A menu item that does what it is given.
private final class ActionItem: NSMenuItem {
    private let action_: () -> Void

    init(title: String, _ action: @escaping () -> Void) {
        action_ = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("unused") }

    @objc private func run() { action_() }
}

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
    let store: WikiStore
    let river: River
    let card: String
    let suggest: (String) -> [LinkTarget]
    let styler: MarkdownStyler
    let onEscape: () -> Void
    let wantsCaret: Bool
    let onCaretTaken: () -> Void
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TiddlerTextView {
        let storage = NSTextStorage()
        let layout = LiveLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        // In line with the card's title.
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let view = TiddlerTextView(frame: .zero, textContainer: container)
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        // ⌘F in a card: its words found, as in Prism's outline.
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.textContainerInset = NSSize(width: 0, height: 2)
        view.font = PlatformFont.systemFont(ofSize: styler.size)
        view.insertionPointColor = Palette.accent
        view.suggest = suggest
        view.onEscape = onEscape
        view.controller = controller
        view.onOpenLink = { [river, card] in follow($0, in: river, from: card) }
        let live = LiveMarkdown(view: view, styler: styler, store: store, river: river, card: card)
        live.onResize = { [weak view] in view?.invalidateIntrinsicContentSize() }
        context.coordinator.live = live
        view.onResize = { [weak live] in live?.attachments.place() }
        view.onFocusChange = { [weak view, weak coordinator = context.coordinator] focused in
            guard let view, let coordinator else { return }
            coordinator.live?.focusChanged(focused, selection: view.selectedRange())
            coordinator.parent.onFocusChange(focused)
        }
        view.delegate = context.coordinator
        storage.delegate = context.coordinator
        view.string = text
        live.restyleAll()
        controller.textView = view
        return view
    }

    func updateNSView(_ view: TiddlerTextView, context: Context) {
        context.coordinator.parent = self
        view.suggest = suggest
        view.onEscape = onEscape
        controller.textView = view
        if view.string != text {
            view.string = text
            context.coordinator.live?.changed()
        }
        if wantsCaret {
            DispatchQueue.main.async { [onCaretTaken] in
                guard let window = view.window else { return }
                if window.firstResponder !== view {
                    window.makeFirstResponder(view)
                    view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
                }
                onCaretTaken()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: TiddlerTextView, context: Context) -> CGSize? {
        // Its ideal width the one it has: measured at another, it is laid out again twice.
        let width = proposal.width ?? (view.bounds.width > 0 ? view.bounds.width : 600)
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        func fit(_ width: CGFloat) {
            let containerWidth = max(50, width - view.textContainerInset.width * 2)
            if abs(container.containerSize.width - containerWidth) > 0.5 {
                container.containerSize = NSSize(width: containerWidth, height: .greatestFiniteMagnitude)
                context.coordinator.live?.attachments.place()
            }
        }
        fit(width)
        layout.ensureLayout(for: container)
        var height = layout.usedRect(for: container).height
        height = max(height, context.coordinator.live?.attachments.bottom ?? 0, ceil(styler.size * 1.5))
        // Asked of another width than it has, laid out again at its own:
        // else it is drawn wrapped as it was asked, past its frame or short of it.
        if view.bounds.width > 0, abs(view.bounds.width - width) > 0.5 { fit(view.bounds.width) }
        return CGSize(width: width, height: ceil(height) + view.textContainerInset.height * 2)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: EditorRepresentable
        var live: LiveMarkdown?

        init(_ parent: EditorRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            live?.changed()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            live?.selectionChanged(view.selectedRange())
        }

        func textStorage(_ storage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range: NSRange, changeInLength: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated { live?.edited(range, in: storage) }
        }
    }
}

#else

/// The phone's text view: over the keys, Prism's bar of glass — undo, the
/// line moved in, out, up and down, its tools, Aa's formatting, Done — and
/// in its capsule what completes the `[[` being typed.
final class TiddlerTextView: UITextView {
    var suggest: (String) -> [LinkTarget] = { _ in [] }
    weak var controller: EditorController?
    /// Told when it is laid out again: what is under its lines placed again.
    var onLayout: () -> Void = {}
    private var laidOutWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - laidOutWidth) > 0.5 {
            laidOutWidth = bounds.width
            onLayout()
        }
    }

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

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), isEditable, UIPasteboard.general.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    /// Pictures pasted, with no words with them: kept in the graph, shown
    /// where the caret is.
    override func paste(_ sender: Any?) {
        let board = UIPasteboard.general
        if board.hasImages, !board.hasStrings, let shown = PastedPictures.keep(PastedPictures.pictures(on: board)) {
            insertText(shown)
        } else {
            super.paste(sender)
        }
    }

    /// A tap on a link follows it, instead of putting the caret there.
    func followLinks(_ open: @escaping (URL) -> Void) {
        let tap = LinkTap(view: self, open: open)
        linkTap = tap
        addGestureRecognizer(tap.recognizer)
    }

    private var linkTap: LinkTap?

    func offerCompletions() {
        guard let range = linkPartialRange(in: text as NSString, caret: selectedRange.location) else {
            if controller?.suggestions.isEmpty == false {
                controller?.suggestions = []
                toolbar?.show(chips: []) { _ in }
            }
            return
        }
        let found = suggest((text as NSString).substring(with: range))
        controller?.suggestions = found
        toolbar?.show(chips: found.map { ($0.kind == .new ? "New “\($0.title)”" : $0.shown, $0.kind.symbol) }) { [weak self] index in
            guard found.indices.contains(index) else { return }
            self?.complete(with: found[index].title)
        }
    }

    // MARK: The bar over the keys

    private lazy var madeToolbar = OutlineToolbar(target: self, tools: [
        .init("list.bullet", #selector(toggleList), "List"),
        .init("checkmark.square", #selector(cycleChecklist), "Checklist"),
        .init("link", #selector(insertLink), "Link"),
        .init("square.on.square", #selector(insertEmbed), "Embed"),
        .init("lightbulb", #selector(insertCallout), "Callout"),
    ])

    private var toolbar: OutlineToolbar? { inputAccessoryView as? OutlineToolbar }

    override var inputAccessoryView: UIView? {
        get { madeToolbar }
        set {}
    }

    /// ↶ and ↷ dimmed when there is nothing to undo, or redo.
    func showUndoState() {
        toolbar?.showUndo(canUndo: undoManager?.canUndo ?? false, canRedo: undoManager?.canRedo ?? false)
    }

    @objc func undoChange() { undoManager?.undo(); showUndoState() }
    @objc func redoChange() { undoManager?.redo(); showUndoState() }
    @objc func indent() { controller?.shiftLines(by: 1) }
    @objc func outdent() { controller?.shiftLines(by: -1) }
    @objc func moveUp() { controller?.moveLines(by: -1) }
    @objc func moveDown() { controller?.moveLines(by: 1) }
    @objc func toggleList() { controller?.prefixLines("- ") }
    @objc func cycleChecklist() { controller?.cycleChecklist() }
    @objc func insertLink() { controller?.startLink() }
    @objc func insertEmbed() { controller?.startLink(embed: true) }
    @objc func insertCallout() { controller?.insertBlock("> [!NOTE]\n> ") }
    @objc func makeBold() { controller?.wrap("**") }
    @objc func makeItalic() { controller?.wrap("*") }
    @objc func makeStruck() { controller?.wrap("~~") }
    @objc func makeHighlighted() { controller?.wrap("==") }
    @objc func makeCode() { controller?.wrap("`") }
    @objc func cycleHeading() { controller?.cycleHeading() }
    @objc func toggleQuote() { controller?.prefixLines("> ") }

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

/// Taps on a text view's links: recognized only on one, and before the
/// text view's own taps — which would put the caret there — so those wait.
private final class LinkTap: NSObject, UIGestureRecognizerDelegate {
    let recognizer = UITapGestureRecognizer()
    private weak var view: UITextView?
    private let open: (URL) -> Void

    init(view: UITextView, open: @escaping (URL) -> Void) {
        self.view = view
        self.open = open
        super.init()
        recognizer.addTarget(self, action: #selector(tapped))
        recognizer.delegate = self
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let view, let url = view.link(at: recognizer.location(in: view)) else { return }
        open(url)
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let view else { return false }
        return view.link(at: recognizer.location(in: view)) != nil
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other is UITapGestureRecognizer && other !== recognizer
    }
}

private struct EditorRepresentable: UIViewRepresentable {
    @Binding var text: String
    let controller: EditorController
    let store: WikiStore
    let river: River
    let card: String
    let suggest: (String) -> [LinkTarget]
    let styler: MarkdownStyler
    let onEscape: () -> Void
    let wantsCaret: Bool
    let onCaretTaken: () -> Void
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TiddlerTextView {
        // Laid out by the layout manager that draws links as pills.
        let storage = NSTextStorage()
        let layout = LiveLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 350, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let view = TiddlerTextView(frame: .zero, textContainer: container)
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.font = PlatformFont.systemFont(ofSize: styler.size)
        view.autocorrectionType = .default
        view.smartQuotesType = .no
        view.isFindInteractionEnabled = true
        view.smartDashesType = .no
        view.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        // In line with the card's title.
        view.textContainer.lineFragmentPadding = 0
        view.tintColor = Palette.accent
        view.suggest = suggest
        view.controller = controller
        view.followLinks { [river, card] in follow($0, in: river, from: card) }
        let live = LiveMarkdown(view: view, styler: styler, store: store, river: river, card: card)
        live.onResize = { [weak view] in view?.invalidateIntrinsicContentSize() }
        context.coordinator.live = live
        view.onLayout = { [weak live] in live?.attachments.place() }
        view.delegate = context.coordinator
        view.textStorage.delegate = context.coordinator
        view.text = text
        live.restyleAll()
        controller.textView = view
        return view
    }

    func updateUIView(_ view: TiddlerTextView, context: Context) {
        context.coordinator.parent = self
        view.suggest = suggest
        controller.textView = view
        if view.text != text {
            view.text = text
            context.coordinator.live?.changed()
        }
        if wantsCaret {
            DispatchQueue.main.async { [onCaretTaken] in
                if !view.isFirstResponder {
                    view.becomeFirstResponder()
                    view.selectedRange = NSRange(location: (view.text as NSString).length, length: 0)
                }
                onCaretTaken()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: TiddlerTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 350
        let size = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let below = (context.coordinator.live?.attachments.bottom ?? 0) + view.textContainerInset.top + view.textContainerInset.bottom
        return CGSize(width: width, height: max(size.height, below, ceil(styler.size * 1.6)))
    }

    final class Coordinator: NSObject, UITextViewDelegate, NSTextStorageDelegate {
        var parent: EditorRepresentable
        var live: LiveMarkdown?

        init(_ parent: EditorRepresentable) {
            self.parent = parent
        }

        func textViewDidChange(_ view: UITextView) {
            parent.text = view.text
            live?.changed()
            (view as? TiddlerTextView)?.offerCompletions()
            (view as? TiddlerTextView)?.showUndoState()
        }

        func textViewDidChangeSelection(_ view: UITextView) {
            live?.selectionChanged(view.selectedRange)
            (view as? TiddlerTextView)?.offerCompletions()
        }

        func textViewDidBeginEditing(_ view: UITextView) {
            live?.focusChanged(true, selection: view.selectedRange)
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ view: UITextView) {
            live?.focusChanged(false, selection: view.selectedRange)
            parent.onFocusChange(false)
        }

        func textStorage(_ storage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions, range: NSRange, changeInLength: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated { live?.edited(range, in: storage) }
        }
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
