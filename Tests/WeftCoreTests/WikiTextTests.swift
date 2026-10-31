import Testing
@testable import WeftCore

@Suite struct WikiTextTests {
    func md(_ text: String, images: [String: String] = [:]) -> String {
        WikiText(images: images).convert(text).markdown
    }

    func residue(_ text: String) -> [String: Int] {
        WikiText().convert(text).residue
    }

    @Test func inlineFormatting() {
        #expect(md("''bold'' //italic// __under__ ~~gone~~ ^^up^^ ,,down,, `code`")
            == "**bold** *italic* <u>under</u> ~~gone~~ <sup>up</sup> <sub>down</sub> `code`\n")
        #expect(md("''bold //and italic//''") == "**bold *and italic***\n")
        #expect(md("an https://example.com/a//b link, and //this//.")
            == "an https://example.com/a//b link, and *this*.\n")
    }

    @Test func links() {
        #expect(md("[[HelloThere]] and [[shown|Target Title]]") == "[[HelloThere]] and [[Target Title|shown]]\n")
        #expect(md("[[TiddlyWiki|https://tiddlywiki.com]] [ext[docs|https://x.org]]")
            == "[TiddlyWiki](https://tiddlywiki.com) [docs](https://x.org)\n")
        #expect(md("~CamelCase stays") == "CamelCase stays\n")
    }

    @Test func images() {
        #expect(md("[img[Motovun Jack.jpg]]", images: ["Motovun Jack.jpg": "assets/motovun-jack.jpg"])
            == "![](assets/motovun-jack.jpg)\n")
        #expect(md("[img width=32 [A cat|https://x.org/cat.png]]") == "![A cat](https://x.org/cat.png)<!-- {\"width\":32} -->\n")
        #expect(md("[img[Unknown Picture]]") == "![[Unknown Picture]]\n")
    }

    @Test func transclusion() {
        #expect(md("{{Some Tiddler}}") == "![[Some Tiddler]]\n")
        #expect(md("{{Some Tiddler||Template}} and {{!!caption}}") == "{{Some Tiddler||Template}} and {{!!caption}}\n")
        #expect(residue("{{Some Tiddler||Template}}") == ["transclusion": 1])
        #expect(residue("{{Some Tiddler}}").isEmpty)
    }

    @Test func headingsAndRules() {
        #expect(md("! One\n!! Two\n!!!.cls Three\n---") == "# One\n\n## Two\n\n### Three\n\n---\n")
    }

    @Test func lists() {
        #expect(md("* one\n** two\n* three\n# first\n## nested\n#* mixed") == """
        - one
          - two
        - three
        1. first
           1. nested
           - mixed

        """)
        #expect(md("; term\n: definition") == "**term**\n  definition\n")
        #expect(md("> quoted\n>> deeper") == "> quoted\n> > deeper\n")
    }

    @Test func blockQuotes() {
        #expect(md("<<<\nWise words.\n<<< Someone") == "> Wise words.\n>\n> — Someone\n")
    }

    @Test func tables() {
        #expect(md("|!Name|!Value|\n|a|[[b|B]]|\n|c|d|") == """
        | Name | Value |
        | --- | --- |
        | a | [[B\\|b]] |
        | c | d |

        """)
        #expect(md("|x|y|\n|cap|c") == "*cap*\n\n|  |  |\n| --- | --- |\n| x | y |\n")
        #expect(residue("|a|~|") == ["table": 1])
    }

    @Test func codeAndTypedBlocks() {
        #expect(md("```js\nlet x = ''a'';\n```") == "```js\nlet x = ''a'';\n```\n")
        #expect(md("$$$text/css\nbody {}\n$$$") == "```css\nbody {}\n```\n")
    }

    @Test func leavesWhatHasNoMarkdown() {
        #expect(md("<<tag-picker>>") == "```tiddlywiki\n<<tag-picker>>\n```\n")
        #expect(md("Inline <<.def \"thing\">> here.") == "Inline <<.def \"thing\">> here.\n")
        #expect(residue("Inline <<.def \"thing\">> here.") == ["macro": 1])
        let widget = "<$list filter=\"[tag[x]]\">\n\n<$view field=\"caption\"/>\n\n</$list>\n\nAfter."
        #expect(md(widget) == "```tiddlywiki\n<$list filter=\"[tag[x]]\">\n\n<$view field=\"caption\"/>\n\n</$list>\n```\n\nAfter.\n")
        #expect(md("\\define hello(name) Hi $name$\n\n<<hello you>>") ==
            "```tiddlywiki\n\\define hello(name) Hi $name$\n```\n\n```tiddlywiki\n<<hello you>>\n```\n")
        #expect(md("\\procedure p()\nbody\n\\end\nText") == "```tiddlywiki\n\\procedure p()\nbody\n\\end\n```\n\nText\n")
    }

    @Test func escapesWhatMarkdownWouldMisread() {
        #expect(md("5 * 3 = 15, snake_case, _lead") == "5 \\* 3 = 15, snake_case, \\_lead\n")
        #expect(md("Para\n+ not a list\n1. not numbered") == "Para\n\\+ not a list\n\\1. not numbered\n")
    }

    @Test func styles() {
        #expect(md("@@.note Watch out@@") == "Watch out\n")
        #expect(md("@@color:red;Red text@@") == "Red text\n")
    }

    func docs(_ text: String) -> String {
        WikiText(documentationMacros: true).convert(text).markdown
    }

    @Test func documentationMacros() {
        #expect(docs("A <<.def thing>> uses <<.var currentTiddler>> and <<.olink tag>>.")
            == "A *thing* uses `currentTiddler` and [[tag Operator|tag]].\n")
        #expect(docs("<<.tip \"Use ''this''.\">>") == "> [!TIP]\n> Use **this**.\n")
        #expect(docs("<<.link-badge-fixed \"https://github.com/x/1\">>") == "[fixed](https://github.com/x/1)\n")
        #expect(docs("<<.operator-example 1 \"[tag[x]]\">>") == "`[tag[x]]`\n")
        // Without them, the same calls are left as written.
        #expect(md("A <<.def thing>>.") == "A <<.def thing>>.\n")
    }

    @Test func multiLineMacroCalls() {
        let text = "<<wikitext-example src:\"* one\n** two\n\">>\n\n! After"
        #expect(docs(text) == "```wikitext\n* one\n** two\n```\n\nThat renders as:\n\n- one\n  - two\n\n# After\n")
        #expect(md(text) == "```tiddlywiki\n<<wikitext-example src:\"* one\n** two\n\">>\n```\n\n# After\n")
    }

    @Test func tableCellAlignment() {
        #expect(md("|^ top|, bottom|") == "|  |  |\n| --- | --- |\n| top | bottom |\n")
    }
}
