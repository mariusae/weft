import Foundation
import ReflectCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// An untitled page's first line, made its title: from the card's More,
/// or ⌃⌘T on the Mac; and while that line is a heading — `# ` — by Title
/// at its end, or Return there.
enum FirstLineTitle {
    /// The first line with anything on it, as a paragraph: its line break too.
    static func line(in text: NSString) -> NSRange? {
        var location = 0
        while location < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            guard paragraph.length > 0 else { break }
            if !text.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return paragraph }
            location = NSMaxRange(paragraph)
        }
        return nil
    }

    /// A paragraph without its line break.
    static func words(of line: NSRange, in text: NSString) -> NSRange {
        var words = line
        while words.length > 0, [10, 13].contains(text.character(at: NSMaxRange(words) - 1)) { words.length -= 1 }
        return words
    }

    /// The title the line makes: empty, when it has no words to make one.
    static func title(of line: NSRange, in text: NSString) -> String {
        Untitled.title(from: text.substring(with: words(of: line, in: text)))
    }

    /// What goes when the line is made the title: it, the blank lines
    /// before it, and those after it.
    static func taken(by line: NSRange, in text: NSString) -> NSRange {
        var end = NSMaxRange(line)
        while end < text.length {
            let next = text.paragraphRange(for: NSRange(location: end, length: 0))
            guard next.length > 0, text.substring(with: next).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
            end = NSMaxRange(next)
        }
        return NSRange(location: 0, length: end)
    }
}

extension TiddlerTextView {
    fileprivate var shownText: NSString {
        #if os(macOS)
        string as NSString
        #else
        (text ?? "") as NSString
        #endif
    }

    /// The first line with words made the title, taken out of what it
    /// says — with the blank lines round it — the caret where it began.
    /// False, when the page has a title, or nothing to be titled by.
    @discardableResult
    func titleByFirstLine() -> Bool {
        let text = shownText
        guard isUntitled(), let line = FirstLineTitle.line(in: text) else { return false }
        let title = FirstLineTitle.title(of: line, in: text)
        guard !title.isEmpty else { return false }
        let taken = FirstLineTitle.taken(by: line, in: text)
        // Titled first: the text, changed, is saved under it.
        onTitle(title)
        replace(taken, with: "")
        selection = NSRange(location: 0, length: 0)
        return true
    }
}

extension FirstLineTitle {
    /// The first line's words, when it is a top heading — `# ` and words:
    /// what an untitled page is offered its title by, as the outline offers.
    static func heading(in text: NSString) -> NSRange? {
        guard let line = line(in: text) else { return nil }
        let words = words(of: line, in: text)
        let written = text.substring(with: words).trimmingCharacters(in: .whitespaces)
        guard written.hasPrefix("# "), written.dropFirst(2).contains(where: { !$0.isWhitespace }) else { return nil }
        return words
    }
}

extension TiddlerTextView {
    /// Return at the end of the first line, a heading, of an untitled page:
    /// that line made the title — whenever it is made one.
    func titleByHeading(at location: Int) -> Bool {
        guard isUntitled(), selection.length == 0, let words = FirstLineTitle.heading(in: shownText),
              location == NSMaxRange(words) else { return false }
        return titleByFirstLine()
    }

    /// Title, quiet, at the end of the first line while it is a heading of
    /// an untitled page and the caret is in it; tapped, that line the title.
    func placeTitleChip() {
        let text = shownText
        guard isWritingHere, isUntitled(), let words = FirstLineTitle.heading(in: text),
              !FirstLineTitle.title(of: words, in: text).isEmpty,
              let layout = layoutManagerForAttachments, let container = textContainerForAttachments else {
            if titleChip?.isHidden == false { titleChip?.isHidden = true }
            return
        }
        let glyphs = layout.glyphRange(forCharacterRange: words, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        layout.ensureLayout(forGlyphRange: glyphs)
        let last = NSMaxRange(glyphs) - 1
        let used = layout.lineFragmentUsedRect(forGlyphAt: last, effectiveRange: nil)
        let end = layout.boundingRect(forGlyphRange: NSRange(location: last, length: 1), in: container)
        let chip = titleChip ?? makeTitleChip()
        #if os(macOS)
        let size = chip.fittingSize
        let origin = textContainerOrigin
        var x = end.maxX + origin.x + 8
        #else
        let size = chip.intrinsicContentSize
        let origin = CGPoint(x: textContainerInset.left, y: textContainerInset.top)
        var x = end.maxX + origin.x + 2
        #endif
        if x + size.width > bounds.width { x = max(0, bounds.width - size.width) }
        let frame = CGRect(x: x.rounded(), y: (used.midY + origin.y - size.height / 2).rounded(), width: size.width, height: size.height)
        if chip.frame != frame { chip.frame = frame }
        if chip.isHidden { chip.isHidden = false }
    }

    #if os(macOS)
    private var isWritingHere: Bool { window?.firstResponder === self }

    private func makeTitleChip() -> NSButton {
        // As the outline's, quiet: a word in the margin, not a button asking.
        let chip = NSButton(title: "Title", target: self, action: #selector(titleChipClicked(_:)))
        chip.bezelStyle = .inline
        chip.controlSize = .small
        chip.isBordered = false
        chip.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        chip.imagePosition = .imageLeading
        chip.imageHugsTitle = true
        chip.contentTintColor = .tertiaryLabelColor
        chip.attributedTitle = NSAttributedString(string: "Title", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])
        chip.toolTip = "Make this line the title (⌃⌘T)"
        chip.setAccessibilityLabel("Make this line the title")
        chip.refusesFirstResponder = true
        chip.sizeToFit()
        chip.isHidden = true
        addSubview(chip)
        titleChip = chip
        return chip
    }

    @objc private func titleChipClicked(_ sender: Any?) {
        titleByFirstLine()
        window?.makeFirstResponder(self)
    }
    #else
    private var isWritingHere: Bool { isFirstResponder }

    private func makeTitleChip() -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        configuration.imagePadding = 3
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        var title = AttributedString("Title")
        title.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        configuration.attributedTitle = title
        configuration.baseForegroundColor = .tertiaryLabel
        let chip = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.titleByFirstLine() })
        chip.accessibilityLabel = "Make the first line the title"
        chip.isHidden = true
        chip.sizeToFit()
        addSubview(chip)
        titleChip = chip
        return chip
    }
    #endif
}
