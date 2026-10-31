import Foundation
import Testing
@testable import WeftCore

@Suite struct ReflectNotesTests {
    func graph() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID())")
        func write(_ path: String, _ text: String) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try write("notes/project-atlas.md", "---\nid: 01a\naliases: [Atlas]\n---\n# Project Atlas\n\n- See [[Fruit]] and [[2026-10-31]]\n")
        try write("daily/2026-10-31.md", "- Worked on [[Atlas]]\n- Ate [[Fruit]]\n")
        try write("notes/secret.md", "---\nprivate: true\n---\n# Secret\n\n- [[Fruit]]\n")
        return root
    }

    @Test func resolvesAsReflectDoes() throws {
        let root = try graph()
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = ReflectNotes(root: root)
        notes.scan()
        #expect(notes.resolve("Project Atlas")?.path == "notes/project-atlas.md")
        #expect(notes.resolve("atlas")?.title == "Project Atlas")
        #expect(notes.resolve("2026-10-31")?.day?.description == "2026-10-31")
        // A day resolves whether or not anything was written on it.
        #expect(notes.resolve("2026-11-01")?.entry == nil)
        // A private note is never shown.
        #expect(notes.resolve("Secret") == nil)
        #expect(notes.resolve("Nothing") == nil)
    }

    @Test func readsBodiesAndBacklinks() throws {
        let root = try graph()
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = ReflectNotes(root: root)
        notes.scan()
        let atlas = try #require(notes.resolve("Project Atlas"))
        // The heading that is its title, and the frontmatter, are not shown.
        #expect(notes.body(of: atlas) == "- See [[Fruit]] and [[2026-10-31]]\n")
        // A tiddler's backlinks from notes, the private one left out.
        #expect(notes.linking(to: ["Fruit"]).map(\.path).sorted() == ["daily/2026-10-31.md", "notes/project-atlas.md"])
        // A note answers to its aliases too.
        #expect(notes.linking(to: atlas.names).map(\.path) == ["daily/2026-10-31.md"])
    }
}

/// How quickly links resolve in a real graph: `WEFT_GRAPH=~/reflect swift test --filter Speed`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WEFT_GRAPH"] != nil)) struct ReflectNotesSpeedTests {
    @Test func linksResolveQuickly() throws {
        let path = (ProcessInfo.processInfo.environment["WEFT_GRAPH"]! as NSString).expandingTildeInPath
        let notes = ReflectNotes(root: URL(fileURLWithPath: path))
        notes.scan()
        let titles = notes.index.all.map(\.title)
        let targets = (0..<2000).map { titles[$0 % titles.count] + ($0 % 3 == 0 ? " missing" : "") }
        var start = Date()
        var found = 0
        for target in targets where notes.resolve(target) != nil { found += 1 }
        let ours = Date().timeIntervalSince(start)
        start = Date()
        var theirs = 0
        for target in targets.prefix(200) where notes.index.resolve(target) != nil { theirs += 1 }
        let index = Date().timeIntervalSince(start) * 10
        print(String(format: "%d notes; 2000 links: %.1f ms through the table, %.0f ms through NoteIndex.resolve", titles.count, ours * 1000, index * 1000))
        #expect(found > 0)
        #expect(ours < 0.2)
        // And to the same notes as Reflect's own resolving, aliases and all.
        let names = notes.index.all.filter { !$0.isPrivate }.flatMap { [$0.title] + $0.aliases }
        for name in names + targets.prefix(200) {
            #expect(notes.resolve(name)?.path == notes.index.resolve(name).flatMap { notes.index.entry($0)?.isPrivate == true ? nil : $0 },
                    "\(name)")
        }
    }
}
