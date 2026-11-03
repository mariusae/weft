import AppKit
import WeftCore
import WeftUI

/// A picture of the window, for seeing the app without a person at it.
///
///     WEFT_SNAPSHOT=out.png WEFT_OPEN="HelloThere|Filters" WEFT_EDIT=Filters \
///       build/Weft.app/Contents/MacOS/WeftMac -GraphPath <graph>
///
/// opens the cards named (the first at the top), edits one, shows Quick Open
/// with `WEFT_QUICK_OPEN=1`, searches for `WEFT_SEARCH`, opens a tab for each
/// of `WEFT_TABS="A|B;C"`, saves the river as `WEFT_SAVE_RIVER`, shows the
/// saved rivers with `WEFT_RIVERS=1`, draws the window into the file, and quits.
@MainActor
enum Snapshot {
    static var isAsked: Bool { ProcessInfo.processInfo.environment["WEFT_SNAPSHOT"] != nil }

    /// Whether the GitHub account is touched: always, but in a snapshot only
    /// of onboarding's GitHub page — it reads the keychain, which may ask.
    static var usesAccount: Bool {
        !isAsked || ProcessInfo.processInfo.environment["WEFT_ONBOARDING_STEP"] == "github"
    }

    private static var taken = false

    /// The window's rivers: its tabs.
    @MainActor static var rivers: RiverSet?

