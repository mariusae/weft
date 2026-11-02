import Foundation
import Testing
import ReflectCore
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

    @Test func aCardDraggedGoesBeforeOrAfterWhereItIsDropped() {
        let one = river(["Alpha", "Beta", "Gamma"])
        one.save(as: "Order")
        one.move("Gamma", to: "Alpha", after: false)
        #expect(one.cards == ["Gamma", "Alpha", "Beta"])
        one.move("Gamma", to: "Beta", after: true)
        #expect(one.cards == ["Alpha", "Beta", "Gamma"])
        one.move("Alpha", to: "Alpha", after: true)
        #expect(one.cards == ["Alpha", "Beta", "Gamma"])
        #expect(one.isSelected("Gamma"))
        // The saved river keeps the order; a card from another river is opened here.
        #expect(file("Order") == "- [[Alpha]]\n- [[Beta]]\n- [[Gamma]]\n")
        write("Delta", "About Delta.")
        one.move("Delta", to: "Beta", after: false)
        #expect(one.cards == ["Alpha", "Delta", "Beta", "Gamma"])
    }

    @Test func backAndForwardGoWhereTheRiverWas() {
        let one = river(["Alpha", "Beta"])
        one.select("Alpha")
        one.open("Gamma", from: "Alpha")
        one.open("Beta")
        #expect(one.places == ["Gamma", "Alpha"])
        one.goBack()
        #expect(one.isSelected("Gamma"))
        #expect(one.canGoForward)
        one.goForward()
        #expect(one.isSelected("Beta"))
        // A place closed since is opened again to go back to it.
        one.close("Alpha")
        one.goBack(to: "Alpha")
        #expect(one.cards.contains("Alpha"))
        #expect(one.isSelected("Alpha"))
        #expect(!one.canGoBack)
    }

    @Test func aDayCardOpensItsNeighboursAfterIt() {
        let one = river(["Alpha"])
        let day = Day.today.description
        one.open(day, from: "Alpha")
        one.stepDay(-1)
        #expect(one.cards == ["Alpha", day, Day.today.adding(-1).description])
        #expect(store.quickOpen("next week").contains { $0.title == Day.today.adding(7).description })
    }

    @Test func rowsMovedToADayGoAtItsTopAndComeBackWithUndo() {
        let day = Day.today.adding(3)
        write(day.description, "- already there\n")
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        store.add([Row(kind: .bullet, text: "moved", task: .open)], toDay: day, undo: undo)
        undo.endUndoGrouping()
        let text = store.tiddler(day.description)?.text ?? ""
        #expect(text.hasPrefix("- [ ] moved"))
        #expect(text.contains("already there"))
        undo.undo()
        #expect(store.tiddler(day.description)?.text == "- already there\n")
    }

    @Test func closingAndDeletingAreUndone() {
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        let one = river(["Alpha", "Beta", "Gamma"])
        undo.beginUndoGrouping()
        one.close("Beta")
        undo.endUndoGrouping()
        #expect(one.cards == ["Alpha", "Gamma"])
        #expect(store.undoOffer?.hasPrefix("Close") == true)
        undo.undo()
        #expect(one.cards == ["Alpha", "Beta", "Gamma"])
        undo.beginUndoGrouping()
        store.delete("Gamma")
        undo.endUndoGrouping()
        #expect(store.tiddler("Gamma") == nil)
        #expect(!one.cards.contains("Gamma"))
        undo.undo()
        #expect(store.tiddler("Gamma")?.text == "About Gamma.")
        #expect(one.cards == ["Alpha", "Beta", "Gamma"])
    }

    @Test func theInboxPinsAndTasksArePrisms() {
        store.setInbox("Alpha", true)
        store.setPinned("Beta", true)
        write("Chores", "+ [ ] sweep\n+ [x] mop\n")
        #expect(store.inbox() == ["Alpha"])
        #expect(store.pinned() == ["Beta"])
        let open = store.taskGroups().flatMap(\.tasks)
        #expect(open.map(\.text) == ["sweep"])
        store.setTask(open[0], done: true)
        #expect(store.tiddler("Chores")?.text == "+ [x] sweep\n+ [x] mop\n")
        #expect(store.taskGroups().isEmpty)
        store.setInbox("Alpha", false)
        #expect(store.inbox().isEmpty)
    }

    @Test func typingLeavesMostQueriesAlone() {
        let graph = store.graphVersion, text = store.textVersion
        write("Alpha", "About Alpha, and more.")
        #expect(store.graphVersion == graph)
        #expect(store.textVersion > text)
        write("Alpha", "About Alpha, and [[Beta]].")
        #expect(store.graphVersion > graph)
    }

    @Test func pagesAreRelatedBothWaysInFrontmatter() throws {
        store.relate("Alpha", to: "beta")
        #expect(store.related(of: "Alpha").map(\.title) == ["Beta"])
        #expect(store.related(of: "Beta").map(\.title) == ["Alpha"])
        #expect(store.related(of: "Beta").first?.isOwn == false)
        let file = try String(contentsOf: root.appendingPathComponent("notes/alpha.md"), encoding: .utf8)
        #expect(file.contains("related: [Beta]"))
        // Already related, the other way: not written twice.
        store.relate("Beta", to: "Alpha")
        #expect(store.related(of: "Beta").count == 1)
        // Unrelated from the side that doesn't hold it.
        store.unrelate("Beta", from: "Alpha")
        #expect(store.related(of: "Alpha").isEmpty)
        #expect(try String(contentsOf: root.appendingPathComponent("notes/alpha.md"), encoding: .utf8).contains("related") == false)
    }

    @Test func foldsAreKeptWithTheRiver() {
        let one = river(["Alpha", "Beta", "Gamma"])
        one.toggleFold("Beta")
        #expect(one.state.folded == ["Beta"])
        let two = river()
        two.restore(one.state)
        #expect(two.isFolded("Beta") && !two.isFolded("Alpha"))
        two.foldAll()
        #expect(two.allFolded)
        two.unfoldAll()
        #expect(two.state.folded == nil)
        write("Delta", "# Delta\n\nFirst words, **bold**.\n- two\n- three\n")
        #expect(store.summary(of: "Delta").first == "First words, bold.")
        #expect(store.summary(of: "Delta").more == 2)
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
