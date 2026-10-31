import CryptoKit
import Foundation
import ReflectCore

/// A TiddlyWiki — the single HTML file — brought into a graph's `notes/`,
/// as wiki pages.
///
/// Its tiddlers are read from the JSON it keeps them in; system tiddlers
/// (`$:/…`) and drafts are left behind. WikiText becomes Markdown, pictures
/// go to `assets/`, and each tiddler gets a file. Importing again writes
/// over what an import wrote, changing only what changed: a tiddler keeps
/// its file and its id.
public enum TiddlyWikiImport {
    public struct Report {
        /// Tiddlers in the file, and those left behind as system tiddlers or drafts.
        public var total = 0
        public var skipped = 0
        public var imported = 0
        /// Files written, and those already as they would be written.
        public var written = 0
        public var unchanged = 0
        /// Pictures and other files, put in `assets/`.
        public var assets = 0
        /// Tiddlers converted with nothing left as WikiText.
        public var complete = 0
        /// What was left as WikiText, by kind, over all tiddlers.
        public var residue: [String: Int] = [:]
        /// The tiddlers with something left as WikiText, and what.
        public var incomplete: [(title: String, residue: [String: Int])] = []
    }

    public struct ImportError: Error, CustomStringConvertible {
        public var description: String
    }

    /// The tiddlers in a TiddlyWiki's HTML, each its fields as text.
    public static func tiddlers(inHTML html: String) throws -> [[String: String]] {
        let marker = "<script class=\"tiddlywiki-tiddler-store\" type=\"application/json\">"
        var tiddlers: [[String: String]] = []
        var rest = html[...]
        while let open = rest.range(of: marker) {
            guard let close = rest[open.upperBound...].range(of: "</script>") else { break }
            let json = Data(rest[open.upperBound..<close.lowerBound].utf8)
            guard let array = try JSONSerialization.jsonObject(with: json) as? [[String: Any]] else {
                throw ImportError(description: "A tiddler store that is not a list of tiddlers")
            }
            tiddlers += array.map { fields in fields.mapValues { "\($0)" } }
            rest = rest[close.upperBound...]
        }
        guard !tiddlers.isEmpty else {
            throw ImportError(description: "No tiddlers found: this needs a TiddlyWiki of version 5.2 or later, which keeps them as JSON")
        }
        return tiddlers
    }

    /// Imports a TiddlyWiki's HTML into the graph at `root`.
    public static func run(html: String, into root: URL) throws -> Report {
        var report = Report()
        let all = try tiddlers(inHTML: html)
        report.total = all.count
        let wanted = all.filter { fields in
            guard let title = fields["title"], !title.isEmpty else { return false }
            return !title.hasPrefix("$:/") && fields["draft.of"] == nil
        }.sorted { $0["title"]! < $1["title"]! }
        report.skipped = all.count - wanted.count

        let wiki = Wiki(root: root)
        try wiki.load()

        // Pictures and other files first, so links to them can show them.
        var assets: [String: String] = [:]
        for fields in wanted {
            guard let type = fields["type"], !isText(type), fields["_canonical_uri"] == nil,
                  let title = fields["title"], let data = assetData(fields) else { continue }
            assets[title] = try saveAsset(data, title: title, type: type, root: root)
            report.assets += 1
        }

        // tiddlywiki.com's own documentation is written with macros of its
        // own, which come to plain Markdown.
        let documentation = all.contains { $0["title"] == "$:/editions/tw5.com/doc-macros" }
        let converter = WikiText(images: assets, documentationMacros: documentation)
        for fields in wanted {
            let title = fields["title"]!
            var residue: [String: Int] = [:]
            let text = body(fields, assets: assets, converter: converter, residue: &residue)
            let created = fields["created"].flatMap(TiddlyWikiDate.parse)
            let modified = fields["modified"].flatMap(TiddlyWikiDate.parse)
            var tiddler = Tiddler(title: title,
                                  id: wiki[title]?.id ?? ulid(at: created ?? modified ?? Date(timeIntervalSince1970: 0), seed: title),
                                  tags: stringArray(fields["tags"] ?? ""),
                                  created: created, modified: modified, text: text)
            // What a TiddlyWiki holds is a wiki's: canonical, kept up.
            tiddler.isWiki = true
            for name in fields.keys.sorted() where !leftBehind.contains(name) {
                let value = fields[name]!
                tiddler.fields.append(Tiddler.Field(name, listFields.contains(name) ? .list(stringArray(value)) : .text(value)))
            }
            let before = wiki.entries[title]?.source
            let entry = try wiki.save(tiddler)
            if entry.source == before { report.unchanged += 1 } else { report.written += 1 }
            report.imported += 1
            if residue.isEmpty {
                report.complete += 1
            } else {
                report.incomplete.append((title, residue))
                for (kind, count) in residue { report.residue[kind, default: 0] += count }
            }
        }
        return report
    }

