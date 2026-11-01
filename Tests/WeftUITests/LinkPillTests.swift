import AppKit
import Testing
@testable import WeftCore
@testable import WeftUI

/// Links in the Text editor: pills, and where each goes.
@MainActor struct LinkPillTests {
    let styler = MarkdownStyler(size: 14, exists: { $0 == "Here" })

    private func styled(_ text: String, revealed: NSRange? = nil) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        styler.style(storage, around: nil, revealed: revealed)
        return storage
    }

    private func pill(_ storage: NSTextStorage, at location: Int) -> LinkPill? {
        storage.attribute(.weftPill, at: location, effectiveRange: nil) as? LinkPill
    }

    private func link(_ storage: NSTextStorage, at location: Int) -> URL? {
        storage.attribute(.weftLink, at: location, effectiveRange: nil) as? URL
    }

    @Test func eachKindOfLinkIsAPillToWhereItGoes() {
        let text = "[[Here]] [[Gone]] [docs](https://swift.org) #reading"
        let storage = styled(text)
        let ns = text as NSString
        #expect(pill(storage, at: 3)?.kind == .page)
        #expect(pill(storage, at: 3)?.missing == false)
        #expect(pill(storage, at: ns.range(of: "Gone").location)?.missing == true)
        #expect(pill(storage, at: ns.range(of: "docs").location)?.kind == .web)
        #expect(pill(storage, at: ns.range(of: "#reading").location)?.kind == .tag)
        #expect(link(storage, at: 3).flatMap(InlineMarkdown.title(from:)) == "Here")
        #expect(link(storage, at: ns.range(of: "docs").location) == URL(string: "https://swift.org"))
        #expect(link(storage, at: ns.range(of: "reading").location).flatMap(InlineMarkdown.title(from:)) == "reading")
    }

    @Test func anAddressIsShortenedButOnTheCaretsLine() {
        let text = "see https://www.example.com/a/b/c/page"
        let hidden = { (storage: NSTextStorage, at: Int) in
            ((storage.attribute(.font, at: at, effectiveRange: nil) as? PlatformFont)?.pointSize ?? 14) < 1
        }
        let start = (text as NSString).range(of: "https").location
        let off = styled(text)
        #expect(hidden(off, start))
        #expect(off.attribute(.weftEllipsis, at: (text as NSString).range(of: "b/c").location, effectiveRange: nil) != nil)
        #expect(pill(off, at: start)?.hasLead == true)
        let on = styled(text, revealed: NSRange(location: 0, length: 0))
        #expect(!hidden(on, start))
        #expect(pill(on, at: start)?.hasLead == false)
    }
}
