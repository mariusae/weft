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
