import Foundation
import Testing
import ReflectCore
@testable import WeftCore
@testable import WeftUI

/// A tiddler jotted down untitled: shown as it begins, titled later — by
/// its first line or by a title typed — and untitled again.
@MainActor @Suite(.serialized) struct UntitledTests {
    let root: URL
    let store = WikiStore()

    init() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("weft-untitled-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
        store.open(graph: root)
        while store.loadedRoot == nil { try await Task.sleep(for: .milliseconds(10)) }
    }

    private func river() -> River {
        let river = River(store: store)
        store.adopt(river)
        river.restore(River.State(graph: root.path, cards: []))
        return river
    }

    private func file(_ path: String) -> String? {
        try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(400)) }

    /// Folded, a card is called what it is called open: a title being
    /// given it, not yet written, before what it begins with — a link, say.
    @Test func foldedCalledAsOpen() async throws {
        let river = river()
        river.newTiddler()
        let name = try #require(river.cards.first)
        store.change(name) { $0.text = "- https://www.stat.cmu.edu/~cshalizi/TALR/TALR.pdf\n" }
        #expect(store.peek(of: name).title.contains("cmu.edu"))
        store.change(name) { $0.title = "Truth about Linear Regression" }
        #expect(store.peek(of: name).title == "Truth about Linear Regression")
        // A day's draft: its name as a day is shown, not its key.
        store.change("2026-11-04") { $0.text = "- a line\n" }
        #expect(store.peek(of: "2026-11-04").title == store.shownTitle("2026-11-04"))
    }

    @Test func jottedTitledAndUntitledAgain() async throws {
        let river = river()
        river.newTiddler()
        let name = try #require(river.cards.first)
        #expect(Untitled.isName(name))
        #expect(store.shownTitle(name) == "Untitled")
        store.change(name) { $0.text = "Groceries for the weekend\n\n- milk\n" }
        store.finishEditing(name)
        // No title written, nor a heading: its file names it.
        let written = try #require(file("notes/\(name).md"))
        #expect(written.hasSuffix("---\nGroceries for the weekend\n\n- milk\n"))
        #expect(!written.contains("title:"))
        #expect(store.shownTitle(name) == "Groceries for the weekend")
        #expect(store.target(name).shown == "Groceries for the weekend")
        #expect(store.quickOpen("weekend").contains { $0.title == name })
        #expect(store.linkSuggestions("grocer").contains { $0.title == name && $0.shown == "Groceries for the weekend" })

        // Linked to, by its name.
        store.change("Plans") { $0.text = "Do [[\(name)]].\n" }
        store.finishEditing("Plans")

        // Titled by its first line.
        river.titleByFirstLine(name)
        // Written once the caret is settled out of it.
        try await settle()
        #expect(river.cards.first == "Groceries for the weekend")
        #expect(file("notes/\(name).md") == nil)
        #expect(file("notes/groceries-for-the-weekend.md")?.hasSuffix("---\n# Groceries for the weekend\n\n- milk\n") == true)
        // Its id and times kept through it all.
        #expect(file("notes/groceries-for-the-weekend.md")?.contains("\nid: ") == true)
        #expect(file("notes/groceries-for-the-weekend.md")?.contains("\ncreated: ") == true)
        #expect(store.tiddler("Plans")?.text == "Do [[Groceries for the weekend]].\n")

        // Its title taken away: untitled again, under a new name, followed.
        store.change("Groceries for the weekend") { $0.title = "" }
        store.finishEditing("Groceries for the weekend")
        let again = try #require(river.cards.first)
        #expect(Untitled.isName(again))
        #expect(file("notes/groceries-for-the-weekend.md") == nil)
        #expect(file("notes/\(again).md")?.hasSuffix("---\n- milk\n") == true)
        #expect(file("notes/\(again).md")?.contains("title:") == false)
        #expect(store.shownTitle(again) == "milk")
        #expect(store.tiddler("Plans")?.text == "Do [[\(again)]].\n")

        // A title typed, the same as another's file would be: its own file.
        store.change(again) { $0.title = "Plans" }
        store.finishEditing(again)
        #expect(store.error?.contains("already a tiddler called “Plans”") == true)
        #expect(file("notes/\(again).md")?.hasSuffix("---\n- milk\n") == true)
    }

    @Test func aTitleGivenIsTakenWhenAllIsSaved() throws {
        let river = river()
        river.newTiddler()
        let name = try #require(river.cards.first)
        store.change(name) { $0.text = "Call the plumber\nThursday works\n" }
        // Its first line made its title, as Use First Line does, the caret still in it.
        store.change(name) { $0 = WikiStore.titledByFirstLine($0)! }
        // The app goes to the background: the title is taken, not only the words.
        store.saveEditing()
        #expect(river.cards.first == "Call the plumber")
        #expect(store.tiddler("Call the plumber")?.text == "Thursday works\n")
        #expect(file("notes/\(name).md") == nil)
    }

    @Test func leftEmptyItGoes() throws {
        let river = river()
        river.newTiddler()
        let name = try #require(river.cards.first)
        store.finishEditing(name)
        #expect(!store.exists(name))
        #expect(river.cards.isEmpty)
    }
}