    /// Fields the tiddler's own properties hold, or that mean nothing here.
    static let leftBehind: Set<String> = ["title", "text", "tags", "created", "modified", "type", "revision", "bag", "_canonical_uri"]
    /// Fields holding a list of titles.
    static let listFields: Set<String> = ["list", "list-before", "list-after"]

    private static func body(_ fields: [String: String], assets: [String: String], converter: WikiText,
                             residue: inout [String: Int]) -> String {
        let text = fields["text"] ?? ""
        let type = fields["type"] ?? ""
        switch type {
        case "", "text/vnd.tiddlywiki":
            let result = converter.convert(text)
            residue = result.residue
            return result.markdown
        case "text/x-markdown", "text/markdown":
            return text
        case _ where !isText(type):
            let picture = type.hasPrefix("image/") ? "!" : ""
            let shown = picture.isEmpty ? (fields["title"] ?? "") : ""
            if let uri = fields["_canonical_uri"] { return "\(picture)[\(shown)](\(uri))\n" }
            if let asset = assets[fields["title"] ?? ""] { return "\(picture)[\(shown)](\(asset))\n" }
            residue[type, default: 0] += 1
            return ""
        default:
            let language = ["text/plain": "", "text/css": "css", "application/javascript": "js", "application/json": "json",
                            "text/html": "html", "text/vnd.tiddlywiki-multiple": "tiddlywiki"][type]
            if language == nil || type == "text/vnd.tiddlywiki-multiple" { residue[type, default: 0] += 1 }
            let fence = text.contains("```") ? "````" : "```"
            return "\(fence)\(language ?? "")\n\(text)\(text.hasSuffix("\n") ? "" : "\n")\(fence)\n"
        }
    }

    /// Whether a tiddler of this type is text, rather than a file in base64.
    static func isText(_ type: String) -> Bool {
        type.isEmpty || type.hasPrefix("text/") || ["application/javascript", "application/json", "application/x-tiddler-dictionary", "application/x-tiddlers"].contains(type)
    }

    private static func assetData(_ fields: [String: String]) -> Data? {
        let text = fields["text"] ?? ""
        if fields["type"] == "image/svg+xml" { return Data(text.utf8) }
        return Data(base64Encoded: text, options: .ignoreUnknownCharacters)
    }

    /// Writes a picture to `assets/`, named for its title, or finds it there
    /// from an import before.
    private static func saveAsset(_ data: Data, title: String, type: String, root: URL) throws -> String {
        var name = title
        let extensions = ["image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp",
                          "image/svg+xml": "svg", "image/x-icon": "ico", "image/heic": "heic", "audio/mp3": "mp3",
                          "audio/mpeg": "mp3", "audio/mp4": "m4a", "video/mp4": "mp4", "application/pdf": "pdf"]
        if (name as NSString).pathExtension.isEmpty {
            name += ".\(extensions[type] ?? String(type.split(separator: "/").last ?? "bin"))"
        }
        let fileName = Assets.fileName(for: name)
        let stem = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        for attempt in 1...1000 {
            let path = "\(Assets.directory)/\(attempt == 1 ? stem : "\(stem)-\(attempt)").\(ext)"
            let url = root.appendingPathComponent(path)
            guard let existing = try? Data(contentsOf: url) else { break }
            if existing == data { return path }
        }
        return try Assets.add(data, named: fileName, to: root)
    }

    /// TiddlyWiki's list of titles: separated by spaces, `[[two words]]` kept together.
    public static func stringArray(_ text: String) -> [String] {
        var items: [String] = []
        var rest = Substring(text)
        while true {
            rest = rest.drop { $0.isWhitespace }
            guard !rest.isEmpty else { break }
            if rest.hasPrefix("[["), let close = rest.range(of: "]]") {
                items.append(String(rest[rest.index(rest.startIndex, offsetBy: 2)..<close.lowerBound]))
                rest = rest[close.upperBound...]
            } else {
                let word = rest.prefix { !$0.isWhitespace }
                items.append(String(word))
                rest = rest.dropFirst(word.count)
            }
        }
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    /// A ULID as Reflect writes them, its time `date` and the rest made from
    /// `seed`, so that importing the same tiddler again gives it the same id.
    static func ulid(at date: Date, seed: String) -> String {
        let alphabet = Array("0123456789abcdefghjkmnpqrstvwxyz")
        var time = UInt64(max(0, date.timeIntervalSince1970 * 1000))
        var text = [Character](repeating: "0", count: 26)
        for index in stride(from: 9, through: 0, by: -1) {
            text[index] = alphabet[Int(time % 32)]
            time /= 32
        }
        let digest = Array(SHA256.hash(data: Data(seed.utf8)))
        for index in 10..<26 { text[index] = alphabet[Int(digest[index] % 32)] }
        return String(text)
    }
}
