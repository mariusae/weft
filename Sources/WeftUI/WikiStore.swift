import Foundation
import Observation
import ReflectCore
import WeftCore

/// The graph open in the window, its wiki, and how this Mac shows it: the
/// river of open cards, which are being edited, and their drafts.
@MainActor @Observable
public final class WikiStore {
    public init() {}

    public private(set) var root: URL?
    private var wiki: Wiki?
    /// The graph's Reflect notes and days, read once the graph is open.
    private var notes: ReflectNotes?
    /// Bumped whenever the wiki changes, so views reading it are redrawn.
    public private(set) var revision = 0

    /// The open cards, top to bottom.
    public private(set) var river: [String] = []
    /// The card to bring into view, and a count so that asking again does.
    public private(set) var focus: String?
    public private(set) var focusRequest = 0
    /// Cards being edited, by the title they are open under, and what they say so far.
    public private(set) var drafts: [String: Tiddler] = [:]
    /// Whether renaming a card's tiddler updates what refers to it; yes
    /// unless turned off in the editor.
    public var relinkOnRename: [String: Bool] = [:]
    /// Cards showing only their titles.
    public var folded: Set<String> = []

    public var search = ""
    public var searchFocusRequest = 0
    public var error: String?
    /// How a graph is chosen here: a folder on the Mac, a GitHub repository
    /// on the phone. Set by the app.
    public var chooseGraph: () -> Void = {}
    /// How a graph's repository is kept in step here: the `git` command
    /// line on the Mac, libgit2 and a GitHub account on the phone. Set by
    /// the app; nil for a graph in no repository.
    public var makeSync: (URL) -> WikiSync? = { _ in nil }
    public private(set) var sync: WikiSync?
    /// What each draft started from, to put together with what a sync
    /// brought in while it was written.
    private var draftBases: [String: Tiddler] = [:]
    private var lastActivation = Date.distantPast

    // MARK: The graph

