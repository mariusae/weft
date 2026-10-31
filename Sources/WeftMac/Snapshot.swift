import AppKit
import WeftCore
import WeftUI

/// A picture of the window, for seeing the app without a person at it.
///
///     WEFT_SNAPSHOT=out.png WEFT_OPEN="HelloThere|Filters" WEFT_EDIT=Filters \
///       build/Weft.app/Contents/MacOS/WeftMac -GraphPath <graph>
///
/// opens the cards named (the first at the top), edits one, searches for
/// `WEFT_SEARCH`, draws the window into the file, and quits.
@MainActor
enum Snapshot {
    static func takeIfAsked(store: WikiStore) {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["WEFT_SNAPSHOT"] else { return }
        let titles = environment["WEFT_OPEN"]?.split(separator: "|").map(String.init) ?? []
        for title in titles.reversed() { store.open(title) }
        if let edit = environment["WEFT_EDIT"] { store.edit(edit) }
        if let search = environment["WEFT_SEARCH"] { store.search = search }
        // Once the cards are laid out, the one named in WEFT_SCROLL (or the
        // first) is brought into view, as a click on a link would.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let title = environment["WEFT_SCROLL"] ?? titles.first { store.bringIntoView(title) }
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
            exit(0)
        }
    }
}
