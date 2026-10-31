import Foundation
import Testing
@testable import WeftCore

@Suite struct TiddlerFileTests {
    let sample = """
    ---
    id: 01jbxk3t6y8q2zp4m9v7c5r0wd
    title: HelloThere
    tags: [Welcome, Table of Contents]
    created: 2014-09-13T09:20:00Z
    modified: 2026-10-31T10:41:12.123Z
    caption: Hello
    ---
    Welcome to [[TiddlyWiki]].

    """

    @Test func readsTheFields() {
        let tiddler = TiddlerFile.read(sample, fallbackTitle: "x")
        #expect(tiddler.title == "HelloThere")
        #expect(tiddler.id == "01jbxk3t6y8q2zp4m9v7c5r0wd")
        #expect(tiddler.tags == ["Welcome", "Table of Contents"])
        #expect(tiddler.created == TiddlyWikiDate.parse("20140913092000000"))
        #expect(tiddler.modified == TiddlyWikiDate.parse("20261031104112123"))
        #expect(tiddler.fields == [Tiddler.Field("caption", .text("Hello"))])
        #expect(tiddler.text == "Welcome to [[TiddlyWiki]].\n")
    }

    @Test func writesBackTheSameBytes() {
        let odd = [
            sample,
            sample.replacingOccurrences(of: "\n", with: "\r\n"),
            "---\n# a comment\ntitle:   Spaced   \ntags:\n- one\n-   two\n\nweird: 'it''s'\n...\nbody",
            "---\ntitle: T\nnote: |\n  line one\n    indented\n\n  after a gap\n---\n",
            "---\n---\njust a body\n",
            "no frontmatter at all\n",
            "---\ntitle: never closed\n",
            "",
        ]
        for source in odd {
            let tiddler = TiddlerFile.read(source, fallbackTitle: "fallback")
            #expect(TiddlerFile.write(tiddler, over: source, fallbackTitle: "fallback") == source, "\(source.debugDescription)")
        }
    }

    @Test func changesOnlyWhatChanged() {
        var tiddler = TiddlerFile.read(sample, fallbackTitle: "x")
        tiddler.tags.append("New")
        tiddler.text = "Changed.\n"
        tiddler[field: "caption"] = nil
        tiddler[field: "color"] = .text("#ff0000")
        #expect(TiddlerFile.write(tiddler, over: sample) == """
        ---
        id: 01jbxk3t6y8q2zp4m9v7c5r0wd
        title: HelloThere
        tags: [Welcome, Table of Contents, New]
        created: 2014-09-13T09:20:00Z
        modified: 2026-10-31T10:41:12.123Z
        color: "#ff0000"
        ---
        Changed.

        """)
    }

    @Test func keepsADateWrittenAnotherWay() {
        let source = "---\ntitle: T\nmodified: 2026-10-31T10:41:12.000Z\n---\n"
        let tiddler = TiddlerFile.read(source, fallbackTitle: "x")
        #expect(TiddlerFile.write(tiddler, over: source) == source)
    }

    @Test func roundTripsAwkwardValues() {
        let values = ["", " leading", "trailing ", "a: b", "#hash", "- dash", "true", "42", "3.14", "it's \"quoted\"",
                      "back\\slash", "two\nlines\n", "no newline\nat end", "\n starts badly", "tab\there", "[bracket",
                      "ünïcødé", "x # not a comment"]
        for value in values {
            let tiddler = Tiddler(title: value.isEmpty ? "empty" : value, tags: [value, "a, b", "[[x]]"].filter { !$0.isEmpty },
                                  fields: [Tiddler.Field("f", .text(value)), Tiddler.Field("l", .list([value, "y"]))])
            let source = TiddlerFile.write(tiddler)
            let back = TiddlerFile.read(source, fallbackTitle: "empty")
            #expect(back.fields == tiddler.fields, "\(value.debugDescription) → \(source)")
            #expect(back.tags == tiddler.tags, "\(value.debugDescription) → \(source)")
            #expect(back.title == tiddler.title.trimmingCharacters(in: .newlines) || value.contains("\n"))
        }
    }

    @Test func writesLongListsAnItemALine() {
        let tiddler = Tiddler(title: "Contents", fields: [Tiddler.Field("list", .list(["One", "Two", "Three", "Four", "Five"]))])
        #expect(TiddlerFile.write(tiddler) == "---\ntitle: Contents\nlist:\n  - One\n  - Two\n  - Three\n  - Four\n  - Five\n---\n")
    }

    @Test func addsAHeaderWhereThereWasNone() {
        let tiddler = Tiddler(title: "Plain", text: "body\n")
        #expect(TiddlerFile.write(tiddler, over: "body\n") == "---\ntitle: Plain\n---\nbody\n")
        #expect(TiddlerFile.write(tiddler, over: "---\n---\nbody\n") == "---\ntitle: Plain\n---\nbody\n")
    }

    @Test func fallsBackToTheFileName() {
        #expect(TiddlerFile.read("just text", fallbackTitle: "name").title == "name")
    }
}

@Suite struct WikiTests {
    @Test func indexesLinksAndTags() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wiki-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let wiki = Wiki(root: root)
        try wiki.save(Tiddler(title: "Contents", fields: [Tiddler.Field("list", .list(["B"]))], text: "See [[A]] and ![[B]]."))
        try wiki.save(Tiddler(title: "A", tags: ["Contents"], text: "`[[not a link]]` [[B|bee]]"))
        try wiki.save(Tiddler(title: "B", tags: ["Contents"], text: "[[Nowhere]]"))

        let reread = Wiki(root: root)
        try reread.load()
        #expect(reread.titles == ["A", "B", "Contents"])
        #expect(reread.backlinks(to: "B") == ["A", "Contents"])
        #expect(reread.missing() == ["Nowhere"])
        #expect(reread.tagged("Contents") == ["B", "A"])
        // Contents is a tag, so not an orphan, though nothing links to it.
        #expect(reread.orphans() == [])
        #expect(try String(contentsOf: root.appendingPathComponent(".reflectignore"), encoding: .utf8) == "/wiki/\n")
    }

    @Test func savesUnderFreeNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wiki-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let wiki = Wiki(root: root)
        #expect(try wiki.save(Tiddler(title: "Jermolene")).path == "wiki/jermolene.md")
        #expect(try wiki.save(Tiddler(title: "@Jermolene")).path == "wiki/jermolene-2.md")
        // Renaming keeps the file.
        var renamed = try #require(wiki["Jermolene"])
        renamed.title = "Jeremy"
        #expect(try wiki.save(renamed, replacing: "Jermolene").path == "wiki/jermolene.md")
        #expect(wiki["Jermolene"] == nil)
    }

    @Test func leavesAnExistingIgnoreAlone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wiki-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("drafts/".utf8).write(to: root.appendingPathComponent(".reflectignore"))
        try WikiFolder.prepare(in: root)
        try WikiFolder.prepare(in: root)
        #expect(try String(contentsOf: root.appendingPathComponent(".reflectignore"), encoding: .utf8) == "drafts/\n/wiki/\n")
    }
}
