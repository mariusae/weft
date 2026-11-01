import Foundation
import Testing
@testable import WeftCore
@testable import WeftUI

/// Rivers over a graph made for each test: what one river does to the
/// others, and saved rivers' files.
@MainActor @Suite(.serialized) struct RiverTests {
    let root: URL
    let store = WikiStore()

    init() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("weft-rivers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
        store.open(graph: root)
        while store.loadedRoot == nil { try await Task.sleep(for: .milliseconds(10)) }
        for title in ["Alpha", "Beta", "Gamma"] { write(title, "About \(title).") }
    }

    private func write(_ title: String, _ text: String) {
        store.change(title) { $0.text = text }
        store.finishEditing(title)
    }

    private func river(_ cards: [String] = []) -> River {
        let river = River(store: store)
        store.adopt(river)
        river.restore(River.State(graph: root.path, cards: cards))
        return river
    }

    private func file(_ name: String) -> String? {
        try? String(contentsOf: root.appendingPathComponent("rivers/\(name).md"), encoding: .utf8)
    }

    @Test func aPageOpenInTwoRiversIsOneDraft() {
        let one = river(["Alpha"]), two = river(["Alpha"])
        store.change("Alpha") { $0.text = "Changed." }
        one.close("Alpha")
        // Still open in the other: the draft stays.
        #expect(store.draft("Alpha")?.text == "Changed.")
        two.close("Alpha")
        #expect(store.draft("Alpha") == nil)
        #expect(store.tiddler("Alpha")?.text == "Changed.")
    }

    @Test func aCardIsAnOutlineWhereItCanBeAndCommandReturnSwitches() {
        write("List", "- one\n- two\n")
        write("Prose", "A line\u{2028}broken within.")
        #expect(store.editorMode("List") == .outline)
        #expect(store.editorMode("Prose") == .text)
        let one = river(["List", "Prose"])
        one.select("List")
        one.toggleEditorMode()
        #expect(store.editorMode("List") == .text)
        one.toggleEditorMode()
        #expect(store.editorMode("List") == .outline)
        // What the outline would write differently stays text.
        one.select("Prose")
        one.toggleEditorMode()
        #expect(store.editorMode("Prose") == .text)
    }

    @Test func savingWritesTheRiverAndKeepsItAsItChanges() {
        let one = river(["Alpha", "Beta"])
        one.save(as: "Work")
        #expect(one.name == "Work")
        #expect(file("Work") == "- [[Alpha]]\n- [[Beta]]\n")
        one.open("Gamma")
        #expect(file("Work") == "- [[Gamma]]\n- [[Alpha]]\n- [[Beta]]\n")
        #expect(store.savedRivers() == ["Work"])
        // A name taken already is refused.
        let two = river(["Beta"])
        two.save(as: "work")
        #expect(two.name == nil)
        #expect(store.error != nil)
    }

    @Test func cloneRenameAndDelete() {
        let one = river(["Alpha"])
        one.save(as: "Work")
        store.cloneSavedRiver("Work", as: store.cloneName("Work"))
        #expect(store.savedRivers() == ["Work", "Work copy"])
        #expect(store.savedRiver("Work copy") == ["Alpha"])
        // The copy is not opened.
        #expect(store.river(named: "Work copy") == nil)
        store.renameSavedRiver("Work", to: "Project")
        #expect(one.name == "Project")
        #expect(file("Work") == nil && file("Project") == "- [[Alpha]]\n")
        store.deleteSavedRiver("Project")
        // The river stays open, its own again.
        #expect(one.name == nil && one.cards == ["Alpha"])
        #expect(store.savedRivers() == ["Work copy"])
    }

    @Test func recallingBringsBackOrPresents() {
        // The store holds rivers weakly: these are held here, as a window would.
        let shown = river(["Alpha", "Beta"])
        shown.save(as: "Work")
        var presented = false
        shown.present = { presented = true }
        let other = river(["Gamma"])
        other.recall("Work")
        #expect(presented)
        // Not open anywhere: an empty river shows it; one with cards opens it beside.
        store.release(shown)
        let empty = river()
        empty.recall("Work")
        #expect(empty.name == "Work" && empty.cards == ["Alpha", "Beta"])
        store.release(empty)
        var opened: River.State?
        other.openNew = { opened = $0 }
        other.recall("Work")
        #expect(opened?.name == "Work" && other.name == nil)
    }

    @Test func renamingAndDeletingAPageReachEveryRiver() {
        let one = river(["Alpha", "Beta"]), two = river(["Alpha"])
        let saved = river(["Alpha", "Gamma"])
        saved.save(as: "Saved")
        store.release(saved)
        store.change("Alpha") { $0.title = "Aleph" }
        store.finishEditing("Alpha")
        #expect(one.cards == ["Aleph", "Beta"] && two.cards == ["Aleph"])
        #expect(store.savedRiver("Saved") == ["Aleph", "Gamma"])
        store.delete("Beta")
        #expect(one.cards == ["Aleph"])
        store.delete("Gamma")
        #expect(store.savedRiver("Saved") == ["Aleph"])
    }

    @Test func aRiverKeptIsPutBack() {
        let one = river(["Beta", "Alpha"])
        one.save(as: "Work")
        let state = one.state
        store.release(one)
        // Changed on another device meanwhile: the file wins.
        try? "- [[Gamma]]\n".write(to: root.appendingPathComponent("rivers/Work.md"), atomically: true, encoding: .utf8)
        let again = river()
        again.restore(state)
        #expect(again.name == "Work" && again.cards == ["Gamma"])
    }
}
