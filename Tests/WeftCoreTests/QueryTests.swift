import Foundation
import Testing
@testable import WeftCore

@Suite struct QueryTests {
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
