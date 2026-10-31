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
    static let accent = Ink(light: 0x265cd1, dark: 0x85adff)

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
