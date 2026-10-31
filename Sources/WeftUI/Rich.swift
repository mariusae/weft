import ImageIO
import Observation
import ReflectCore
import SwiftUI
import WeftCore

// What a card's preview shows besides words — pictures and link cards, as
// Prism shows them — and the caches that keep drawing it cheap: nothing is
// parsed, read or decoded twice, and nothing is read on the main thread.

/// Parsed Markdown, kept by its text: a card drawn again reads its blocks
/// and its lines' styled text from here, not from the parser.
@MainActor
enum MarkdownCache {
    private static var blocks: [String: [MarkdownBlock]] = [:]
    private static var inline: [String: AttributedString] = [:]
    private static var pieces: [String: InlinePieces] = [:]
    private static let most = 4000

    static func blocks(_ text: String) -> [MarkdownBlock] {
        if let found = blocks[text] { return found }
        if blocks.count > most / 4 { blocks.removeAll(keepingCapacity: true) }
        let parsed = MarkdownBlock.parse(text)
        blocks[text] = parsed
        return parsed
    }

    /// A line's inline Markdown as styled text, before links are coloured
    /// by whether they lead anywhere.
    static func attributed(_ text: String) -> AttributedString {
        if let found = inline[text] { return found }
        if inline.count > most { inline.removeAll(keepingCapacity: true) }
        let prepared = InlineMarkdown.prepared(text)
        var string = (try? AttributedString(markdown: prepared, options: .init(
            allowsExtendedAttributes: true, interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible
        ))) ?? AttributedString(text)
        for run in string.runs where run.inlinePresentationIntent?.contains(.code) == true {
            string[run.range].font = .system(.body, design: .monospaced).weight(.regular)
            string[run.range].backgroundColor = Color.secondary.opacity(0.12)
        }
        inline[text] = string
        return string
    }

    static func pieces(_ text: String) -> InlinePieces {
        if let found = pieces[text] { return found }
        if pieces.count > most { pieces.removeAll(keepingCapacity: true) }
        let split = InlinePieces(text)
        pieces[text] = split
        return split
    }
}

/// A line as its words, its pictures, and — when it is a link alone — the
/// card the link shows: read with Prism's own rules (`InlineMarkup`).
struct InlinePieces: Equatable {
    /// The line without its pictures or comments.
    var words: String
    var pictures: [ImageReference]
    /// The link the line is, alone, when it shows a card; and what it says.
    var card: (source: String, text: String?)?

    static func == (a: InlinePieces, b: InlinePieces) -> Bool {
        a.words == b.words && a.pictures == b.pictures && a.card?.source == b.card?.source
    }

    init(_ line: String) {
        let text = line as NSString
        let spans = InlineMarkup.spans(in: text, range: NSRange(location: 0, length: text.length))
        var pictures: [ImageReference] = []
        var cut: [NSRange] = []
        var card: (String, String?)?
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for span in spans {
            switch span.kind {
            case .image(let reference):
                pictures.append(reference)
                cut.append(span.range)
            case .comment:
                cut.append(span.range)
            case .link(let target), .url(let target):
                // Alone in its line, as Prism shows a card.
                if !span.hidesCard, text.substring(with: span.range) == trimmed, RichLinkKind.of(target) != nil {
                    let shown = span.content.location != NSNotFound && span.content.length > 0 ? text.substring(with: span.content) : nil
                    card = (target, shown == target ? nil : shown)
                }
            default:
                break
            }
        }
        var words = line
        for range in cut.sorted(by: { $0.location > $1.location }) {
            words = (words as NSString).replacingCharacters(in: range, with: "")
        }
        self.words = words.trimmingCharacters(in: .whitespaces)
        self.pictures = pictures
        self.card = card
    }
}

// MARK: Pictures

/// Pictures decoded off the main thread at the size they are drawn, and kept.
@MainActor
final class Pictures {
    static let shared = Pictures()
    private let cache = NSCache<NSString, PlatformImage>()
    private var sizes: [String: CGSize] = [:]

    private init() { cache.countLimit = 300 }

    func cached(_ key: String) -> PlatformImage? { cache.object(forKey: key as NSString) }

    /// A picture's natural size in points, when known.
    func size(_ key: String) -> CGSize? { sizes[key] }

