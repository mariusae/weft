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
/// of `WEFT_TABS="A|B;C;@Saved"`, saves the river as `WEFT_SAVE_RIVER`, shows the
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
        store.whenLoaded {
            if Bench.isAsked { Bench.loaded() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { take(store: store) }
        }
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
        let codes: [String: UInt16] = ["return": 36, "up": 126, "down": 125, "left": 123, "right": 124, "k": 40, "o": 31, "d": 2, "b": 11, "l": 37, "9": 25, "0": 29, "8": 28]
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
        // `WEFT_SHOW_SEARCH=words`: every page searched for them, as a river.
        if let typed = environment["WEFT_SHOW_SEARCH"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { river.showSearch(typed) }
        }
        // `WEFT_EMPTY`: one river, empty — its start page showing, as a new tab's.
        if environment["WEFT_EMPTY"] != nil {
            if let rivers { rivers.closeOthers(river) }
            river.restore(River.State(graph: store.root?.path ?? "", cards: []))
        }
        // `WEFT_QUERY_RIVER=Name|query lines`: a query river of the
        // query (its lines with \n), shown here.
        if let asked = environment["WEFT_QUERY_RIVER"], let bar = asked.firstIndex(of: "|") {
            let name = String(asked[..<bar])
            let query = Query(text: String(asked[asked.index(after: bar)...]).replacingOccurrences(of: "\\n", with: "\n"))
            if store.savedRiverName(name) == nil {
                _ = store.addQueryRiver(name, query: query, icon: "clock", color: "orange")
            }
            if let rivers { rivers.closeOthers(river) }
            river.restore(River.State(graph: store.root?.path ?? "", name: name, cards: []))
        }
        // `WEFT_RIVER_ICON=1`: the river's icon being chosen.
        if environment["WEFT_RIVER_ICON"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { river.choosingIcon = true }
        }
        // `WEFT_QUERY_EDITOR=new|edit`: the query river's editor.
        if let ask = environment["WEFT_QUERY_EDITOR"].flatMap(QueryEditorAsk.init(rawValue:)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { river.queryEditor = ask }
        }
        // `WEFT_OUTLINE`: a card edited as an outline.
        if let outline = environment["WEFT_OUTLINE"] { store.setEditorMode(.outline, for: outline) }
        if let text = environment["WEFT_TEXT"] { store.setEditorMode(.text, for: text) }
        for title in environment["WEFT_FOLD"]?.split(separator: "|") ?? [] { river.setFolded(String(title), true) }
        if let edit = environment["WEFT_EDIT"] { river.edit(edit) }
        if environment["WEFT_QUICK_OPEN"] != nil { river.quickOpenShown = true }
        // `WEFT_HOMING=<title>`: that card's home river being chosen.
        if let homing = environment["WEFT_HOMING"] { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { river.homing = homing } }
        // `WEFT_INSPECT`: the selected card's inspector beside the river.
        if environment["WEFT_INSPECT"] != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if environment["WEFT_INSPECT"] == "read" { river.reading = river.cards.first } else if environment["WEFT_INSPECT"] == "related" { river.side = .related } else { river.inspecting = true } } }
        // `WEFT_REPLACE=Saved`: a saved river chosen from its start page, in its place.
        if let saved = environment["WEFT_REPLACE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { river.replace(withSaved: saved) }
        }
        // `WEFT_START`: its start page over it, as its tab clicked asks.
        if environment["WEFT_START"] != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { river.startShown = true } }
        // `WEFT_NEW`: a new tiddler, its title being typed.
        if environment["WEFT_NEW"] != nil { river.newTiddler() }
        // `WEFT_PASTEBOARD_TEXT=words` or `WEFT_PASTEBOARD_PICTURE=file`: a new
        // tiddler of a pasteboard of the snapshot's own holding them, and
        // a moment later, and again later, its title and what it says.
        let pastedText = environment["WEFT_PASTEBOARD_TEXT"], pastedPicture = environment["WEFT_PASTEBOARD_PICTURE"]
        if pastedText != nil || pastedPicture != nil {
            let board = NSPasteboard(name: .init("weft-snapshot"))
            board.clearContents()
            if let pastedText { board.setString(pastedText.replacingOccurrences(of: "\\n", with: "\n"), forType: .string) }
            if let pastedPicture, let data = try? Data(contentsOf: URL(fileURLWithPath: pastedPicture)) { board.setData(data, forType: .png) }
            PastedTiddler.pasteboardName = "weft-snapshot"
            river.newTiddlerFromPasteboard()
            let title = river.cards.first ?? ""
            for wait in [0.5, 6.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                    print("PASTED after \(wait)s: card", title.debugDescription, "titled", (store.draftHead(title)?.title ?? "none").debugDescription,
                          "says", (store.draft(title)?.text ?? "none").debugDescription)
                }
            }
        }
        // `WEFT_NEW_PASTE=words`: a new tiddler, Return in its title — on to
        // its body — the words put there, and a moment later what its draft
        // says, and what has the keys, printed.
        if let words = environment["WEFT_NEW_PASTE"] {
            river.newTiddler()
            let title = river.cards.first ?? ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                river.edit(title)
                let delay = Double(environment["WEFT_PASTE_DELAY"] ?? "") ?? 0.1
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    let view = NSApp.windows.lazy.compactMap { $0.firstResponder as? NSTextView }.first
                    print("PASTE into", view.map { String(describing: type(of: $0)) } ?? "nothing", view?.isFieldEditor == true ? "(a field)" : "")
                    view?.insertText(words, replacementRange: view?.selectedRange() ?? NSRange())
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        print("PASTE draft:", store.draft(title)?.text.debugDescription ?? "none",
                              "| editing:", store.isEditing(title))
                    }
                }
            }
        }
        if let search = environment["WEFT_SEARCH"] { river.search = search }
        // `WEFT_SIDEBAR`: the sidebar toggled — shown, when it was not.
        if environment["WEFT_SIDEBAR"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // The split view's own controller: the window, drawn unseen, has no keys to send it by.
                func split(in view: NSView) -> NSSplitView? {
                    if let found = view as? NSSplitView { return found }
                    return view.subviews.lazy.compactMap(split).first
                }
                // From the window's frame: the split view is not always under its content.
                if let window = NSApp.windows.first(where: { $0.isVisible }), let view = window.contentView?.superview ?? window.contentView,
                   let found = split(in: view),
                   let controller = found.delegate as? NSSplitViewController {
                    controller.toggleSidebar(nil)
                }
            }
        }
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
        // `@Name`: a saved river, recalled into a tab of its own.
        for tab in environment["WEFT_TABS"]?.split(separator: ";") ?? [] {
            if tab.hasPrefix("@") {
                rivers?.add(River.State(graph: store.root?.path ?? "", name: String(tab.dropFirst()), cards: []))
            } else {
                rivers?.add(River.State(graph: store.root?.path ?? "", cards: tab.split(separator: "|").map(String.init)))
            }
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
                // `WEFT_KEYS=down,down,space` (or `cmd-delete`): keys pressed, a moment apart, as
                // the keyboard would — through what watches for them.
                if let keys = environment["WEFT_KEYS"]?.split(separator: ","), let window = NSApp.windows.first(where: { $0.isVisible }) {
                    let codes: [Substring: (UInt16, String, NSEvent.ModifierFlags)] = [
                        "up": (126, "\u{F700}", []), "down": (125, "\u{F701}", []), "space": (49, " ", []),
                        "return": (36, "\r", []), "escape": (53, "\u{1B}", []), "cmd-delete": (51, "\u{7F}", .command)]
                    for (index, key) in keys.enumerated() {
                        guard let (code, characters, flags) = codes[key] else { continue }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 * Double(index)) {
                            for type in [NSEvent.EventType.keyDown, .keyUp] {
                                if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                                                windowNumber: window.windowNumber, context: nil, characters: characters,
                                                                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) {
                                    NSApp.postEvent(event, atStart: false)
                                }
                            }
                        }
                    }
                }
                // `WEFT_HOVER=x,y`: the pointer moved there, in points from the
                // window's top left.
                // Moved again a moment later: over what the first move showed.
                func move() {
                if let hover = environment["WEFT_HOVER"]?.split(separator: ",").compactMap({ Double($0) }), hover.count == 2,
                   let window = NSApp.windows.first(where: { $0.isVisible }) {
                    window.acceptsMouseMovedEvents = true
                    for step in 0...4 {
                        let point = NSPoint(x: hover[0] - Double(4 - step) * 3, y: window.frame.height - hover[1])
                        if let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
                            window.sendEvent(event)
                            // In the title bar the window server tells tracking
                            // areas of the pointer, not the window: told here.
                            func tell(_ view: NSView) {
                                let inView = view.convert(point, from: nil)
                                if view.visibleRect.contains(inView),
                                   view.trackingAreas.contains(where: { $0.owner === view && $0.options.contains(.mouseMoved) }) {
                                    view.mouseMoved(with: event)
                                }
                                view.subviews.forEach(tell)
                            }
                            if let frame = window.contentView?.superview { tell(frame) }
                        }
                    }
                }
                }
                move()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: move)
                // Once more, after a river brought back has settled.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: move)
                // `WEFT_SWIPE=x,y,dx`: two fingers swiped across the trackpad
                // there, `dx` points the way they went — a trackpad's
                // scrolling, begun, moved and ended, as the app is sent it.
                if let swipe = environment["WEFT_SWIPE"]?.split(separator: ",").compactMap({ Double($0) }), swipe.count == 3,
                   let window = NSApp.windows.first(where: { $0.isVisible }) {
                    let point = NSPoint(x: swipe[0], y: window.frame.height - swipe[1])
                    let screen = window.convertPoint(toScreen: point)
                    let flipped = CGPoint(x: screen.x, y: (NSScreen.screens.first?.frame.height ?? 0) - screen.y)
                    let steps = 8
                    for step in 0...(steps + 1) {
                        let phase: Int64 = step == 0 ? 1 : step == steps + 1 ? 4 : 2
                        // As a trackpad scrolls with natural scrolling off: the content
                        // against the fingers, which a made-up event can't say otherwise.
                        let delta = step == 0 || step == steps + 1 ? 0 : -swipe[2] / Double(steps)
                        guard let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0) else { continue }
                        scroll.location = flipped
                        scroll.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                        scroll.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
                        scroll.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: delta)
                        scroll.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: delta)
                        if let event = NSEvent(cgEvent: scroll) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6 + Double(step) * 0.016) { NSApp.sendEvent(event) }
                        }
                    }
                }
                // `WEFT_CLICK=x,y`: a click there, in points from the window's
                // top left, as the pointer would make it.
                if let click = environment["WEFT_CLICK"]?.split(separator: ",").compactMap({ Double($0) }), click.count == 2,
                   let window = NSApp.windows.first(where: { $0.isVisible }) {
                    let point = NSPoint(x: click[0], y: window.frame.height - click[1])
                    let events = [NSEvent.EventType.leftMouseDown, .leftMouseUp].compactMap {
                        NSEvent.mouseEvent(with: $0, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                    }
                    // The button's coming up waiting, for a view that follows the
                    // click itself; the click given to the view under it — the
                    // window not being key, it would only be made so.
                    if events.count == 2 {
                        NSApp.postEvent(events[1], atStart: false)
                        if let view = window.contentView?.superview?.hitTest(point), !view.acceptsFirstMouse(for: events[0]) {
                            view.mouseDown(with: events[0])
                        } else {
                            window.sendEvent(events[0])
                        }
                    }
                }
                // `WEFT_KEY=cmd-shift-k`: the key pressed in the card being
                // written in, as the app would take it — the window not being
                // key in a snapshot, given to it and then the menus straight.
                if let key = environment["WEFT_KEY"], let window = NSApp.windows.first(where: { $0.firstResponder is NSTextView }) {
                    press(key, in: window)
                }
                // `WEFT_TITLE`: Story ▸ Title Tiddler, as its menu sends it —
                // the window, in a snapshot, never key for the menu to know its river.
                if environment["WEFT_TITLE"] != nil, !NSApp.sendAction(Selector(("titlePage:")), to: nil, from: nil) { river.titleCard() }
                // `WEFT_NEWLINE`: Return pressed at the end of the card being written in.
                if environment["WEFT_NEWLINE"] != nil, let view = NSApp.windows.lazy.compactMap({ $0.firstResponder as? NSTextView }).first {
                    view.moveToEndOfDocument(nil)
                    view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
                }
                // `WEFT_NEW_TYPE=words`: ⌘N, the river scrolled away from where the
                // new card goes, and the words typed at once — as keys, before
                // the card can have the caret.
                if let words = environment["WEFT_NEW_TYPE"], let window = NSApp.windows.first(where: { $0.isVisible }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // `WEFT_NEW_TODO`: ⌘⇧N instead.
                        if environment["WEFT_NEW_TODO"] != nil { river.newTodo() } else { river.newTiddler() }
                        for (index, character) in words.enumerated() {
                            guard let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                             windowNumber: window.windowNumber, context: nil, characters: String(character),
                                                             charactersIgnoringModifiers: String(character), isARepeat: false, keyCode: 0) else { continue }
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.01) { NSApp.sendEvent(key) }
                        }
                    }
                }
                // `WEFT_NEW_LATER`: a new tiddler, once the caret is in a card or the river scrolled, as ⌘N would.
                if environment["WEFT_NEW_LATER"] != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { river.newTiddler() }
                }
                // `WEFT_QUICK_OPEN_LATER`: Quick Open asked for once the caret is in a card, as ⌘O would.
                if environment["WEFT_QUICK_OPEN_LATER"] != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { river.quickOpenShown = true }
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
        // `WEFT_BENCH`: timed, once all is settled, instead of drawn.
        if Bench.isAsked {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Bench.run(river: river, rivers: rivers) }
            return
        }
        let delay = Double(environment["WEFT_DELAY"] ?? "") ?? 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // A sheet over the window, when there is one: it is what shows.
            guard let front = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }), case let window = front.attachedSheet ?? front,
                  let view = window.contentView?.superview ?? window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                FileHandle.standardError.write(Data("No window to draw\n".utf8))
                exit(1)
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            // `WEFT_RESPONDER`: what has the keys, printed.
            if environment["WEFT_RESPONDER"] != nil {
                let responder = window.firstResponder
                if let field = responder as? NSTextView { print("RESPONDER selection", field.selectedRange(), "of", (field.string as NSString).length) }
                print("RESPONDER", responder.map { String(describing: type(of: $0)) } ?? "none",
                      ((responder as? NSTextView)?.delegate as? NSTextField).map { "field editor of \($0.placeholderString ?? "?")" } ?? "")
            }
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
