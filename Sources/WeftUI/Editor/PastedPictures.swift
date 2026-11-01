import Foundation
import ReflectCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Pictures pasted into a card's text, or dropped on it on the Mac: kept in
/// the graph's `assets/`, as Prism keeps them, and written where the caret
/// is as Markdown, `![](assets/pasted-….png)`.
@MainActor enum PastedPictures {
    /// The graph's folder, `assets/` in it: told when a graph is opened.
    static var root: URL?

    /// The pictures kept, as the Markdown that shows them; nothing, when
    /// there is no graph or none could be written.
    static func keep(_ pictures: [(data: Data, ext: String)]) -> String? {
        guard let root, !pictures.isEmpty else { return nil }
        let shown = pictures.compactMap { picture in
            (try? Assets.add(picture.data, named: Assets.pastedName(extension: picture.ext), to: root)).map { "![](\($0))" }
        }
        return shown.isEmpty ? nil : shown.joined(separator: " ")
    }

    /// The kinds a note keeps as they are; any other picture is made a PNG.
    private static let kept: [(type: UTType, ext: String)] = [(.png, "png"), (.jpeg, "jpg"), (.gif, "gif")]

    #if os(macOS)
    /// Each picture a pasteboard holds: files of pictures, or a picture itself.
    static func pictures(on board: NSPasteboard) -> [(data: Data, ext: String)] {
        let files = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let fromFiles = files.compactMap { url -> (data: Data, ext: String)? in
            guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
                  let data = try? Data(contentsOf: url) else { return nil }
            if let known = kept.first(where: { type.conforms(to: $0.type) }) { return (data, known.ext) }
            return NSImage(data: data).flatMap(png).map { ($0, "png") }
        }
        if !files.isEmpty { return fromFiles }
        for known in kept {
            if let data = board.data(forType: NSPasteboard.PasteboardType(known.type.identifier)) { return [(data, known.ext)] }
        }
        if let data = board.data(forType: .tiff), let image = NSImage(data: data), let made = png(image) { return [(made, "png")] }
        return []
    }

    private static func png(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
    #else
    /// Each picture on the pasteboard, as its own bytes when a note keeps
    /// that kind as it is, else a JPEG — a photo's HEIC.
    static func pictures(on board: UIPasteboard) -> [(data: Data, ext: String)] {
        board.items.compactMap { item -> (data: Data, ext: String)? in
            for known in kept {
                if let data = item[known.type.identifier] as? Data { return (data, known.ext) }
            }
            let image = item.values.lazy.compactMap { value -> UIImage? in
                if let image = value as? UIImage { return image }
                return (value as? Data).flatMap(UIImage.init(data:))
            }.first
            return image?.jpegData(compressionQuality: 0.9).map { ($0, "jpg") }
        }
    }
    #endif
}
