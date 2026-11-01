import AppKit
import Testing
@testable import WeftUI

/// Pictures pasted into a card: kept in the graph's `assets/`, shown by Markdown.
@MainActor struct PastedPictureTests {
    @Test func aPastedPictureIsKeptAndShown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("weft-pictures-\(UUID().uuidString)")
        PastedPictures.root = root
        defer { PastedPictures.root = nil }
        // A board of its own, not the one the user copies to.
        let board = NSPasteboard(name: NSPasteboard.Name("weft-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        board.clearContents()
        board.setData(image.tiffRepresentation, forType: .tiff)
        let pictures = PastedPictures.pictures(on: board)
        #expect(pictures.count == 1)
        #expect(pictures.first?.ext == "png")
        let shown = try #require(PastedPictures.keep(pictures))
        #expect(shown.hasPrefix("![](assets/pasted-") && shown.hasSuffix(".png)"))
        let path = String(shown.dropFirst(4).dropLast())
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
    }
}