    /// A picture, a local file or a web address, decoded no larger than
    /// `pixels` across.
    func load(_ url: URL, key: String, pixels: CGFloat) async -> PlatformImage? {
        if let image = cached(key) { return image }
        let found: (CGImage, CGSize)? = await Task.detached(priority: .userInitiated) {
            let data: Data?
            if url.isFileURL {
                data = try? Data(contentsOf: url, options: .mappedIfSafe)
            } else {
                data = try? await Self.fetch(url)
            }
            guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            var width = properties?[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
            var height = properties?[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
            if let orientation = properties?[kCGImagePropertyOrientation] as? Int, orientation >= 5 { swap(&width, &height) }
            let dpi = properties?[kCGImagePropertyDPIWidth] as? CGFloat ?? 72
            let scale = dpi > 100 ? dpi / 72 : 1
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceShouldCacheImmediately: true,
                                            kCGImageSourceThumbnailMaxPixelSize: max(64, pixels)]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return (image, CGSize(width: width / scale, height: height / scale))
        }.value
        guard let (cgImage, size) = found else { return nil }
        #if os(macOS)
        let image = NSImage(cgImage: cgImage, size: size)
        #else
        let image = UIImage(cgImage: cgImage)
        #endif
        cache.setObject(image, forKey: key as NSString)
        sizes[key] = size
        return image
    }

    /// A web picture, kept on disk so it is fetched once.
    nonisolated private static func fetch(_ url: URL) async throws -> Data {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Weft/Pictures")
        var hash: UInt64 = 14695981039346656037
        for byte in url.absoluteString.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let file = folder.appendingPathComponent(String(hash, radix: 16))
        if let data = try? Data(contentsOf: file) { return data }
        let (data, _) = try await URLSession.shared.data(from: url)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }
}

/// A picture in a card: from the graph — `assets/…`, or anywhere in it — or
/// the web; its width as the note says, else its own, never wider than the
/// card. Drawn once decoded; until then, room kept for it.
struct PictureView: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.displayScale) private var displayScale
    let reference: ImageReference
    /// Filling a square of this side, cropped — a card's thumbnail — not
    /// fitted to its width.
    var filling: CGFloat?
    @State private var image: PlatformImage?
    @State private var failed = false

    var body: some View {
        let url = self.url
        let key = (url?.absoluteString ?? reference.source) + "@" + String(Int(pixels))
        Group {
            if let image = image ?? Pictures.shared.cached(key), let side = filling {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if let image = image ?? Pictures.shared.cached(key) {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: width(of: image))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Ink.rule.color, lineWidth: 0.5))
            } else if failed || url == nil {
                Label(reference.alt.isEmpty ? reference.source : reference.alt, systemImage: "photo")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Ink.rule.color.opacity(0.3))
                    .frame(maxWidth: reference.width.map { CGFloat($0) } ?? 320)
                    .aspectRatio(aspect, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(reference.alt)
        .task(id: key) {
            guard image == nil, let url else { return }
            image = await Pictures.shared.load(url, key: key, pixels: pixels)
            failed = image == nil
        }
    }

    private var url: URL? {
        let source = reference.source
        if let url = URL(string: source), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" { return url }
        return store.file(source)
    }

    /// As many pixels across as it is drawn: its width, or a card's.
    private var pixels: CGFloat { CGFloat(reference.width ?? 760) * max(displayScale, 1) }

    private var aspect: CGFloat {
        if let width = reference.width, let height = reference.height, height > 0 { return width / height }
        return 4 / 3
    }

    private func width(of image: PlatformImage) -> CGFloat {
        if let width = reference.width { return CGFloat(width) }
        return image.size.width
    }
}

// MARK: Link cards

/// The cards links show, fetched once with Prism's own code — `RichLinks`,
/// kept in its folder — and told to the cards waiting on them.
@MainActor
final class LinkCards {
    static let shared = LinkCards()
    @Observable final class Box {
        var face: RichCardFace?
        var settled = false
    }
    private var boxes: [String: Box] = [:]
    private let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Weft/Links")

    func box(_ source: String, text: String?) -> Box {
        if let box = boxes[source] { return box }
        let box = Box()
        boxes[source] = box
        if case .some(let known) = RichLinks.cached(source, in: folder) {
            box.face = known.map { RichCardFace($0, linkText: text) }
            box.settled = true
            return box
        }
        let folder = folder
        Task {
            let card = await RichLinks.load(source, in: folder)
            box.face = card.map { RichCardFace($0, linkText: text) }
            box.settled = true
        }
        return box
    }
}

/// A link's card, as Prism draws one: the service over a title, a line or
/// two more, a line of facts; a page's picture at the right, a cover at the left.
struct LinkCardView: View {
    let source: String
    let text: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        let box = LinkCards.shared.box(source, text: text)
        if let face = box.face {
            Button { if let url = URL(string: source) { openURL(url) } } label: { card(face) }
                .buttonStyle(.plain)
                .help(source)
        } else {
            InlineText(text: text.map { "[\($0)](\(source))" } ?? source, cards: false)
        }
    }

    private func card(_ face: RichCardFace) -> some View {
        let tint = face.tint.map { Color(red: $0.0, green: $0.1, blue: $0.2) } ?? Ink.secondary.color
        return HStack(alignment: .top, spacing: 12) {
            if case .artwork(let picture) = face.picture { thumbnail(picture, side: 64) }
            VStack(alignment: .leading, spacing: 3) {
                Label(face.service, systemImage: face.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Text(face.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Ink.text.color)
                    .lineLimit(2)
                if let detail = face.detail {
                    Text(detail).font(.caption).foregroundStyle(Ink.secondary.color).lineLimit(2)
                }
                if let facts = face.facts {
                    Text(facts).font(.caption2).foregroundStyle(Ink.faint.color).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if case .thumbnail(let picture) = face.picture { thumbnail(picture, side: 64) }
        }
        .padding(12)
        .frame(maxWidth: 460, alignment: .leading)
        .background(Ink.paper.color, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.rule.color))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private func thumbnail(_ source: String, side: CGFloat) -> some View {
        PictureView(reference: ImageReference(source: source, width: Double(side * 2)), filling: side)
            .frame(width: side, height: side)
    }
}
