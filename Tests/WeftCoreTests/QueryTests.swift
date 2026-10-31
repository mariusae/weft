import Foundation
import Testing
@testable import WeftCore

@Suite struct QueryTests {
    func wiki() throws -> (Wiki, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("query-\(UUID())")
        let wiki = Wiki(root: root)
        let day = { (n: Double) in Date(timeIntervalSince1970: n * 86400) }
        try wiki.save(Tiddler(title: "Fruit", fields: [Tiddler.Field("list", .list(["Pear", "Apple"]))], text: "[[Apple]]"))
        try wiki.save(Tiddler(title: "Apple", tags: ["Fruit"], modified: day(3), fields: [Tiddler.Field("colour", .text("red"))], text: "Crisp. [[Pear]]"))
        try wiki.save(Tiddler(title: "Pear", tags: ["Fruit", "Soft"], modified: day(1), text: "Soft."))
        try wiki.save(Tiddler(title: "Banana", tags: ["Fruit", "Soft"], modified: day(2), text: "Yellow."))
        return (wiki, root)
    }

    @Test func readsAndWritesItsText() {
        let text = "tag: Fruit\nnot tag: Soft\nsort: -modified\nlimit: 3\nshow: table\ncolumns: colour, size\nmystery line"
        let query = Query(text: text)
        #expect(query.tags == ["Fruit"])
        #expect(query.excludedTags == ["Soft"])
        #expect(query.sort == .modified && query.descending)
        #expect(query.limit == 3 && query.show == .table && query.columns == ["colour", "size"])
        #expect(query.text == text)
    }

    @Test func findsTiddlers() throws {
        let (wiki, root) = try wiki()
        defer { try? FileManager.default.removeItem(at: root) }
        // A tag's own order first, then by title.
        #expect(Query(text: "tag: Fruit").run(in: wiki, this: "x") == ["Pear", "Apple", "Banana"])
        #expect(Query(text: "tag: {this}\nnot tag: Soft").run(in: wiki, this: "Fruit") == ["Apple"])
        #expect(Query(text: "tag: Fruit\nsort: -modified\nlimit: 2").run(in: wiki, this: "x") == ["Apple", "Banana"])
        #expect(Query(text: "links to: Pear").run(in: wiki, this: "x") == ["Apple"])
        #expect(Query(text: "linked from: {this}").run(in: wiki, this: "Fruit") == ["Apple"])
        #expect(Query(text: "listed in: Fruit").run(in: wiki, this: "x") == ["Pear", "Apple"])
        #expect(Query(text: "has: colour").run(in: wiki, this: "x") == ["Apple"])
        #expect(Query(text: "text: soft").run(in: wiki, this: "x") == ["Pear"])
    }

    @Test func blocksAreParsedAndReplaced() {
        let text = "Intro\n\n```query\ntag: A\n```\n\n```swift\nlet x\n```\n\n```query\ntag: B\n```\n"
        #expect(MarkdownBlock.parse(text)[1] == .query(Query(text: "tag: A")))
        var query = Query(text: "tag: B")
        query.show = .count
        #expect(MarkdownBlock.replacingQuery(at: 1, in: text, with: query)
            == "Intro\n\n```query\ntag: A\n```\n\n```swift\nlet x\n```\n\n```query\ntag: B\nshow: count\n```\n")
    }

    @Test func readsTiddlyWikiFilters() {
        #expect(Query(tiddlyWikiFilter: "[tag[Fruit]!tag[Soft]sort[modified]limit[5]]")?.text
            == "tag: Fruit\nnot tag: Soft\nsort: modified\nlimit: 5")
        #expect(Query(tiddlyWikiFilter: "[all[current]tagging[]]")?.tags == ["{this}"])
        #expect(Query(tiddlyWikiFilter: "[<currentTiddler>backlinks[]!is[system]]")?.linksTo == "{this}")
        #expect(Query(tiddlyWikiFilter: "[[HelloThere]links[]]")?.linkedFrom == "HelloThere")
        #expect(Query(tiddlyWikiFilter: "[tag<currentTiddler>!sort[title]]")?.text == "tag: {this}\nsort: -title")
        #expect(Query(tiddlyWikiFilter: "[enlist{HelloThere!!list}]")?.listedIn == "HelloThere")
        // Steps weft has nothing for, and more than one run, are left alone.
        #expect(Query(tiddlyWikiFilter: "[tag[x]get[caption]]") == nil)
        #expect(Query(tiddlyWikiFilter: "[tag[x]] [tag[y]]") == nil)
        #expect(Query(tiddlyWikiFilter: "[[Just A Title]]") == nil)
    }

    @Test func convertsListMacrosAndWidgets() {
        let wiki = WikiText()
        #expect(wiki.convert("<<list-links filter:\"[tag[Fruit]]\">>").markdown == "```query\ntag: Fruit\n```\n")
        #expect(wiki.convert("<<toc-selective-expandable 'TableOfContents'>>").markdown
            == "```query\ntag: TableOfContents\nshow: tree\n```\n")
        #expect(wiki.convert("<$list filter=\"[tag[Fruit]sort[title]]\"/>").markdown == "```query\ntag: Fruit\nsort: title\n```\n")
        #expect(wiki.convert("<$list filter='[tag[Fruit]]'>\n<$link/>\n</$list>").markdown == "```query\ntag: Fruit\n```\n")
        #expect(wiki.convert("{{{ [tag[Fruit]] }}}").markdown == "```query\ntag: Fruit\n```\n")
        #expect(wiki.convert("<<list-links filter:\"[tag[Fruit]]\">>").residue.isEmpty)
    }
}
