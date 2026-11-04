import Foundation
import Testing
import ReflectCore
@testable import WeftCore
@testable import WeftUI

/// Rivers of what a query finds: in its order, after the cards put at the
/// top by hand, with those put among them keeping their place, and those
/// taken out kept out.
@MainActor @Suite(.serialized) struct QueryRiverTests {
    let root: URL
    let store = WikiStore()

    init() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("weft-query-rivers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
        store.open(graph: root)
        while store.loadedRoot == nil { try await Task.sleep(for: .milliseconds(10)) }
        // Written one after another: the newest last.
        for title in ["Alpha", "Beta", "Gamma", "Delta"] {
            store.change(title) { $0.text = "About \(title)." }
            store.finishEditing(title)
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func river() -> River {
        let river = River(store: store)
        store.adopt(river)
        river.restore(River.State(graph: root.path, cards: []))
        river.save(as: "Recent")
        river.setQuery(Query(text: "sort: -modified"), icon: "clock", color: "orange")
        return river
    }

    private var file: String? { try? String(contentsOf: root.appendingPathComponent("rivers/Recent.md"), encoding: .utf8) }

    @Test func aSavedQueryRiverReadsBackAsItWasWritten() {
        let saved = SavedRiver(cards: ["Top"], folded: ["Top"], query: Query(text: "sort: -modified\nhigh priority: Work"),
                               placed: [.init(title: "Kept", place: Query.Place(rank: 1000, key: "2026-11-03T10:00:00.000Z"))],
                               hidden: ["Gone"], opened: ["Open"], icon: "clock", color: "orange")
        #expect(SavedRiver(text: saved.text) == saved)
        #expect(saved.text.contains("```query\nsort: -modified\nhigh priority: Work\n```\n- [[Kept]] @ 1000 2026-11-03T10:00:00.000Z\n"))
    }

    @Test func itShowsWhatItFindsInItsOrder() {
        let river = river()
        #expect(river.cards == ["Delta", "Gamma", "Beta", "Alpha"])
        // What it finds peeks.
        #expect(river.isFolded("Gamma"))
        river.setFolded("Gamma", false)
        #expect(!river.isFolded("Gamma"))
        #expect(file?.contains("opened:\n  - Gamma") == true)
    }

    @Test func aCardOpenedGoesToTheTopAndStays() {
        let river = river()
        river.open("Elsewhere")
        #expect(river.cards.first == "Elsewhere")
        #expect(river.isHeld("Elsewhere"))
        #expect(!river.isFolded("Elsewhere"))
        #expect(file?.hasPrefix("---\nicon: clock\ncolor: orange\n---\n- [[Elsewhere]]\n\n```query\nsort: -modified\n```\n") == true)
    }

    @Test func aCardClosedIsKeptOut() {
        let river = river()
        river.close("Beta")
        #expect(river.cards == ["Delta", "Gamma", "Alpha"])
        #expect(file?.contains("hidden:\n  - Beta") == true)
        river.restoreHidden("Beta")
        #expect(river.cards == ["Delta", "Gamma", "Beta", "Alpha"])
    }

    @Test func aCardMovedKeepsItsPlaceAsOthersCome() async throws {
        let river = river()
        // Alpha, the oldest, put between Delta and Gamma.
        river.move("Alpha", to: "Delta", after: true)
        #expect(river.cards == ["Delta", "Alpha", "Gamma", "Beta"])
        #expect(file?.contains("- [[Alpha]] @ 1000 ") == true)
        // A newer page comes: at the top; Alpha stays between Delta and Gamma.
        river.isShown = false
        store.change("Epsilon") { $0.text = "New." }
        store.finishEditing("Epsilon")
        try await Task.sleep(for: .milliseconds(600))
        #expect(river.cards == ["Epsilon", "Delta", "Alpha", "Gamma", "Beta"])
        // Read back from its file, the same.
        let again = River(store: store)
        store.release(river)
        store.adopt(again)
        again.restore(River.State(graph: root.path, name: "Recent", cards: []))
        #expect(again.cards == ["Epsilon", "Delta", "Alpha", "Gamma", "Beta"])
    }

    @Test func whileInFrontWhatChangesWaits() async throws {
        let river = river()
        river.isShown = true
        store.change("Beta") { $0.text = "Changed." }
        store.finishEditing("Beta")
        try await Task.sleep(for: .milliseconds(600))
        // Not moved under the reader: waiting, counted.
        #expect(river.cards == ["Delta", "Gamma", "Beta", "Alpha"])
        #expect(river.updates == 1)
        river.applyUpdates()
        #expect(river.cards == ["Beta", "Delta", "Gamma", "Alpha"])
        #expect(river.updates == 0)
    }
}
