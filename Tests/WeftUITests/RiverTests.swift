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

    @Test func savedRiversPutInOrderByHand() {
        for name in ["Apple", "Banana", "Cherry", "Date"] { _ = store.addSavedRiver(name, SavedRiver(cards: ["Alpha"])) }
        #expect(store.savedRivers() == ["Apple", "Banana", "Cherry", "Date"])
        // None placed yet: all numbered as they now stand.
        store.moveSavedRiver("Date", before: "Banana")
        #expect(store.savedRivers() == ["Apple", "Date", "Banana", "Cherry"])
        #expect(file("Cherry")?.contains("place: 4") == true)
        // Placed: only the one moved written, between its neighbours.
        let banana = file("Banana")
        store.moveSavedRiver("Apple", before: "Cherry")
        #expect(store.savedRivers() == ["Date", "Banana", "Apple", "Cherry"])
        #expect(file("Apple")?.contains("place: 3.5") == true)
        #expect(file("Banana") == banana)
        // To the end; and an open river's writes keep its place.
        store.moveSavedRiver("Date", before: nil)
        #expect(store.savedRivers() == ["Banana", "Apple", "Cherry", "Date"])
        store.keepSavedRiver("Date", SavedRiver(cards: ["Beta"]))
        #expect(store.savedRivers().last == "Date")
        // One new, after those placed.
        _ = store.addSavedRiver("Aardvark", SavedRiver(cards: []))
        #expect(store.savedRivers().last == "Aardvark")
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

    @Test func rowFoldsAreTheRiversOwn() {
        let one = river(["Alpha"]), two = river(["Alpha"])
        let marks = [OutlineFolds.Mark(index: 0, text: "About Alpha.")]
        one.setRowFolds(marks, of: "Alpha")
        #expect(one.rowFolds(of: "Alpha") == marks)
        // Another river keeps its own: unfolded, once told so.
        two.setRowFolds([], of: "Alpha")
        #expect(two.rowFolds(of: "Alpha").isEmpty && one.rowFolds(of: "Alpha") == marks)
        // Closed and opened again, as it was; kept with the river.
        one.close("Alpha")
        one.open("Alpha")
        #expect(one.rowFolds(of: "Alpha") == marks)
        let three = river()
        three.restore(one.state)
        #expect(three.rowFolds(of: "Alpha") == marks)
        // A river new to the page opens it as it was folded last here.
        #expect(river(["Alpha"]).rowFolds(of: "Alpha").isEmpty)
    }

    @Test func aSavedRiversFileKeepsWhatIsFolded() {
        let text = "---\nfolded:\n  - \"Beta: two\"\n---\n- [[Alpha]]\n  - 4: Projects \\\\ more\\nnext\n  - 9: - [[Link]]\n- [[Beta: two]]\n"
        let saved = SavedRiver(text: text)
        #expect(saved.cards == ["Alpha", "Beta: two"])
        #expect(saved.folded == ["Beta: two"])
        #expect(saved.rows["Alpha"] == [OutlineFolds.Mark(index: 4, text: "Projects \\ more\nnext"), OutlineFolds.Mark(index: 9, text: "- [[Link]]")])
        #expect(saved.text == text)
        #expect(SavedRiver(text: "- [[Alpha]]\n- [[Beta]]\n") == SavedRiver(cards: ["Alpha", "Beta"]))
        let renamed = saved.renaming("Alpha", to: "Aleph")
        #expect(renamed.cards.first == "Aleph" && renamed.rows["Aleph"]?.count == 2)
        #expect(saved.removing("Beta: two").text == "- [[Alpha]]\n  - 4: Projects \\\\ more\\nnext\n  - 9: - [[Link]]\n")
    }

    @Test func foldsSyncWithASavedRiver() throws {
        let one = river(["Alpha", "Beta"])
        one.save(as: "Work")
        one.toggleFold("Beta")
        one.setRowFolds([OutlineFolds.Mark(index: 0, text: "About Alpha.")], of: "Alpha")
        #expect(file("Work") == "---\nfolded:\n  - Beta\n---\n- [[Alpha]]\n  - 0: About Alpha.\n- [[Beta]]\n")
        // Another device opens it folded so.
        let state = one.state
        store.release(one)
        let again = river()
        again.restore(River.State(graph: state.graph, name: "Work", cards: []))
        #expect(again.isFolded("Beta") && again.rowFolds(of: "Alpha").count == 1)
        // A sync unfolds it there: here too.
        try "- [[Alpha]]\n- [[Beta]]\n".write(to: root.appendingPathComponent("rivers/Work.md"), atomically: true, encoding: .utf8)
        store.pulled(["rivers/Work.md"])
        #expect(!again.isFolded("Beta") && again.rowFolds(of: "Alpha").isEmpty)
        // Renaming a page keeps what is folded of it in a river not open.
        again.setRowFolds([OutlineFolds.Mark(index: 0, text: "About Alpha.")], of: "Alpha")
        store.release(again)
        store.change("Alpha") { $0.title = "Aleph" }
        store.finishEditing("Alpha")
        #expect(store.savedRiver("Work")?.rows["Aleph"]?.count == 1)
    }

    @Test func aLinkToASavedRiverBringsItBackAndFollowsItsRenames() throws {
        #expect(RiverLink.name("rivers/Work") == "Work" && RiverLink.name("Rivers/Work.md") == "Work")
        #expect(RiverLink.name("rivers/") == nil && RiverLink.name("notes/Work") == nil && RiverLink.name("rivers/a/b") == nil)
        let one = river(["Alpha", "Beta"])
        one.save(as: "Work")
        write("Plans", "See [[rivers/Work]] and [[rivers/Work|the work]].")
        #expect(store.linkExists("rivers/Work") && store.linkExists("rivers/WORK") && !store.linkExists("rivers/Play"))
        #expect(store.riverNote("rivers/Work")?.contains("2 cards") == true)
        // Followed from a river showing other cards: the one showing it, to the front.
        var presented = false
        one.present = { presented = true }
        let other = river(["Gamma"])
        other.open("rivers/work")
        #expect(presented && other.cards == ["Gamma"])
        // Not open anywhere: beside this one.
        store.release(one)
        var opened: River.State?
        other.openNew = { opened = $0 }
        other.open("rivers/Work")
        #expect(opened?.name == "Work")
        // One no river has: said so, nothing opened.
        other.open("rivers/Play")
        #expect(store.error != nil && other.cards == ["Gamma"])
        store.error = nil
        // Renamed, its links follow.
        store.renameSavedRiver("Work", to: "Project")
        #expect(store.tiddler("Plans")?.text.contains("[[rivers/Project]]") == true)
        #expect(store.tiddler("Plans")?.text.contains("[[rivers/Project|the work]]") == true)
    }

    @Test func riversAreOfferedToLinkAndDraggedAsLinks() {
        let one = river(["Alpha", "Beta"])
        #expect(one.dropped == "- [[Alpha]]\n- [[Beta]]")
        one.save(as: "Weft work")
        #expect(one.dropped == "[[rivers/Weft work]]")
        let offered = store.linkSuggestions("weft")
        #expect(offered.contains(LinkTarget(title: "rivers/Weft work", shown: "Weft work", kind: .river)))
        #expect(store.target("rivers/Weft work").kind == .river && store.shownTitle("rivers/Weft work") == "Weft work")
    }

    @Test func riversAreFoundAndSayWhatTheyHoldAndWhatLinksThem() {
        let one = river(["Alpha", "Beta"])
        one.save(as: "Weft work")
        let two = river(["Beta"])
        two.save(as: "Taxes")
        #expect(store.rivers(holding: "Beta") == ["Taxes", "Weft work"])
        #expect(store.rivers(holding: "Gamma").isEmpty)
        // As the rivers change, so does what they hold.
        one.open("Gamma")
        #expect(store.rivers(holding: "Gamma") == ["Weft work"])
        #expect(store.quickOpen("weft").contains { $0.kind == .river && $0.shown == "Weft work" })
        write("Plans", "See [[rivers/Taxes]].")
        #expect(store.linking(toRiver: "Taxes") == ["Plans"])
    }

    @Test func aPageHasAHomeRiverInItsFrontmatter() throws {
        #expect(store.homeRiver(of: "Alpha") == nil)
        store.setHomeRiver("Weft work", of: "Alpha")
        #expect(store.homeRiver(of: "Alpha") == "Weft work")
        let file = try String(contentsOf: root.appendingPathComponent(store.pages!.entries["Alpha"]!.path), encoding: .utf8)
        #expect(file.contains("river: Weft work"))
        // Written as a link, read the same.
        store.change("Beta") { $0[field: RiverLink.homeKey] = .text("[[rivers/Taxes]]") }
        store.finishEditing("Beta")
        #expect(store.homeRiver(of: "Beta") == "Taxes")
        store.setHomeRiver(nil, of: "Alpha")
        #expect(store.homeRiver(of: "Alpha") == nil)
    }

    @Test func quickOpenListsTodayOnce() {
        write(Day.today.description, "- written today\n")
        let titles = store.quickOpen("").map(\.title)
        #expect(titles.first == Day.today.description)
        #expect(titles.filter { $0 == Day.today.description }.count == 1)
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
        #expect(store.savedCards("Work copy") == ["Alpha"])
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
        #expect(store.savedCards("Saved") == ["Aleph", "Gamma"])
        store.delete("Beta")
        #expect(one.cards == ["Aleph"])
        store.delete("Gamma")
        #expect(store.savedCards("Saved") == ["Aleph"])
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

/// Tabs in the Mac's title bar: alike while they show their names, else bunched.
@Suite struct TabLayoutTests {
    @Test func tabsShareTheRoomThenBunch() {
        let roomy = TabLayout.widths(count: 3, current: 2, pointed: nil, in: 600)
        #expect(Set(roomy.map { Int($0) }).count == 1)
        let tight = TabLayout.widths(count: 8, current: 7, pointed: nil, in: 500)
        #expect(tight[0] == TabLayout.bunched)
        #expect(tight[7] >= TabLayout.shownMin)
        #expect(tight.reduce(0, +) + TabLayout.spacing * 7 <= 500.5)
        let pointed = TabLayout.widths(count: 8, current: 7, pointed: 2, in: 500)
        #expect(pointed[2] == TabLayout.pointed)
        let crowded = TabLayout.widths(count: 12, current: 11, pointed: nil, in: 420)
        #expect(crowded[0] < TabLayout.bunched && crowded[0] >= TabLayout.tightest)
    }
}
