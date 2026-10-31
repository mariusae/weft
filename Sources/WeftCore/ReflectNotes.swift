import Foundation
import ReflectCore

/// The Reflect notes and days of the graph the wiki is in, as cards can show
/// them: found by their names as Reflect resolves `[[links]]` — a date is
/// its day, then a note's title, then an alias — read through reflect-mac's
/// own index, with which notes link to each name.
public final class ReflectNotes: @unchecked Sendable {
    public let index: NoteIndex
    private let lock = NSLock()
    /// The notes linking to each name, by the name's fold key.
    private var linkers: [String: Set<String>] = [:]
    /// The note each name leads to, by its fold key — a title before an
    /// alias, the first by path of each — as `NoteIndex.resolve` finds
    /// them, but without sorting every note for every link: cards resolve
    /// links each time they are drawn.
    private var names: [String: String] = [:]

    public init(root: URL) {
        index = NoteIndex(root: root)
    }

    /// Reads every note. A few thousand take a moment: off the main thread.
    public func scan() {
        index.scan()
        var found: [String: Set<String>] = [:]
        for entry in index.all {
            guard let body = index.body(entry.path) else { continue }
            for target in WikiLinks.targets(in: body) {
                found[NoteIndex.foldKey(target), default: []].insert(entry.path)
            }
        }
        lock.withLock { linkers = found }
        indexNames()
    }

    private func indexNames() {
        var titles: [String: String] = [:], aliases: [String: String] = [:]
        for entry in index.all.sorted(by: { $0.path < $1.path }) {
            let title = NoteIndex.foldKey(entry.title)
            if titles[title] == nil { titles[title] = entry.path }
            for alias in entry.aliases {
                let key = NoteIndex.foldKey(alias)
                if aliases[key] == nil { aliases[key] = entry.path }
            }
        }
        lock.withLock { names = titles.merging(aliases) { title, _ in title } }
    }

    /// Reads one note again, after a sync or another app wrote it.
    public func refresh(_ path: String) {
        let before = index.body(path).map(WikiLinks.targets(in:)) ?? []
        index.refresh(path)
        let after = index.body(path).map(WikiLinks.targets(in:)) ?? []
        lock.withLock {
            for target in before.subtracting(after) { linkers[NoteIndex.foldKey(target)]?.remove(path) }
            for target in after { linkers[NoteIndex.foldKey(target), default: []].insert(path) }
        }
        indexNames()
    }

    /// A note or day by a name, as a link to it resolves.
    public func resolve(_ name: String) -> Note? {
        let raw = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // A date or a week is its note, whether or not one is written yet.
        let path = Day(raw) != nil || Week(raw) != nil ? index.resolve(raw) : lock.withLock { names[NoteIndex.foldKey(raw)] }
        guard let path else { return nil }
        if let day = GraphPaths.day(fromDailyPath: path) {
            return Note(path: path, title: day.description, day: day, entry: index.entry(path))
        }
        guard let entry = index.entry(path), !entry.isPrivate else { return nil }
        return Note(path: path, title: entry.title, day: nil, entry: entry)
    }

    /// A note's body, without its frontmatter or the heading that is its title.
    public func body(of note: Note) -> String? {
        guard let text = index.body(note.path) ?? (try? String(contentsOf: index.root.appendingPathComponent(note.path), encoding: .utf8))
        else { return nil }
        var body = TiddlerFile.split(text).body
        let lines = body.components(separatedBy: "\n")
        if let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }), first.hasPrefix("# "),
           NoteIndex.foldKey(String(first.dropFirst(2))) == NoteIndex.foldKey(note.title) {
            body = lines.drop { $0 != first }.dropFirst().joined(separator: "\n")
        }
        return body.trimmingCharacters(in: .newlines) + "\n"
    }

    /// The notes linking to any of these names — a tiddler's title, or a
    /// note's title and aliases — as `(path, title)`, newest first.
    public func linking(to names: [String]) -> [Note] {
        let paths = lock.withLock { names.reduce(into: Set<String>()) { $0.formUnion(linkers[NoteIndex.foldKey($1)] ?? []) } }
        return paths.compactMap { path in
            guard let entry = index.entry(path), !entry.isPrivate else { return nil }
            return Note(path: path, title: entry.day?.description ?? entry.title, day: entry.day, entry: entry)
        }
        .sorted { ($0.entry?.modified ?? .distantPast) > ($1.entry?.modified ?? .distantPast) }
    }

    /// Notes by a name typed in search: the whole name first, then its start,
    /// the starts of its words, its initials — as Reflect's chooser finds them.
    public func search(_ query: String, limit: Int = 30) -> [Note] {
        index.matches(query, limit: limit).compactMap { match in
            guard !match.entry.isPrivate else { return nil }
            return Note(path: match.entry.path, title: match.entry.day?.description ?? match.entry.title,
                        day: match.entry.day, entry: match.entry)
        }
    }

    /// A Reflect note or day.
    public struct Note: Equatable, Sendable {
        public var path: String
        /// What a card is open under: the note's title, or the day's date.
        public var title: String
        public var day: Day?
        public var entry: NoteEntry?

        /// The names it answers to: its title, or date, and its aliases.
        public var names: [String] { [title] + (entry?.aliases ?? []) }

        /// "Saturday, 31 October 2026", for a day; the title, for a note.
        public var displayTitle: String {
            guard let date = day?.date else { return title }
            return date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        }

        public var tags: [String] { entry?.tags ?? [] }
    }
}
