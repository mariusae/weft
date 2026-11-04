import Foundation
import ReflectCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// An untitled page's first line, made its title: by Title, at the end of
/// that line while the caret is on it; ⌃⌘T on the Mac; the bar over the
/// keys' Title on the phone.
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

    /// Where the chip goes: just after the line's last letter, on its last
    /// line's middle — or, with no room after it, at the right edge.
    @MainActor
    static func frame(for words: NSRange, layout: NSLayoutManager, container: NSTextContainer, origin: CGPoint,
                      width: CGFloat, size: CGSize) -> CGRect? {
        let glyphs = layout.glyphRange(forCharacterRange: words, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        layout.ensureLayout(forGlyphRange: glyphs)
        let last = NSMaxRange(glyphs) - 1
        let used = layout.lineFragmentUsedRect(forGlyphAt: last, effectiveRange: nil)
        let end = layout.boundingRect(forGlyphRange: NSRange(location: last, length: 1), in: container)
        var x = end.maxX + origin.x + 8
        if x + size.width > width { x = max(0, width - size.width) }
        return CGRect(x: x.rounded(), y: (used.midY + origin.y - size.height / 2).rounded(), width: size.width, height: size.height)
    }
}

extension TiddlerTextView {
    private var shownText: NSString {
        #if os(macOS)
        string as NSString
        #else
        (text ?? "") as NSString
        #endif
    }

    private var hasCaret: Bool {
        #if os(macOS)
        window?.firstResponder === self
        #else
        isFirstResponder
        #endif
    }

    func setUpTitleChip() {
        #if os(macOS)
        titleChip.bezelStyle = .inline
        titleChip.controlSize = .small
        titleChip.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        titleChip.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        titleChip.imagePosition = .imageLeading
        titleChip.imageHugsTitle = true
        titleChip.contentTintColor = Palette.accent
        titleChip.toolTip = "Make this line the title (⌃⌘T)"
        titleChip.target = self
        titleChip.action = #selector(titleChipClicked(_:))
        titleChip.refusesFirstResponder = true
        titleChip.sizeToFit()
        #else
        var look = UIButton.Configuration.tinted()
        look.title = "Title"
        look.image = UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        look.imagePadding = 4
        look.cornerStyle = .capsule
        look.buttonSize = .small
        look.baseForegroundColor = Palette.accent
        look.baseBackgroundColor = Palette.accent
        look.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
            return attributes
        }
        titleChip.configuration = look
        titleChip.addTarget(self, action: #selector(titleChipClicked(_:)), for: .touchUpInside)
        titleChip.sizeToFit()
        #endif
        #if os(macOS)
        titleChip.setAccessibilityLabel("Make this line the title")
        #else
        titleChip.accessibilityLabel = "Make this line the title"
        #endif
        titleChip.isHidden = true
        addSubview(titleChip)
    }

    @objc private func titleChipClicked(_ sender: Any?) {
        titleByFirstLine()
        #if os(macOS)
        window?.makeFirstResponder(self)
        #endif
    }

    /// The chip shown at the end of the first line, while the caret is on
    /// it — an untitled page's, saying something to be titled by.
    func placeTitleChip() {
        let text = shownText
        guard hasCaret, isUntitled(), let line = FirstLineTitle.line(in: text), let layout = layoutManagerForAttachments,
              case let words = FirstLineTitle.words(of: line, in: text), words.length > 0,
              case let caret = selection, caret.location >= line.location, NSMaxRange(caret) <= NSMaxRange(words),
              !FirstLineTitle.title(of: line, in: text).isEmpty else {
            if !titleChip.isHidden { titleChip.isHidden = true }
            return
        }
        #if os(macOS)
        let size = titleChip.fittingSize
        guard let container = textContainer,
              let frame = FirstLineTitle.frame(for: words, layout: layout, container: container, origin: textContainerOrigin,
                                               width: bounds.width, size: size) else { return }
        #else
        let size = titleChip.intrinsicContentSize
        guard let frame = FirstLineTitle.frame(for: words, layout: layout, container: textContainer,
                                               origin: CGPoint(x: textContainerInset.left, y: textContainerInset.top),
                                               width: bounds.width, size: size) else { return }
        #endif
        if titleChip.frame != frame { titleChip.frame = frame }
        if titleChip.isHidden { titleChip.isHidden = false }
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
        titleChip.isHidden = true
        return true
    }
}