    /// The graph given with `-GraphPath`, or the one open last.
    public func openInitialGraph() {
        guard let path = UserDefaults.standard.string(forKey: "GraphPath") else { return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else { return }
        open(graph: url)
    }

    public func open(graph url: URL) {
        let wiki = Wiki(root: url)
        do {
            try wiki.load()
        } catch {
            self.error = "Couldn't read \(url.path): \(error.localizedDescription)"
            return
        }
        root = url.standardizedFileURL
        self.wiki = wiki
        drafts = [:]
        folded = []
        UserDefaults.standard.set(url.path, forKey: "GraphPath")
        river = UserDefaults.standard.stringArray(forKey: riverKey) ?? []
        if river.isEmpty { river = defaultRiver(wiki) }
        revision += 1
        let notes = ReflectNotes(root: url)
        self.notes = notes
        Task {
            await Task.detached(priority: .userInitiated) { notes.scan() }.value
            revision += 1
        }
        sync = makeSync(url)
        sync?.onPulled = { [weak self] paths in self?.pulled(paths) }
        sync?.sync()
    }

    /// The app came to the front: take in what other devices wrote.
    public func activated() {
        guard Date().timeIntervalSince(lastActivation) > 1.5 else { return }
        lastActivation = Date()
        sync?.sync()
    }

    /// A sync wrote files: the tiddlers among them are read again. Drafts
    /// stay as they are, to be put together with them when saved.
    private func pulled(_ paths: [String]) {
        guard let wiki else { return }
        for path in paths {
            if WikiFolder.isTiddler(path) {
                wiki.reload(path: path)
            } else if path.hasSuffix(".md") {
                notes?.refresh(path)
            }
        }
        revision += 1
    }

    // MARK: Conflicts

    public func needsReview(_ title: String) -> Bool {
        _ = revision
        return wiki?.needsReview(title) ?? false
    }

    public func conflicted() -> [String] {
        _ = revision
        return wiki?.conflicted() ?? []
    }

    /// A tiddler's text with its conflict markers, to show both sides.
    public func source(_ title: String) -> String? {
        _ = revision
        return wiki?.entries[title]?.source
    }

    public func resolve(_ title: String, keeping side: ConflictMarkers.Resolution) {
        do {
            try wiki?.resolve(title, keeping: side)
        } catch {
            self.error = "Couldn't save “\(title)”: \(error.localizedDescription)"
        }
        revision += 1
        sync?.noteChanged()
    }

    public func openConflicts() {
        for title in conflicted().reversed() { open(title) }
    }

    public var graphName: String { root?.lastPathComponent ?? "Weft" }

    /// Which cards are open is kept per graph, on this Mac only.
    private var riverKey: String { "River:\(root?.path ?? "")" }

    private func saveRiver() {
        UserDefaults.standard.set(river, forKey: riverKey)
    }

    private func defaultRiver(_ wiki: Wiki) -> [String] {
        if wiki["HelloThere"] != nil { return ["HelloThere"] }
        return Array(wiki.recent(limit: 1))
    }

    // MARK: Reading

    public func tiddler(_ title: String) -> Tiddler? {
        _ = revision
        return wiki?[title]
    }

    /// Whether a title leads anywhere: to a tiddler, or a Reflect note or day.
    public func exists(_ title: String) -> Bool { tiddler(title) != nil || note(title) != nil }

    // MARK: Reflect notes

    /// The Reflect note or day a title leads to, when no tiddler has it.
    public func note(_ title: String) -> ReflectNotes.Note? {
        _ = revision
        guard wiki?[title] == nil else { return nil }
        return notes?.resolve(title)
    }

    public func body(of note: ReflectNotes.Note) -> String? {
        _ = revision
        return notes?.body(of: note)
    }

    /// The Reflect notes linking to any of these names.
    public func notesLinking(to names: [String]) -> [ReflectNotes.Note] {
        _ = revision
        return notes?.linking(to: names) ?? []
    }

    /// The tiddlers linking to any of these names.
    public func tiddlersLinking(to names: [String]) -> [String] {
        _ = revision
        return Array(Set(names.flatMap { wiki?.backlinks(to: $0) ?? [] })).sorted()
    }

    /// Reflect notes matching what is typed in search.
    public func noteResults() -> [ReflectNotes.Note] {
        _ = revision
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return notes?.search(query) ?? []
    }

    public func openToday() {
        open(Day.today.description)
    }

    public func backlinks(_ title: String) -> [String] {
        _ = revision
        return wiki?.backlinks(to: title) ?? []
    }

    public func tagged(_ tag: String) -> [String] {
        _ = revision
        return wiki?.tagged(tag) ?? []
    }

    public func tags() -> [(tag: String, count: Int)] {
        _ = revision
        return wiki?.tags() ?? []
    }

    public func recent() -> [String] {
        _ = revision
        return wiki?.recent(limit: 100) ?? []
    }

    public func missing() -> [String] {
        _ = revision
        return wiki?.missing() ?? []
    }

    /// What a query finds, asked from a tiddler.
    public func run(_ query: Query, this: String) -> [String] {
        _ = revision
        guard let wiki else { return [] }
        return query.run(in: wiki, this: this)
    }

    /// The fields a tiddler's tags give it.
    public func schema(for tiddler: Tiddler) -> [FieldSpec] {
        _ = revision
        return wiki?.schema(for: tiddler) ?? []
    }

    /// Every title, for completing links.
    public var titles: [String] {
        _ = revision
        return wiki?.titles ?? []
    }

    public var count: Int {
        _ = revision
        return wiki?.entries.count ?? 0
    }

    /// Titles matching what is typed — those with it in the title first,
    /// starting with it before containing it — then those with it in the text.
    public func searchResults(limit: Int = 200) -> [String] {
        _ = revision
        let query = search.trimmingCharacters(in: .whitespaces)
        guard let wiki, !query.isEmpty else { return [] }
        var starts: [String] = [], contains: [String] = [], inText: [String] = []
        for title in wiki.titles {
            if title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
                starts.append(title)
            } else if title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                contains.append(title)
            } else if wiki[title]?.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                inText.append(title)
            }
        }
        return Array((starts + contains + inText).prefix(limit))
    }

    /// A tiddler's file.
    public func path(of title: String) -> URL? {
        _ = revision
        guard let root, let entry = wiki?.entries[title] else { return nil }
        return root.appendingPathComponent(entry.path)
    }

    /// A picture's file in the graph, for a source like `assets/cat.png`.
    public func file(_ source: String) -> URL? {
        guard let root, !source.contains("://"), !source.hasPrefix("/") else { return nil }
        let path = source.removingPercentEncoding ?? source
        return root.appendingPathComponent(path)
    }

    // MARK: The river

    /// Opens a card, or brings it into view when it is open already. A card
    /// opened from another goes just after it, as in TiddlyWiki; otherwise
    /// at the top.
    public func open(_ title: String, from source: String? = nil) {
        // A note opened by an alias, or in other case, is opened by its title.
        let title = note(title)?.title ?? title
        if !river.contains(title) {
            if let source, let index = river.firstIndex(of: source) {
                river.insert(title, at: index + 1)
            } else {
                river.insert(title, at: 0)
            }
            saveRiver()
        }
        folded.remove(title)
        bringIntoView(title)
    }

    public func bringIntoView(_ title: String) {
        focus = title
        focusRequest += 1
    }

    public func close(_ title: String) {
        river.removeAll { $0 == title }
        drafts[title] = nil
        draftBases[title] = nil
        folded.remove(title)
        saveRiver()
    }

    public func closeOthers(_ title: String) {
        for other in river where other != title && drafts[other] == nil { close(other) }
    }

    public func closeAll() {
        for title in river where drafts[title] == nil { close(title) }
    }

    public func toggleFold(_ title: String) {
        if folded.contains(title) { folded.remove(title) } else { folded.insert(title) }
    }

    // MARK: Editing

    public func isEditing(_ title: String) -> Bool { drafts[title] != nil }

    public func draft(_ title: String) -> Tiddler? { drafts[title] }

    public func edit(_ title: String) {
        drafts[title] = tiddler(title) ?? Tiddler(title: title)
        draftBases[title] = tiddler(title)
        open(title)
    }

    public func updateDraft(_ title: String, _ tiddler: Tiddler) {
        drafts[title] = tiddler
    }

    public func cancel(_ title: String) {
        drafts[title] = nil
        draftBases[title] = nil
        // A new tiddler never saved goes with its draft.
        if !exists(title) { close(title) }
    }

    /// Saves a card's draft: a new tiddler gets an id and its creation time,
    /// every save the time it was modified. Renaming keeps the tiddler's
    /// file, and its card where it was.
    public func save(_ title: String) {
        guard let wiki, var tiddler = drafts[title] else { return }
        // Changed by a sync while it was being written: the two put together.
        if let base = draftBases[title], let current = wiki[title], current != base {
            tiddler = TiddlerMerge.merge(draft: tiddler, base: base, current: current)
        }
        tiddler.title = tiddler.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tiddler.title.isEmpty else {
            error = "A tiddler needs a title."
            return
        }
        if tiddler.title != title, wiki[tiddler.title] != nil {
            error = "There is already a tiddler called “\(tiddler.title)”."
            return
        }
        let now = Date()
        if tiddler.id == nil { tiddler.id = Tiddler.newID() }
        if tiddler.created == nil { tiddler.created = now }
        tiddler.modified = now
        do {
            try wiki.save(tiddler, replacing: wiki[title] != nil ? title : nil)
        } catch {
            self.error = "Couldn't save “\(tiddler.title)”: \(error.localizedDescription)"
            return
        }
        // Renamed: what named it names it still, unless asked not to.
        if tiddler.title != title, wiki[title] == nil, relinkOnRename[title] ?? true {
            do {
                try wiki.relink(from: title, to: tiddler.title)
            } catch {
                self.error = "Couldn't update the tiddlers linking to “\(title)”: \(error.localizedDescription)"
            }
        }
        relinkOnRename[title] = nil
        drafts[title] = nil
        draftBases[title] = nil
        sync?.noteChanged()
        if tiddler.title != title, let index = river.firstIndex(of: title) {
            river[index] = tiddler.title
            if folded.remove(title) != nil { folded.insert(tiddler.title) }
            saveRiver()
        }
        revision += 1
    }

    /// Changes one of a tiddler's query blocks, from its card, and saves it.
    public func updateQuery(in title: String, at index: Int, to query: Query) {
        guard var tiddler = tiddler(title) else { return }
        tiddler.text = MarkdownBlock.replacingQuery(at: index, in: tiddler.text, with: query)
        tiddler.modified = Date()
        do {
            try wiki?.save(tiddler)
        } catch {
            self.error = "Couldn't save “\(title)”: \(error.localizedDescription)"
        }
        revision += 1
        sync?.noteChanged()
    }

    /// The tiddlers naming a title: linking, tagging, listing, asking for it.
    public func references(to title: String) -> [String] {
        _ = revision
        return wiki?.references(to: title) ?? []
    }

    /// Takes a tiddler out, and its card. Its file goes; the history keeps it.
    public func delete(_ title: String) {
        do {
            try wiki?.delete(title)
        } catch {
            self.error = "Couldn't delete “\(title)”: \(error.localizedDescription)"
            return
        }
        close(title)
        revision += 1
        sync?.noteChanged()
    }

    /// A new tiddler, at the top of the river, being edited — tagged with
    /// `tag`, when there is one, and given its fields.
    public func newTiddler(taggedWith tag: String? = nil) {
        guard wiki != nil else { return }
        var title = tag.map { "New \($0)" } ?? "New Tiddler"
        let base = title
        var number = 1
        while exists(title) || river.contains(title) {
            title = "\(base) \(number)"
            number += 1
        }
        var tiddler = Tiddler(title: title, tags: tag.map { [$0] } ?? [])
        for spec in schema(for: tiddler) { tiddler[field: spec.name] = .text("") }
        drafts[title] = tiddler
        open(title)
    }
}
