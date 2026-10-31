import Foundation
import Testing
@testable import WeftCore

@Suite struct RelinkTests {
    @Test func relinksText() {
        let text = """
        See [[Old]], [[Old|the old one]] and ![[Old]], not [[Older]] or `[[Old]]`.

        | a | [[Old\\|cell]] |

        ```query
        tag: Old
        not tag: Other
        ```

        ```swift
        let s = "[[Old]]"
        ```
        """
        #expect(Relink.text(text, from: "Old", to: "New") == """
        See [[New]], [[New|the old one]] and ![[New]], not [[Older]] or `[[Old]]`.

        | a | [[New\\|cell]] |

        ```query
        tag: New
        not tag: Other
        ```

        ```swift
        let s = "[[Old]]"
        ```
        """)
    }

    @Test func renamesThroughTheWiki() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("relink-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let wiki = Wiki(root: root)
        try wiki.save(Tiddler(title: "Old", text: "I am old."))
        try wiki.save(Tiddler(title: "A", text: "Link to [[Old]]."))
        try wiki.save(Tiddler(title: "B", tags: ["Old", "X"]))
        try wiki.save(Tiddler(title: "C", fields: [Tiddler.Field("list", .list(["Old", "A"])), Tiddler.Field("boss", .text("Old"))]))
        try wiki.save(Tiddler(title: "D", text: "Unrelated."))
        #expect(wiki.references(to: "Old") == ["A", "B", "C"])

        var renamed = try #require(wiki["Old"])
        renamed.title = "New"
        try wiki.save(renamed, replacing: "Old")
        #expect(try wiki.relink(from: "Old", to: "New") == 3)
        #expect(wiki["A"]?.text == "Link to [[New]].")
        #expect(wiki["B"]?.tags == ["New", "X"])
        #expect(wiki["C"]?[field: "list"] == .list(["New", "A"]))
        #expect(wiki["C"]?[field: "boss"] == .text("New"))
        #expect(wiki.backlinks(to: "New") == ["A"])
        #expect(wiki.references(to: "Old").isEmpty)

        try wiki.delete("D")
        #expect(wiki["D"] == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("wiki/d.md").path))
    }
}
