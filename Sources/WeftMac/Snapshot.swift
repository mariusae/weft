import AppKit
import WeftCore
import WeftUI

/// A picture of the window, for seeing the app without a person at it.
///
///     WEFT_SNAPSHOT=out.png WEFT_OPEN="HelloThere|Filters" WEFT_EDIT=Filters \
///       build/Weft.app/Contents/MacOS/WeftMac -GraphPath <graph>
///
/// opens the cards named (the first at the top), edits one, shows Quick Open
/// with `WEFT_QUICK_OPEN=1`, searches for
/// `WEFT_SEARCH`, draws the window into the file, and quits.
@MainActor
enum Snapshot {
    static var isAsked: Bool { ProcessInfo.processInfo.environment["WEFT_SNAPSHOT"] != nil }

    /// Whether the GitHub account is touched: always, but in a snapshot only
    /// of onboarding's GitHub page — it reads the keychain, which may ask.
    static var usesAccount: Bool {
        !isAsked || ProcessInfo.processInfo.environment["WEFT_ONBOARDING_STEP"] == "github"
    }

    static func takeIfAsked(store: WikiStore) {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["WEFT_SNAPSHOT"] else { return }
        let titles = environment["WEFT_OPEN"]?.split(separator: "|").map(String.init) ?? []
        // Just the cards named, whatever was open last.
        if !titles.isEmpty { store.closeAll() }
        for title in titles.reversed() { store.open(title) }
        if let edit = environment["WEFT_EDIT"] { store.edit(edit) }
        if environment["WEFT_QUICK_OPEN"] != nil { store.quickOpenShown = true }
        if let search = environment["WEFT_SEARCH"] { store.search = search }
        // Once the cards are laid out, the one named in WEFT_SCROLL (or the
        // first) is brought into view, as a click on a link would.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let title = environment["WEFT_SCROLL"] ?? titles.first { store.bringIntoView(title) }
            // `WEFT_TYPE`: typed at the end of the card being edited.
            if let typed = environment["WEFT_TYPE"], let view = NSApp.windows.lazy.compactMap({ $0.firstResponder as? NSTextView }).first {
                view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
                view.insertText(typed, replacementRange: view.selectedRange())
            }
        }
        let delay = Double(environment["WEFT_DELAY"] ?? "") ?? 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }), let view = window.contentView?.superview ?? window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                FileHandle.standardError.write(Data("No window to draw\n".utf8))
                exit(1)
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
            // Panels over it — the list of titles for a link — beside it.
            for (index, panel) in NSApp.windows.filter({ $0 !== window && $0.isVisible && $0 is NSPanel }).enumerated() {
                guard let content = panel.contentView, let picture = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { continue }
                content.cacheDisplay(in: content.bounds, to: picture)
                let path = (output as NSString).deletingPathExtension + "-panel\(index + 1).png"
                try? picture.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }
    }
}
