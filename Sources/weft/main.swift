import Foundation
import WeftCore

/// `weft import <wiki.html> <graph>`: a TiddlyWiki into a graph's `wiki/`.
/// `weft show <graph> <title>`: a tiddler's file.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let usage = """
usage: weft import <wiki.html> <graph>
       weft show <graph> <title>
"""

switch arguments.first {
case "import":
    guard arguments.count == 3 else { fail(usage) }
    let html = (try? String(contentsOfFile: arguments[1], encoding: .utf8)) ?? { fail("Can't read \(arguments[1])") }()
    let root = URL(fileURLWithPath: arguments[2])
    do {
        let start = Date()
        let report = try TiddlyWikiImport.run(html: html, into: root)
        let percent = report.imported == 0 ? 0 : 100 * report.complete / report.imported
        print("""
        \(report.total) tiddlers: \(report.imported) imported, \(report.skipped) left behind (system tiddlers and drafts)
        \(report.written) files written, \(report.unchanged) unchanged, \(report.assets) pictures and other files
        \(report.complete) of \(report.imported) converted completely (\(percent)%)
        """)
        if !report.residue.isEmpty {
            print("\nLeft as WikiText:")
            for (kind, count) in report.residue.sorted(by: { $0.value > $1.value }) {
                let tiddlers = report.incomplete.filter { $0.residue[kind] != nil }.count
                print("  \(kind.padding(toLength: 28, withPad: " ", startingAt: 0)) \(count) in \(tiddlers) tiddlers")
            }
        }
        print(String(format: "\nTook %.1fs", Date().timeIntervalSince(start)))
    } catch {
        fail("\(error)")
    }
case "show":
    guard arguments.count == 3 else { fail(usage) }
    let wiki = Wiki(root: URL(fileURLWithPath: arguments[1]))
    try wiki.load()
    guard let entry = wiki.entries[arguments[2]] else { fail("No tiddler called \(arguments[2])") }
    print("\(entry.path)\n")
    print(entry.source)
    let backlinks = wiki.backlinks(to: entry.page.title)
    if !backlinks.isEmpty { print("Linked from: \(backlinks.joined(separator: ", "))") }
default:
    fail(usage)
}