    static func takeIfAsked(store: WikiStore) {
        guard ProcessInfo.processInfo.environment["WEFT_SNAPSHOT"] != nil, !taken else { return }
        taken = true
        // `WEFT_MENUS=1`: the File menu's items, printed, for checking its keys.
        if ProcessInfo.processInfo.environment["WEFT_MENUS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                for item in NSApp.mainMenu?.items.first(where: { $0.title == "File" })?.submenu?.items ?? [] {
                    print("MENU", item.title, item.keyEquivalentModifierMask.rawValue, item.keyEquivalent)
                }
            }
        }
        // Once the window has put back its river.
        store.whenLoaded { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { take(store: store) } }
    }

    /// A key like `cmd-shift-k` or `cmd-ctrl-up`, pressed as the app
    /// takes a key with ⌘: the window's views first, then the menus.
    private static func press(_ key: String, in window: NSWindow) {
        var parts = key.split(separator: "-").map(String.init)
        let named = ["return": "\r", "up": String(UnicodeScalar(NSUpArrowFunctionKey)!), "down": String(UnicodeScalar(NSDownArrowFunctionKey)!),
                     "left": String(UnicodeScalar(NSLeftArrowFunctionKey)!), "right": String(UnicodeScalar(NSRightArrowFunctionKey)!)]
        let last = parts.removeLast()
        let character = named[last] ?? last
        var flags: NSEvent.ModifierFlags = []
        for part in parts {
            switch part {
            case "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "opt": flags.insert(.option)
            case "ctrl": flags.insert(.control)
            default: break
            }
        }
        if named[last] != nil, last != "return" { flags.insert([.numericPad, .function]) }
        let codes: [String: UInt16] = ["return": 36, "up": 126, "down": 125, "left": 123, "right": 124, "k": 40, "d": 2, "b": 11, "l": 37, "9": 25, "0": 29, "8": 28]
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil,
                                           characters: flags.contains(.shift) ? character.uppercased() : character,
                                           charactersIgnoringModifiers: flags.contains(.shift) ? character.uppercased() : character,
                                           isARepeat: false, keyCode: codes[last] ?? 0) else { return }
        if !window.performKeyEquivalent(with: event) { _ = NSApp.mainMenu?.performKeyEquivalent(with: event) }
    }

    private static func take(store: WikiStore) {
        guard let river = rivers?.current ?? store.rivers.first else { return }
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["WEFT_SNAPSHOT"] else { return }
        // `WEFT_WIDTH`: the window this wide, as a narrow window or a phone is.
        if let width = environment["WEFT_WIDTH"].flatMap(Double.init), let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(NSSize(width: width, height: window.contentLayoutRect.height))
        }
        let titles = environment["WEFT_OPEN"]?.split(separator: "|").map(String.init) ?? []
        // Just the cards named, whatever was open last.
        if !titles.isEmpty {
            // Just this river, whatever tabs were kept from before.
            if let rivers { rivers.closeOthers(river) }
            river.closeAll()
        }
        for title in titles.reversed() { river.open(title) }
        // `WEFT_OUTLINE`: a card edited as an outline.
        if let outline = environment["WEFT_OUTLINE"] { store.setEditorMode(.outline, for: outline) }
        if let text = environment["WEFT_TEXT"] { store.setEditorMode(.text, for: text) }
        for title in environment["WEFT_FOLD"]?.split(separator: "|") ?? [] { river.setFolded(String(title), true) }
        if let edit = environment["WEFT_EDIT"] { river.edit(edit) }
        if environment["WEFT_QUICK_OPEN"] != nil { river.quickOpenShown = true }
        // `WEFT_NEW`: a new tiddler, its title being typed.
        if environment["WEFT_NEW"] != nil { river.newTiddler() }
        if let search = environment["WEFT_SEARCH"] { river.search = search }
        if let name = environment["WEFT_SAVE_RIVER"] { river.save(as: name) }
        // `WEFT_RECALL`: a saved river brought back, folded as its file says;
        // `WEFT_PULL=<file>`, a moment later its file as a sync would bring it.
        if let name = environment["WEFT_RECALL"] {
            // Emptied without writing: were it that river already, closing
            // its cards would empty its file.
            river.restore(River.State(graph: store.root?.path ?? "", cards: []))
            river.restore(River.State(graph: store.root?.path ?? "", name: name, cards: []))
            if let pulled = environment["WEFT_PULL"], let root = store.root {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    try? FileManager.default.removeItem(at: root.appendingPathComponent("rivers/\(name).md"))
                    try? FileManager.default.copyItem(at: URL(fileURLWithPath: pulled), to: root.appendingPathComponent("rivers/\(name).md"))
                    store.pulled(["rivers/\(name).md"])
                }
            }
        }
        // `WEFT_ADDRESS=weft://…`: the address opened, as a click on it
        // elsewhere would — sent to this process alone, not any Weft.
        if let address = environment["WEFT_ADDRESS"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let event = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
                                                   targetDescriptor: NSAppleEventDescriptor(processIdentifier: getpid()),
                                                   returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
                event.setParam(NSAppleEventDescriptor(string: address), forKeyword: keyDirectObject)
                _ = try? event.sendEvent(options: [.noReply], timeout: 5)
            }
        }
        for tab in environment["WEFT_TABS"]?.split(separator: ";") ?? [] {
            rivers?.add(River.State(graph: store.root?.path ?? "", cards: tab.split(separator: "|").map(String.init)))
        }
        // `WEFT_TIMING=<n>`: the first two tabs shown in turn n times, each
        // switch's time printed — laid out and drawn — as a click would.
        if let rounds = environment["WEFT_TIMING"].flatMap(Int.init), let rivers, rivers.rivers.count > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
                for round in 0..<rounds {
                    let next = rivers.rivers[(round + 1) % 2]
                    let start = CACurrentMediaTime()
                    rivers.select(next)
                    window.contentView?.layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                    print("SWITCH", round, next.title, Int((CACurrentMediaTime() - start) * 1000), "ms")
                }
            }
        }
        if environment["WEFT_RIVERS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { river.riversShown = true }
        }
        // Once the cards are laid out, the one named in WEFT_SCROLL (or the
        // first) is brought into view, as a click on a link would.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let title = environment["WEFT_SCROLL"] ?? titles.first { river.bringIntoView(title) }
            // `WEFT_TYPE`: typed at the end of the card being edited.
            // A moment later: the caret goes in once the card is drawn.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if let typed = environment["WEFT_TYPE"], let view = NSApp.windows.lazy.compactMap({ $0.firstResponder as? NSTextView }).first {
                    view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
                    view.insertText(typed, replacementRange: view.selectedRange())
                }
                // `WEFT_CLICK=x,y`: a click there, in points from the window's
                // top left, as the pointer would make it.
                if let click = environment["WEFT_CLICK"]?.split(separator: ",").compactMap({ Double($0) }), click.count == 2,
                   let window = NSApp.windows.first(where: { $0.isVisible }) {
                    let point = NSPoint(x: click[0], y: window.frame.height - click[1])
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                            window.sendEvent(event)
                        }
                    }
                }
                // `WEFT_KEY=cmd-shift-k`: the key pressed in the card being
                // written in, as the app would take it — the window not being
                // key in a snapshot, given to it and then the menus straight.
                if let key = environment["WEFT_KEY"], let window = NSApp.windows.first(where: { $0.firstResponder is NSTextView }) {
                    press(key, in: window)
                }
                // `WEFT_SWITCH`: the card being written in switched to text, or outline.
                if environment["WEFT_SWITCH"] != nil { river.toggleEditorMode() }
                // `WEFT_MARKED`: words being dictated, not yet taken, at the end.
                if let marked = environment["WEFT_MARKED"], let view = NSApp.windows.lazy.compactMap({ $0.firstResponder as? NSTextView }).first {
                    view.setSelectedRange(NSRange(location: (view.string as NSString).length - 1, length: 0))
                    view.setMarkedText(marked, selectedRange: NSRange(location: (marked as NSString).length, length: 0), replacementRange: view.selectedRange())
                    // `WEFT_COMMIT`: then taken, as dictation takes its words when done.
                    if environment["WEFT_COMMIT"] != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { view.insertText(marked, replacementRange: view.markedRange()) }
                    }
                }
            }
        }
        let delay = Double(environment["WEFT_DELAY"] ?? "") ?? 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }), let view = window.contentView?.superview ?? window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                FileHandle.standardError.write(Data("No window to draw\n".utf8))
                exit(1)
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
            // Panels over it — the list of titles for a link — beside it.
            for (index, panel) in NSApp.windows.filter({ $0 !== window && $0.isVisible && ($0 is NSPanel || $0.className.contains("Popover")) }).enumerated() {
                guard let content = panel.contentView, let picture = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { continue }
                content.cacheDisplay(in: content.bounds, to: picture)
                let path = (output as NSString).deletingPathExtension + "-panel\(index + 1).png"
                try? picture.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }
    }
}
