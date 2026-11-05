import SwiftUI

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
#else
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
#endif

/// What differs between the Mac and the phone, in one place.
enum Platform {
    static func image(at url: URL) -> PlatformImage? {
        #if os(macOS)
        NSImage(contentsOf: url)
        #else
        UIImage(contentsOfFile: url.path)
        #endif
    }

    /// Whether the pasteboard has words, an address or a picture — asked
    /// without reading them, which on the phone would ask to paste.
    static var pasteboardHasContents: Bool {
        #if os(macOS)
        !(NSPasteboard.general.types ?? []).isEmpty
        #else
        UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs || UIPasteboard.general.hasImages
        #endif
    }

    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    /// Shows a file where the system keeps files: the Finder, on the Mac.
    static func reveal(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    /// The caret taken out of whatever has it.
    static func endEditing() {
        #if os(macOS)
        if let window = NSApp.keyWindow { window.makeFirstResponder(nil) }
        #else
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    /// The find bar of the text the caret is in: words found in a card.
    static func findInCard() {
        #if os(macOS)
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: item)
        #else
        UIApplication.shared.sendAction(#selector(UIResponder.find(_:)), to: nil, from: nil, for: nil)
        #endif
    }

    static var canReveal: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}

extension Image {
    init(platformImage image: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: image)
        #else
        self.init(uiImage: image)
        #endif
    }
}

extension Color {
    /// A card's paper.
    static var card: Color { Ink.card.color }

    /// What the river runs over.
    static var river: Color { Ink.page.color }
}

/// Prism's colours: warm paper and warm ink — off-white and off-black in
/// the light, the same turned about in the dark — and one accent. Cards
/// lie lighter on a page a shade under them.
struct Ink {
    let light: UInt32
    let dark: UInt32
    var alpha: CGFloat = 1

    static let page = Ink(light: 0xf0ece5, dark: 0x161412)
    static let paper = Ink(light: 0xfaf7f2, dark: 0x1d1b18)
    static let card = Ink(light: 0xfdfcf9, dark: 0x23201d)
    static let shelf = Ink(light: 0xf2ede5, dark: 0x262320)
    static let text = Ink(light: 0x2b2724, dark: 0xece6dc)
    static let secondary = Ink(light: 0x6f665d, dark: 0xa79e92)
    static let faint = Ink(light: 0x2b2724, dark: 0xece6dc, alpha: 0.32)
    static let rule = Ink(light: 0x2b2724, dark: 0xece6dc, alpha: 0.1)
    /// A row under the pointer, or chosen with the keys.
    static let hover = Ink(light: 0x2b2724, dark: 0xece6dc, alpha: 0.06)
    static let accent = Ink(light: 0x265cd1, dark: 0x85adff)
    /// A card's drawer of controls: the accent, softened — white on it still clear.
    static let drawer = Ink(light: 0x6189e0, dark: 0x4b6bb5)

    private static func make(_ value: UInt32, _ alpha: CGFloat) -> PlatformColor {
        PlatformColor(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                      blue: CGFloat(value & 0xff) / 255, alpha: alpha)
    }

    /// The colour, light or dark as whatever draws it is.
    var platform: PlatformColor {
        let light = Self.make(self.light, alpha), dark = Self.make(self.dark, alpha)
        #if os(macOS)
        return NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
        #else
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
        #endif
    }

    var color: Color {
        #if os(macOS)
        Color(nsColor: platform)
        #else
        Color(uiColor: platform)
        #endif
    }
}

#if os(macOS)
/// The window a view is in, once it is in one.
public struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    public init(found: @escaping (NSWindow) -> Void) { self.found = found }

    public func makeNSView(context: Context) -> Reader {
        let view = Reader()
        view.found = found
        return view
    }

    public func updateNSView(_ view: Reader, context: Context) {}

    public final class Reader: NSView {
        var found: (NSWindow) -> Void = { _ in }

        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found(window) }
        }
    }
}
#endif
