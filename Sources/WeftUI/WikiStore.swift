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
    /// Every page of the graph — its days, weeks and notes — as GraphKit
    /// reads them, Prism's way.
    private var wiki: Wiki?
    /// Bumped whenever the wiki changes, so views reading it are redrawn.
    public private(set) var revision = 0

    /// The open cards, top to bottom.
    public private(set) var river: [String] = []
    /// The card to bring into view, and a count so that asking again does.
    public private(set) var focus: String?
    public private(set) var focusRequest = 0
    /// Cards being edited, by the title they are open under, and what they say so far.
    public private(set) var drafts: [String: Tiddler] = [:]
    /// Which cards are being edited, apart from what their drafts say: a
    /// card asks only this, so typing in one redraws that card's editor and
    /// not the river.
    public private(set) var editing: Set<String> = []
    /// Whether renaming a card's tiddler updates what refers to it; yes
    /// unless turned off in the editor.
    public var relinkOnRename: [String: Bool] = [:]
    /// Saves waiting for typing to pause, by card.
    @ObservationIgnored private var autosaves: [String: Task<Void, Never>] = [:]
    /// Tiddlers whose file was made while they were edited.
    @ObservationIgnored private var createdWhileEditing: Set<String> = []
    /// The tags a new tiddler was made with, which alone do not make it worth a file.
    @ObservationIgnored private var schemaTags: [String: [String]] = [:]
    /// Cards showing only their titles.
    public var folded: Set<String> = []

    public var search = ""
    public var searchFocusRequest = 0
    /// Whether ⌘O's Quick Open is showing.
    public var quickOpenShown = false
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

    /// Whether the first launch's onboarding is done — or skipped, for a
    /// graph given with `-GraphPath`.
    public private(set) var onboarded = UserDefaults.standard.bool(forKey: "Onboarded")
        || ProcessInfo.processInfo.arguments.contains("-GraphPath")

    public func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "Onboarded")
        onboarded = true
    }

    /// The graph given with `-GraphPath`, or the one open last.
    public func openInitialGraph() {
        guard onboarded, let path = UserDefaults.standard.string(forKey: "GraphPath") else { return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else { return }
        open(graph: url)
    }

    /// Opens a graph: the window shows it at once, and its pages once they
    /// are read — off the main thread, so nothing waits on them.
    public func open(graph url: URL) {
        let wiki = Wiki(root: url)
        loads += 1
        let load = loads
        root = url.standardizedFileURL
        self.wiki = nil
        isLoading = true
        drafts = [:]
        editing = []
        folded = []
        outlined = []
        linkNotes = nil
        river = []
        sync = nil
        revision += 1
        Task {
            let failure: String? = await Task.detached(priority: .userInitiated) {
                do {
                    try wiki.load()
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            // Another graph opened meanwhile: this one is not wanted.
            guard load == loads else { return }
            isLoading = false
            if let failure {
                root = nil
                self.error = "Couldn't read \(url.path): \(failure)"
                return
            }
            loaded(wiki, at: url)
        }
    }

    private func loaded(_ wiki: Wiki, at url: URL) {
        self.wiki = wiki
        UserDefaults.standard.set(url.path, forKey: "GraphPath")
        river = UserDefaults.standard.stringArray(forKey: riverKey) ?? []
        if river.isEmpty { river = defaultRiver(wiki) }
        revision += 1
        sync = makeSync(url)
        sync?.onPulled = { [weak self] paths in self?.pulled(paths) }
        sync?.sync()
        let waiting = whenLoaded
        whenLoaded = []
        for body in waiting { body() }
    }

    /// Whether the graph's pages are being read.
    public private(set) var isLoading = false
    @ObservationIgnored private var loads = 0
    @ObservationIgnored private var whenLoaded: [() -> Void] = []

    /// Runs once the graph's pages are read — now, if they are.
    public func whenLoaded(_ body: @escaping () -> Void) {
        if wiki != nil, !isLoading { body() } else { whenLoaded.append(body) }
    }

    /// The app came to the front: take in what other devices wrote.
    public func activated() {
        guard Date().timeIntervalSince(lastActivation) > 1.5 else { return }
        lastActivation = Date()
        sync?.sync()
    }

    /// A sync wrote files: the pages among them are read again. Drafts
    /// stay as they are, to be put together with them when saved.
    private func pulled(_ paths: [String]) {
        guard let wiki else { return }
        for path in paths where PageFolder.isPage(path) { wiki.reload(path: path) }
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
        let recent = wiki.recent(limit: 1)
        return recent.isEmpty ? [ShadowTiddlers.gettingStarted] : recent
    }

    // MARK: Reading

    public func tiddler(_ title: String) -> Tiddler? {
        _ = revision
        guard let wiki else { return nil }
        return wiki[title] ?? ShadowTiddlers.all[title]
    }

    /// Whether a title is one of weft's own tiddlers, not yet the wiki's.
    public func isShadow(_ title: String) -> Bool {
        _ = revision
        return wiki?[title] == nil && ShadowTiddlers.all[title] != nil
    }

    /// Whether a title leads anywhere: to a page, or to a day or week,
    /// written yet or not.
    public func exists(_ title: String) -> Bool { tiddler(title) != nil || Day(title) != nil || Week(title) != nil }

    /// What a page is, by where it is — a day's, a week's, or a note's —
    /// and whether it is in the wiki.
    public func kind(_ title: String) -> LinkTarget.Kind {
        _ = revision
        if Day(title) != nil || Week(title) != nil { return .day }
        if let entry = wiki?.entries[title] {
            if case .note = entry.kind { return entry.page.isWiki ? .wiki : .note }
            return .day
        }
        if let shadow = ShadowTiddlers.all[title] { return shadow.isWiki ? .wiki : .note }
        return .new
    }

    /// How a title is shown: a day's date in words, else the title.
    public func shownTitle(_ title: String) -> String {
        guard let date = Day(title)?.date else { return title }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    /// The pages linking to a page, by any name it answers to.
    public func linking(to title: String) -> [String] {
        _ = revision
        return wiki?.backlinks(to: title) ?? []
    }

    /// The wiki's pages, by title.
    public func wikiPages() -> [String] {
        _ = revision
        guard let wiki else { return [] }
        return wiki.titles.filter { wiki[$0]?.isWiki == true }
    }

    /// Whether a page is part of the wiki.
    public func isWiki(_ title: String) -> Bool { tiddler(title)?.isWiki ?? false }

    /// Puts a page in the wiki, or takes it out: its `wiki` flag, saved.
    public func setWiki(_ title: String, _ wiki: Bool) {
        if var draft = drafts[title] {
            draft.isWiki = wiki
            updateDraft(title, draft)
            return
        }
        guard var page = tiddler(title) else { return }
        page.isWiki = wiki
        write(page, from: title)
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
        return wiki?.search(search, limit: limit) ?? []
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
        // A page opened by an alias, or in other case, is opened by its title.
        let title = wiki?.title(for: title) ?? title
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

    /// Makes a card the one ⌘↩ and the outline go to, without moving the river.
    public func select(_ title: String) {
        if focus != title { focus = title }
    }

    /// ⌘↩: the selected card between editing and reading.
    public func toggleEditing() {
        guard let title = focus, river.contains(title) else { return }
        if isEditing(title) {
            finishEditing(title)
        } else {
            edit(title)
        }
    }

    public func close(_ title: String) {
        if isEditing(title) { finishEditing(title, closing: true) }
        river.removeAll { $0 == title }
        drafts[title] = nil
        editing.remove(title)
        draftBases[title] = nil
        folded.remove(title)
        saveRiver()
    }

    public func closeOthers(_ title: String) {
        for other in river where other != title { close(other) }
    }

    public func closeAll() {
        for title in river { close(title) }
    }

    public func toggleFold(_ title: String) {
        if folded.contains(title) { folded.remove(title) } else { folded.insert(title) }
    }

    // MARK: Editing

    /// A card is in Edit or in Preview, and that is all: what is written in
    /// Edit is saved a moment after typing pauses, and when the card goes
    /// back to Preview — where a new title, too, takes effect.
    public func isEditing(_ title: String) -> Bool { editing.contains(title) }

    // MARK: Text or Outline

    /// How a card's body is edited: as text, unless an outline is asked
    /// for — in Prism's outline editor.
    public enum EditorMode: String, CaseIterable, Sendable {
        case text = "Text", outline = "Outline"
    }

    /// Cards edited as outlines, by title; every other is edited as text.
    public private(set) var outlined: Set<String> = []

    public func editorMode(_ title: String) -> EditorMode { outlined.contains(title) ? .outline : .text }

    public func setEditorMode(_ mode: EditorMode, for title: String) {
        if mode == .outline { outlined.insert(title) } else { outlined.remove(title) }
    }

    /// The graph's pages, for an outline's queries and embeds to ask.
    public var pages: PageIndex? {
        _ = revision
        return wiki
    }

    /// Every note by name, as Prism's index has them — for an outline's
    /// `[[` to complete from — read off the main thread once asked for.
    @ObservationIgnored public private(set) var linkNotes: NoteIndex?

    public func prepareLinkNotes(_ ready: @escaping @MainActor (NoteIndex) -> Void) {
        if let linkNotes { return ready(linkNotes) }
        guard let root else { return }
        let notes = NoteIndex(root: root)
        Task {
            await Task.detached(priority: .utility) { notes.scan() }.value
            guard self.root == root else { return }
            linkNotes = notes
            ready(notes)
        }
    }

    public func draft(_ title: String) -> Tiddler? { drafts[title] }

    public func edit(_ title: String) {
        guard !isEditing(title) else { return open(title) }
        drafts[title] = tiddler(title) ?? Tiddler(title: title)
        editing.insert(title)
        draftBases[title] = wiki?[title]
        open(title)
    }

    public func updateDraft(_ title: String, _ tiddler: Tiddler) {
        drafts[title] = tiddler
        autosaves[title]?.cancel()
        autosaves[title] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            self?.autosave(title)
        }
    }

    /// Writes what every card being edited says, now: before the app goes
    /// to the background, or quits.
    public func saveEditing() {
        for title in editing { autosave(title) }
    }

    /// A new tiddler with nothing in it yet, which is not worth a file.
    private func isUntouched(_ title: String, _ draft: Tiddler) -> Bool {
        wiki?[title] == nil && draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.fields.allSatisfy { $0.value.text?.isEmpty ?? ($0.value.list?.isEmpty ?? true) }
            && (draft.tags.isEmpty || draft.tags == schemaTags[title])
    }

    /// Writes a card's draft under the title it is open under: a title
    /// being typed takes effect only when the card goes to Preview.
    private func autosave(_ title: String) {
        autosaves[title]?.cancel()
        autosaves[title] = nil
        guard var tiddler = drafts[title], !isUntouched(title, tiddler) else { return }
        tiddler.title = title
        guard tiddler != wiki?[title] || wiki?[title] == nil else { return }
        if write(tiddler, from: title) { draftBases[title] = wiki?[title] }
    }

    /// Back to Preview: the draft written, a new title taken — with what
    /// referred to it updated, unless asked not to — and the card read again.
    public func finishEditing(_ title: String, closing: Bool = false) {
        autosaves[title]?.cancel()
        autosaves[title] = nil
        guard let wiki, var tiddler = drafts[title] else { return }
        defer { revision += 1 }
        if isUntouched(title, tiddler) {
            // Made and left empty: it goes, card and all.
            drafts[title] = nil
            editing.remove(title)
            draftBases[title] = nil
            if !closing, !exists(title) { close(title) }
            return
        }
        tiddler.title = tiddler.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if tiddler.title.isEmpty { tiddler.title = title }
        if tiddler.title != title, wiki[tiddler.title] != nil || ShadowTiddlers.all[tiddler.title] != nil {
            error = "There is already a tiddler called “\(tiddler.title)”; this one keeps its title."
            tiddler.title = title
        }
        guard write(tiddler, from: title) else { return }
        if tiddler.title != title, wiki[title] == nil, relinkOnRename[title] ?? true {
            do {
                try wiki.relink(from: title, to: tiddler.title)
            } catch {
                self.error = "Couldn't update the tiddlers linking to “\(title)”: \(error.localizedDescription)"
            }
        }
        relinkOnRename[title] = nil
        drafts[title] = nil
        editing.remove(title)
        draftBases[title] = nil
        createdWhileEditing.remove(title)
        if tiddler.title != title, let index = river.firstIndex(of: title) {
            river[index] = tiddler.title
            if folded.remove(title) != nil { folded.insert(tiddler.title) }
            if focus == title { focus = tiddler.title }
            saveRiver()
        }
    }

    /// Saves a tiddler open under `title`: a new one gets an id and its
    /// creation time, every save the time it was modified; one a sync changed
    /// meanwhile is put together with it. Renamed, it keeps its file —
    /// unless the file was made while it was edited, and named for the title
    /// it had then. True when it was written.
    @discardableResult
    private func write(_ draft: Tiddler, from title: String) -> Bool {
        guard let wiki else { return false }
        var tiddler = draft
        if let base = draftBases[title], let current = wiki[title], current != base, ShadowTiddlers.all[title] != base {
            tiddler = TiddlerMerge.merge(draft: tiddler, base: base, current: current)
        }
        // A new page gets an id and its times; a page that keeps its
        // modified time gets a new one. A day or a week, named by its file,
        // and a note of Prism's that keeps no times, are written as they are.
        let now = Date()
        let existed = wiki[title] != nil
        let named = Day(title) == nil && Week(title) == nil
        if !existed, named {
            if tiddler.id == nil { tiddler.id = Tiddler.newID() }
            if tiddler.created == nil { tiddler.created = now }
            tiddler.modified = now
        } else if tiddler.modified != nil {
            tiddler.modified = now
        }
        do {
            let entry = try wiki.save(tiddler, replacing: existed ? title : nil, movingFile: createdWhileEditing.contains(title))
            linkNotes?.refresh(entry.path)
        } catch {
            self.error = "Couldn't save “\(tiddler.title)”: \(error.localizedDescription)"
            return false
        }
        if !existed { createdWhileEditing.insert(title) }
        revision += 1
        sync?.noteChanged()
        return true
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
        // What Weft makes is the wiki's.
        tiddler.isWiki = true
        for spec in schema(for: tiddler) { tiddler[field: spec.name] = .text("") }
        schemaTags[title] = tiddler.tags
        drafts[title] = tiddler
        editing.insert(title)
        open(title)
    }
}

/// Somewhere a link, a backlink or Quick Open leads: a wiki page, a
/// note, a day or week, or a page not written yet.
public struct LinkTarget: Hashable, Sendable {
    /// What a link to it says, and what its card is open under.
    public var title: String
    /// What it is shown as: a day's date in words, else its title.
    public var shown: String
    public var kind: Kind

    public enum Kind: Sendable {
        case wiki, note, day, new

        public var symbol: String {
            switch self {
            case .wiki: "book.closed"
            case .note: "doc.text"
            case .day: "calendar"
            case .new: "plus.circle"
            }
        }

        public var label: String {
            switch self {
            case .wiki: "Wiki"
            case .note: "Note"
            case .day: "Day"
            case .new: "New page"
            }
        }
    }
}

extension WikiStore {
    /// What a title leads to, as a link to it would.
    public func target(_ title: String) -> LinkTarget {
        let title = wiki?.title(for: title) ?? title
        return LinkTarget(title: title, shown: shownTitle(title), kind: kind(title))
    }

    /// What links to a card: wiki pages first, then notes and days, by title.
    public func backlinks(of card: String) -> [LinkTarget] {
        let order: [LinkTarget.Kind: Int] = [.wiki: 0, .note: 1, .day: 2, .new: 3]
        return linking(to: card).map(target).sorted { (order[$0.kind] ?? 0, $0.title) < (order[$1.kind] ?? 0, $1.title) }
    }

    /// The words around a source's link to a card, for its summary.
    public func context(of source: LinkTarget, linkingTo card: String) -> String? {
        guard let text = tiddler(source.title)?.text else { return nil }
        let names = (pageNames(card)).map { "[[" + $0.lowercased() }
        guard let line = text.components(separatedBy: "\n").first(where: { line in
            let lower = line.lowercased()
            return names.contains { lower.contains($0 + "]]") || lower.contains($0 + "|") }
        }) else { return nil }
        return Self.plain(line)
    }

    /// Every name a page answers to: its title and aliases.
    func pageNames(_ title: String) -> [String] {
        _ = revision
        return wiki?.entries[title]?.names ?? [title]
    }

    /// A line of Markdown as words: links as what they show, markup gone.
    static func plain(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["- [ ] ", "- [x] ", "+ [ ] ", "+ [x] ", "- ", "+ ", "* ", "> "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        text = text.replacingOccurrences(of: #"!?\[\[([^\]|]+)\|([^\]]+)\]\]"#, with: "$2", options: .regularExpression)
        text = text.replacingOccurrences(of: #"!?\[\[([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\*\*|__|`|~~|^#+ "#, with: "", options: .regularExpression)
        return text.count > 180 ? String(text.prefix(177)) + "…" : text
    }

    /// Titles for a `[[` being typed: pages by title or alias, a day when
    /// it is one — and, when nothing is called that, a new page.
    public func linkSuggestions(_ partial: String, limit: Int = 8) -> [LinkTarget] {
        let query = partial.trimmingCharacters(in: .whitespaces)
        let titles = query.isEmpty ? Array(recent().prefix(limit)) : (wiki?.search(query, limit: limit * 3) ?? [])
        var found = titles.filter { pageNames($0).contains { name in name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil } || query.isEmpty }
            .prefix(limit).map(target)
        if let day = dayTarget(query), !found.contains(day) { found.insert(day, at: 0) }
        found = Array(found.prefix(limit))
        if !query.isEmpty, !found.contains(where: { $0.title.caseInsensitiveCompare(query) == .orderedSame }), wiki?.title(for: query) == nil {
            found.append(LinkTarget(title: query, shown: query, kind: .new))
        }
        return found
    }

    /// Quick Open: pages by title or alias, then by what they say, and days
    /// — or, with nothing typed, today and the pages written last.
    public func quickOpen(_ query: String, limit: Int = 14) -> [LinkTarget] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            return [dayTarget("today")!] + recent().prefix(limit - 1).map(target)
        }
        var found = (wiki?.search(query, limit: limit) ?? []).map(target)
        if let day = dayTarget(query), !found.contains(day) { found.insert(day, at: 0) }
        return Array(found.prefix(limit))
    }

    /// A day, by its date or as today, yesterday or tomorrow.
    func dayTarget(_ text: String) -> LinkTarget? {
        let words = ["today": 0, "yesterday": -1, "tomorrow": 1]
        let title: String
        if let offset = words[text.lowercased()] {
            title = Day.today.adding(offset).description
        } else if Day(text) != nil {
            title = text
        } else {
            return nil
        }
        return LinkTarget(title: title, shown: shownTitle(title), kind: .day)
    }
}
