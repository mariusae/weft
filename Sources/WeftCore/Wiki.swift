import Foundation
import ReflectCore

/// The tiddlers of a graph's `wiki/`, every one in memory, as TiddlyWiki
/// keeps them, with what links to what and what is tagged with what.
public final class Wiki {
    public let root: URL

    /// A tiddler, the file it is kept in, and that file's text as last read
    /// or written.
    public struct Entry {
        public var path: String
        public var tiddler: Tiddler
        public var source: String
    }

    public private(set) var entries: [String: Entry] = [:]
    /// Titles each tiddler links to, and the titles linking to each.
    private var outgoing: [String: Set<String>] = [:]
    private var incoming: [String: Set<String>] = [:]

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public var titles: [String] { entries.keys.sorted() }

    public subscript(title: String) -> Tiddler? { entries[title]?.tiddler }

    /// Reads every tiddler from `wiki/`. A title two files claim goes to the
    /// first by path.
    public func load() throws {
        entries = [:]
        outgoing = [:]
        incoming = [:]
        let folder = root.appendingPathComponent(WikiFolder.directory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names.sorted() where name.hasSuffix(".md") {
            let path = "\(WikiFolder.directory)/\(name)"
            guard let data = try? Data(contentsOf: root.appendingPathComponent(path)) else { continue }
            let source = String(decoding: data, as: UTF8.self)
            let tiddler = TiddlerFile.read(source, fallbackTitle: WikiFolder.fallbackTitle(for: path))
            guard entries[tiddler.title] == nil else { continue }
            entries[tiddler.title] = Entry(path: path, tiddler: tiddler, source: source)
            index(tiddler)
        }
    }

    /// Writes a tiddler to its file — a new one to a new file — changing only
    /// what changed in it.
    @discardableResult
    public func save(_ tiddler: Tiddler, replacing oldTitle: String? = nil) throws -> Entry {
        let previous = entries[oldTitle ?? tiddler.title]
        let path = previous?.path ?? WikiFolder.path(for: tiddler.title, in: root, taken: Set(entries.values.map(\.path)))
        let source = TiddlerFile.write(tiddler, over: previous?.source, fallbackTitle: WikiFolder.fallbackTitle(for: path))
        if source != previous?.source {
            try WikiFolder.prepare(in: root)
            try Data(source.utf8).write(to: root.appendingPathComponent(path), options: .atomic)
        }
        if let previous {
            unindex(previous.tiddler)
            entries[previous.tiddler.title] = nil
        }
        let entry = Entry(path: path, tiddler: tiddler, source: source)
        entries[tiddler.title] = entry
        index(tiddler)
        return entry
    }

    /// Reads one tiddler's file again — after another app or a sync wrote
    /// it — or forgets it, when the file is gone.
    public func reload(path: String) {
        let previous = entries.first { $0.value.path == path }
        if let previous {
            unindex(previous.value.tiddler)
            entries[previous.key] = nil
        }
        guard let data = try? Data(contentsOf: root.appendingPathComponent(path)) else { return }
        let source = String(decoding: data, as: UTF8.self)
        let tiddler = TiddlerFile.read(source, fallbackTitle: WikiFolder.fallbackTitle(for: path))
        entries[tiddler.title] = Entry(path: path, tiddler: tiddler, source: source)
        index(tiddler)
    }

    // MARK: Conflicts

    /// Tiddlers a sync left both devices' changes in, between markers.
    public func conflicted() -> [String] {
        entries.values.filter { ConflictMarkers.detect($0.source) }.map(\.tiddler.title).sorted()
    }

    public func needsReview(_ title: String) -> Bool {
        entries[title].map { ConflictMarkers.detect($0.source) } ?? false
    }

    /// Settles a tiddler's conflicts, keeping one side of each or both, in
    /// its file as written.
    public func resolve(_ title: String, keeping side: ConflictMarkers.Resolution) throws {
        guard let entry = entries[title] else { return }
        let resolved = ConflictMarkers.resolve(entry.source, keeping: side)
        try Data(resolved.utf8).write(to: root.appendingPathComponent(entry.path), options: .atomic)
        reload(path: entry.path)
    }

    // MARK: Links

    public func links(from title: String) -> Set<String> { outgoing[title] ?? [] }

    public func backlinks(to title: String) -> [String] { (incoming[title] ?? []).sorted() }

    /// Titles linked to that no tiddler has.
    public func missing() -> [String] { incoming.keys.filter { entries[$0] == nil }.sorted() }

    /// Tiddlers nothing links to, tags, or lists.
    public func orphans() -> [String] {
        let tags = Set(entries.values.flatMap(\.tiddler.tags))
        let listed = Set(entries.values.flatMap { $0.tiddler[field: "list"]?.list ?? [] })
        return entries.keys.filter { (incoming[$0] ?? []).isEmpty && !tags.contains($0) && !listed.contains($0) }.sorted()
    }

    private func index(_ tiddler: Tiddler) {
        let targets = WikiLinks.targets(in: tiddler.text)
        outgoing[tiddler.title] = targets
        for target in targets { incoming[target, default: []].insert(tiddler.title) }
    }

    private func unindex(_ tiddler: Tiddler) {
        for target in outgoing[tiddler.title] ?? [] { incoming[target]?.remove(tiddler.title) }
        outgoing[tiddler.title] = nil
    }

    // MARK: Tags

    /// The tiddlers tagged with `tag`, in the order the tag's own tiddler
    /// lists them, then by title — as TiddlyWiki orders them.
    public func tagged(_ tag: String) -> [String] {
        let all = Set(entries.values.filter { $0.tiddler.tags.contains(tag) }.map(\.tiddler.title))
        let listed = (entries[tag]?.tiddler[field: "list"]?.list ?? []).filter(all.contains)
        let rest = all.subtracting(listed).sorted()
        return listed + rest
    }

    /// Every tag, with how many tiddlers have it.
    public func tags() -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for entry in entries.values { for tag in entry.tiddler.tags { counts[tag, default: 0] += 1 } }
        return counts.map { ($0.key, $0.value) }.sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    /// The tiddlers written most lately, newest first.
    public func recent(limit: Int = 50) -> [String] {
        entries.values.sorted { ($0.tiddler.modified ?? .distantPast) > ($1.tiddler.modified ?? .distantPast) }
            .prefix(limit).map(\.tiddler.title)
    }
}

/// The links in a tiddler's Markdown: `[[Title]]`, `[[Title|shown]]`, and
/// embeds, `![[Title]]` — outside code.
public enum WikiLinks {
    public static func targets(in markdown: String) -> Set<String> {
        var targets = Set<String>()
        var inFence = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            guard !inFence, line.contains("[[") else { continue }
            var rest = removingCodeSpans(line)[...]
            while let open = rest.range(of: "[[") {
                guard let close = rest[open.upperBound...].range(of: "]]") else { break }
                var target = String(rest[open.upperBound..<close.lowerBound])
                if let bar = target.firstIndex(of: "|") { target = String(target[..<bar]) }
                target = target.replacingOccurrences(of: "\\", with: "").trimmingCharacters(in: .whitespaces)
                if !target.isEmpty { targets.insert(target) }
                rest = rest[close.upperBound...]
            }
        }
        return targets
    }

    private static func removingCodeSpans(_ line: Substring) -> String {
        var result = ""
        var inCode = false
        for character in line {
            if character == "`" { inCode.toggle(); continue }
            if !inCode { result.append(character) }
        }
        return result
    }
}
