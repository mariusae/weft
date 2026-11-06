import Foundation
import Observation
import PrismCore
import ReflectCore
import WeftCore

/// The graph open, its wiki, and what is being written in it: the cards
/// being edited and their drafts — shown in as many rivers as are open.
@MainActor @Observable
public final class WikiStore {
    public init() {}

    public private(set) var root: URL?
    /// Every page of the graph — its days, weeks and notes — as GraphKit
    /// reads them, Prism's way.
    private var wiki: Wiki?
    // What changed, told each view in its own measure — so a save redraws
    // the card saved, the cards it links to and is tagged into, and a list
    // only while it shows — never the whole river.

    /// One page's signal: bumped when it, what links to it, or what is
    /// tagged with it changes. By the fold key of any name, so a link in
    /// other case, or to a page not yet written, hears of it too.
    @Observable final class PageSignal { var version = 0 }
    @ObservationIgnored private var signals: [String: PageSignal] = [:]
    /// A card's draft, apart from every other's: typing in one redraws its
    /// editor alone.
    @ObservationIgnored private var draftSignals: [String: PageSignal] = [:]
    /// Told when a draft's words change, apart from the rest of it: what
    /// shows its title, tags and fields is not drawn again for each key.
    @ObservationIgnored private var draftTextSignals: [String: PageSignal] = [:]
    /// Bumped when a name comes or goes; when any list of pages may read
    /// otherwise — the recent, the tags, the missing; and when anything is
    /// written, for what queries find.
    public private(set) var namesVersion = 0
    public private(set) var listsVersion = 0
    public private(set) var graphVersion = 0
    /// Bumped when any page's words change, and not only its names, tags,
    /// fields and links: for what asks the words — a `text:` query, one
    /// sorted by when pages changed, an embed.
    public private(set) var textVersion = 0

    private func signal(_ name: String) -> PageSignal {
        let key = NoteIndex.foldKey(name)
        if let signal = signals[key] { return signal }
        let signal = PageSignal()
        signals[key] = signal
        return signal
    }

    /// Reads a page's signal: what is asked next is asked again when it changes.
    private func watch(_ title: String) { _ = signal(title).version }

    private func watchDraft(_ title: String) {
        watchDraftHead(title)
        let signal = draftTextSignals[title] ?? { let made = PageSignal(); draftTextSignals[title] = made; return made }()
        _ = signal.version
    }

    private func watchDraftHead(_ title: String) {
        let signal = draftSignals[title] ?? { let made = PageSignal(); draftSignals[title] = made; return made }()
        _ = signal.version
    }

    private func draftChanged(_ title: String, wordsOnly: Bool = false) {
        if !wordsOnly { draftSignals[title]?.version += 1 }
        draftTextSignals[title]?.version += 1
    }

    /// A page changed: those that showed it are told — itself, the pages it
    /// links to (their backlinks), its tags (what they list), and, when a
    /// name came or went, every link written with it.
    private func changed(_ before: Wiki.Entry?, _ after: Wiki.Entry?) {
        guard let wiki else { return }
        // A picture shown, perhaps new: read, if it is.
        if let after, after.page.text.contains("assets/"), after.page.text != before?.page.text { pictureReader?.update() }
        var told = Set<String>()
        func tell(_ name: String) { if told.insert(NoteIndex.foldKey(name)).inserted { signal(name).version += 1 } }
        var links: [Set<String>] = []
        for entry in [before, after].compactMap({ $0 }) {
            entry.names.forEach(tell)
            let targets = WikiLinks.targets(in: entry.page.text)
            links.append(Set(targets))
            for target in targets {
                tell(target)
                if let title = wiki.title(for: target) { tell(title) }
            }
        }
        if before?.tags != after?.tags || before?.page.title != after?.page.title || before?.page[field: "list"] != after?.page[field: "list"] {
            for tag in (before?.tags ?? []) + (after?.tags ?? []) { tell(tag) }
        }
        if before?.names != after?.names { namesVersion += 1 }
        // Query rivers find again what they find — and in what order.
        if let title = after?.page.title ?? before?.page.title {
            for river in rivers where river.query != nil { river.pageChanged(title) }
        }
        listsVersion += 1
        textVersion += 1
        // What most queries ask — names, tags, fields, links — changed: they
        // run again. Words alone, as typing writes them, leave them be.
        let flags = { (entry: Wiki.Entry?) -> NoteEntry? in
            guard var note = entry?.note else { return nil }
            note.modified = .distantPast
            return note
        }
        let shape = { (entry: Wiki.Entry?) -> Page? in
            guard var page = entry?.page else { return nil }
            page.text = ""
            page.modified = nil
            return page
        }
        if before == nil || after == nil || before?.names != after?.names || before?.tags != after?.tags
            || shape(before) != shape(after) || links.first != links.last || flags(before) != flags(after) {
            graphVersion += 1
        }
    }

    /// Cards being edited, by the title they are open under, and what they say so far.
    @ObservationIgnored private var drafts: [String: Tiddler] = [:]
    /// The graph's own words, as last gathered, and for which names.
    @ObservationIgnored fileprivate var keptWords: (version: Int, words: [String])?
    /// Which cards are being edited, apart from what their drafts say: each
    /// card told of its own beginning and ending, not the river of every one.
    @ObservationIgnored public private(set) var editing: Set<String> = [] {
        didSet { for title in editing.symmetricDifference(oldValue) { draftChanged(title) } }
    }
    /// Whether renaming a card's tiddler updates what refers to it; yes
    /// unless turned off in the editor.
    public var relinkOnRename: [String: Bool] = [:]
    /// Saves waiting for typing to pause, by card.
    @ObservationIgnored private var autosaves: [String: Task<Void, Never>] = [:]
    /// Tiddlers whose file was made while they were edited.
    @ObservationIgnored private var createdWhileEditing: Set<String> = []
    /// The tags a new tiddler was made with, which alone do not make it worth a file.
    @ObservationIgnored private var schemaTags: [String: [String]] = [:]
    /// The fields a new tiddler was made with — its tags' schema, what the
    /// query river it was made in gave it — which alone do not make it worth a file.
    @ObservationIgnored private var madeFields: [String: [Tiddler.Field]] = [:]
    public var error: String?
    /// How a graph is chosen here: a folder on the Mac, a GitHub repository
    /// on the phone. Set by the app.
    public var chooseGraph: () -> Void = {}
    /// How a graph's repository is kept in step here: the `git` command
    /// line on the Mac, libgit2 and a GitHub account on the phone. Set by
    /// the app; nil for a graph in no repository.
    public var makeSync: (URL) -> WikiSync? = { _ in nil }
    /// A git of the graph for reading its history — a page's past, pages
    /// deleted — apart from the sync's.
    public var makeHistory: (URL) -> (any GitBackend)? = { _ in nil }
    public private(set) var sync: WikiSync?
    /// What each draft started from, to put together with what a sync
    /// brought in while it was written.
    private var draftBases: [String: Tiddler] = [:]
    private var lastActivation = Date.distantPast

    // MARK: The graph

    /// Whether the first launch's onboarding is done — or skipped, for a
    /// graph given with `-GraphPath`.
    public private(set) var onboarded = UserDefaults.standard.bool(forKey: "Onboarded")
        || WikiStore.isGivenGraph

    /// Whether the graph was given with `-GraphPath` — a test's, or a
    /// snapshot's: not remembered as the one to open next time, or the app
    /// opened afterwards would show that graph instead of the person's own.
    private static let isGivenGraph = ProcessInfo.processInfo.arguments.contains("-GraphPath")

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
        // Its words on disk, in this app's caches: ranked, and ready at once
        // when the graph was opened before.
        wiki.textIndex = TextIndex.shared(at: TextIndex.location(for: url, app: "Weft"))
        // What its pictures say, as read before — read here, the rest, once it is open.
        let pictures = ImageTextIndex(root: url, cache: TextIndex.cache(for: url, app: "Weft", kind: "Pictures"))
        wiki.pictures = pictures
        // The system's search told of its pages — unless asked not to, or
        // the graph was given to try something on.
        if Self.showsInSpotlight { wiki.spotlight = SpotlightIndex(root: url, app: "Weft") }
        spotlightChanges = spotlightChanges ?? NotificationCenter.default.addObserver(forName: .weftSpotlightChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.spotlightChanged() }
        }
        loads += 1
        let load = loads
        root = url.standardizedFileURL
        PastedPictures.root = root
        self.wiki = nil
        isLoading = true
        loadedRoot = nil
        for river in rivers { river.reset() }
        drafts = [:]
        editing = []
        chosenModes = [:]
        defaultModes = [:]
        linkNotes = nil
        linkNotesWaiting = []
        sync = nil
        listsVersion += 1
        Task {
            let failure: String? = await Task.detached(priority: .userInitiated) {
                do {
                    _ = pictures.refresh()
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
        wiki.onChanged = { [weak self] before, after in self?.changed(before, after) }
        // The pictures not read yet, read in the background: what they say
        // found as their pages' words once it is.
        if let pictures = wiki.pictures {
            let reader = ImageTextReader(index: pictures)
            reader.onRead = { [weak self, weak wiki] in
                DispatchQueue.main.async {
                    guard let self, let wiki, self.wiki === wiki else { return }
                    wiki.picturesRead()
                    self.listsVersion += 1
                }
            }
            pictureReader = reader
            reader.update()
        }
        if !Self.isGivenGraph { UserDefaults.standard.set(url.path, forKey: "GraphPath") }
        loadedRoot = root
        namesVersion += 1
        listsVersion += 1
        graphVersion += 1
        sync = makeSync(url)
        sync?.onPulled = { [weak self] paths in self?.pulled(paths) }
        sync?.onFinished = { [weak self] result in self?.syncFinished(result) }
        syncNow(announcing: false)
        let waiting = whenLoaded
        whenLoaded = []
        for body in waiting { body() }
    }

    /// The graph whose pages are read, once they are: the rivers show its cards then.
    public private(set) var loadedRoot: URL?
    /// Reads the text in the graph's pictures, as they come.
    @ObservationIgnored private var pictureReader: ImageTextReader?
    @ObservationIgnored private var spotlightChanges: NSObjectProtocol?

    /// Whether pages are shown in the system's search: Settings says.
    public static let spotlightKey = "Spotlight"
    static var showsInSpotlight: Bool {
        !isGivenGraph && (UserDefaults.standard.object(forKey: spotlightKey) as? Bool ?? true)
    }

    /// Settings changed: the pages told to the system's search — or taken out of it.
    private func spotlightChanged() {
        guard let wiki, let root else { return }
        if Self.showsInSpotlight {
            if wiki.spotlight == nil { wiki.spotlight = SpotlightIndex(root: root, app: "Weft") }
        } else if !Self.isGivenGraph {
            (wiki.spotlight ?? SpotlightIndex(root: root, app: "Weft")).removeAll()
            wiki.spotlight = nil
        }
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
        for river in rivers { river.timePassed() }
        syncNow(announcing: false)
    }

    // MARK: Telling how syncing goes

    /// What the foot of the river says about syncing, while it says anything.
    public enum SyncNotice: Equatable {
        case syncing
        case done(String)
        case failed(String)
    }

    public private(set) var syncNotice: SyncNotice?
    /// Whether the cycle under way was asked for here, and is told whatever it does.
    @ObservationIgnored private var announcing = false
    @ObservationIgnored private var clearing: Task<Void, Never>?

    /// Syncs now. Asked for — Sync Now, ⌘R — it says so, and then what it
    /// did; else it speaks only when something came in, or went wrong.
    public func syncNow(announcing: Bool = true) {
        guard let sync else { return }
        if announcing {
            self.announcing = true
            clearing?.cancel()
            syncNotice = .syncing
        }
        sync.sync()
    }

    /// The river pulled down: a sync, told as Sync Now's is, and waited
    /// for while the river shows it going.
    public func syncPulled() async {
        guard let sync else { return }
        announcing = true
        clearing?.cancel()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            sync.sync { _ in done.resume() }
        }
    }

    private func syncFinished(_ result: Result<SyncReport, Error>) {
        let asked = announcing
        announcing = false
        switch result {
        case .failure(let error):
            clearing?.cancel()
            syncNotice = .failed(error.localizedDescription)
            return
        case .success(let report):
            let brought = report.changed.filter(PageFolder.isPage).count
            let sent = report.parts.contains("pushed")
            // A quiet sync says nothing — and leaves what was said to go
            // as it was to.
            guard asked || brought > 0 else {
                if case .failed = syncNotice { syncNotice = nil }
                if syncNotice == .syncing { syncNotice = nil }
                return
            }
            clearing?.cancel()
            let pages = { (n: Int) in n == 1 ? "1 change" : "\(n) changes" }
            let said = switch (brought, sent) {
            case (0, false): "Up to date"
            case (0, true): "Sent your changes"
            case (let n, false): "Brought in \(pages(n))"
            case (let n, true): "Brought in \(pages(n)), sent yours"
            }
            syncNotice = .done(said)
        }
        clearing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.syncNotice = nil
        }
    }

    /// The failure said, set aside.
    public func dismissSyncNotice() {
        clearing?.cancel()
        syncNotice = nil
    }

    /// A sync wrote files: the pages among them are read again. Drafts
    /// stay as they are, to be put together with them when saved.
    public func pulled(_ paths: [String]) {
        guard let wiki else { return }
        for path in paths where PageFolder.isPage(path) { wiki.reload(path: path) }
        refreshLinkNotes(paths.filter { $0.hasSuffix(".md") })
        let saved = paths.filter { $0.hasPrefix(Self.riversFolder + "/") }
        guard !saved.isEmpty else { return }
        savedVersion += 1
        for river in rivers {
            guard let name = river.name, saved.contains(Self.riverPath(name)) else { continue }
            if let saved = savedRiver(name) { river.savedChanged(saved) } else { river.forget() }
        }
    }

    // MARK: Conflicts

    public func needsReview(_ title: String) -> Bool {
        watch(title)
        return wiki?.needsReview(title) ?? false
    }

    public func conflicted() -> [String] {
        _ = listsVersion
        return wiki?.conflicted() ?? []
    }

    /// A tiddler's text with its conflict markers, to show both sides.
    public func source(_ title: String) -> String? {
        watch(title)
        return wiki?.entries[title]?.source
    }

    public func resolve(_ title: String, keeping side: ConflictMarkers.Resolution) {
        do {
            try wiki?.resolve(title, keeping: side)
        } catch {
            self.error = "Couldn't save “\(title)”: \(error.localizedDescription)"
        }
        sync?.noteChanged()
    }

    public var graphName: String { root?.lastPathComponent ?? "Weft" }

    /// The cards a river opens with when nothing was kept of it: the
    /// graph's HelloThere, or the page written last.
    public func defaultCards() -> [String] {
        guard let wiki else { return [] }
        if wiki["HelloThere"] != nil { return ["HelloThere"] }
        let recent = wiki.recent(limit: 1)
        return recent.isEmpty ? [ShadowTiddlers.gettingStarted] : recent
    }

    /// A page's title, for any name it answers to.
    func canonicalTitle(_ title: String) -> String { wiki?.title(for: title) ?? title }

    // MARK: Reading

    public func tiddler(_ title: String) -> Tiddler? {
        watch(title)
        guard let wiki else { return nil }
        return wiki[title] ?? ShadowTiddlers.all[title]
    }

    /// Whether a title is one of weft's own tiddlers, not yet the wiki's.
    public func isShadow(_ title: String) -> Bool {
        watch(title)
        return wiki?[title] == nil && ShadowTiddlers.all[title] != nil
    }

    /// Whether a title leads anywhere: to a page, or to a day or week,
    /// written yet or not.
    public func exists(_ title: String) -> Bool { tiddler(title) != nil || Day(title) != nil || Week(title) != nil }

    /// What a page is, by where it is — a day's, a week's, or a note's —
    /// and whether it is in the wiki.
    public func kind(_ title: String) -> LinkTarget.Kind {
        watch(title)
        if Day(title) != nil || Week(title) != nil { return .day }
        if RiverLink.name(title) != nil { return .river }
        if let entry = wiki?.entries[title] {
            if case .note = entry.kind { return entry.page.isWiki ? .wiki : .note }
            return .day
        }
        if let shadow = ShadowTiddlers.all[title] { return shadow.isWiki ? .wiki : .note }
        return .new
    }

    /// How a title is shown: a day's date in words, else the title.
    public func shownTitle(_ title: String) -> String {
        if Untitled.isName(title) { return untitledName(title) ?? "Untitled" }
        if let river = RiverLink.name(title) { return river }
        guard let date = Day(title)?.date else { return title }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    /// What an untitled page is shown as, as last written: what it begins
    /// with, or "Untitled". Nil for a page with a title.
    public func untitledName(_ title: String) -> String? {
        guard Untitled.isName(title) else { return nil }
        watch(title)
        if let entry = wiki?.entries[title] { return entry.shown }
        // Not written yet: what its draft begins with.
        return drafts[title].map { Untitled.name(of: $0.text) ?? "Untitled" }
    }

    /// How often each page's words were replaced from outside its editor
    /// while it may be being written in — its first line made its title —
    /// for an editor that otherwise keeps what it has while it has the
    /// caret: it takes them anyway.
    public private(set) var replacements: [String: Int] = [:]

    func noteReplaced(_ title: String) { replacements[title, default: 0] += 1 }

    /// The title a page is to take: what is typed, or — none — untitled:
    /// as it was, if it was, else under a new name.
    func titleTaken(_ typed: String, by title: String) -> String {
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return Untitled.isName(title) ? title : wiki?.newUntitledName() ?? Untitled.newName()
    }

    /// A tiddler titled by its first line with words — that line taken
    /// out of what it says, and the blank lines after it. Nil, when it
    /// says nothing to be titled by.
    public static func titledByFirstLine(_ tiddler: Tiddler) -> Tiddler? {
        var lines = tiddler.text.components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let title = Untitled.title(from: lines[first])
        guard !title.isEmpty else { return nil }
        lines.removeSubrange(0...first)
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true, lines.count > 1 { lines.removeFirst() }
        var titled = tiddler
        titled.title = title
        titled.text = lines.joined(separator: "\n")
        if titled.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { titled.text = "" }
        return titled
    }

    /// The pages linking to a page, by any name it answers to.
    public func linking(to title: String) -> [String] {
        watch(title)
        return wiki?.backlinks(to: title) ?? []
    }

    /// The wiki's pages, by title.
    public func wikiPages() -> [String] {
        _ = listsVersion
        guard let wiki else { return [] }
        return wiki.pages(flagged: .wiki).sorted()
    }

    /// Whether a page is part of the wiki.
    public func isWiki(_ title: String) -> Bool { tiddler(title)?.isWiki ?? false }

    /// Puts a page in the wiki, or takes it out: its `wiki` flag, saved.
    // MARK: Reading

    /// Whether a page has anything to read: a link note's address, a link, a PDF.
    public func canRead(_ title: String) -> Bool {
        watch(title)
        guard let root, let text = tiddler(title)?.text, text.containsText("http") || text.containsText(".pdf") else { return false }
        // Asked each time its card is drawn: the page read once for each text it has.
        if let known = readable[title], known.text == text { return known.can }
        let can = ReaderSource.any(in: text, root: root)
        readable[title] = (text, can)
        return can
    }

    /// Whether each page asked of could be read, and for what text.
    @ObservationIgnored private var readable: [String: (text: String, can: Bool)] = [:]

    /// A passage highlighted in a page a card links to, written into the
    /// card as Prism writes it: under the link, or a link note's Highlights.
    public func highlight(_ passage: String, of address: String, in title: String) {
        guard let text = (drafts[title] ?? tiddler(title))?.text else { return }
        let marked = WebCapture.highlighting(passage, in: text, of: address)
        guard marked != text else { return }
        setText(title, marked)
    }

    /// The pages saved to read — in the inbox, with a page, not put off —
    /// oldest first, as Prism's Reading Queue has them; and when the next
    /// put off comes back.
    public func readingQueue() -> (titles: [String], next: Date?) {
        _ = listsVersion
        guard let root, let wiki else { return ([], nil) }
        guard let notes = linkNotes else {
            // Prism's index of notes, read once, then the queue again.
            prepareLinkNotes { [weak self] _ in self?.listsVersion += 1 }
            return ([], nil)
        }
        let found = ReadingQueue.items(index: notes, root: root)
        return (found.items.compactMap { wiki.entry(atPath: $0.path)?.page.title }, found.next)
    }

    /// Read, or put off: out of the queue, or back in it later.
    public func finishReading(_ title: String, snooze: ReadingQueue.Snooze? = nil) {
        change(title) { page in
            if let snooze {
                page[field: ReadingQueue.snoozeKey] = .text(ReadingQueue.written(snooze.until(from: Date())))
            } else {
                page[field: "inbox"] = nil
                page[field: ReadingQueue.snoozeKey] = nil
            }
        }
        if !river(writing: title) { finishEditing(title) }
    }

    /// A folded card's line: the first of its page's words, as words, and
    /// how many lines more it has.
    public func summary(of title: String) -> (first: String?, more: Int) {
        let text = (drafts[title] ?? tiddler(title))?.text ?? ""
        var lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("```") }
        // Its own title, as a first heading, says nothing more.
        if let head = lines.first, head.hasPrefix("# "), head.dropFirst(2).trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(shownTitle(title)) == .orderedSame {
            lines.removeFirst()
        }
        guard !lines.isEmpty else { return (nil, 0) }
        // The first line with words in it: pictures say nothing here, and an
        // address shows without its brackets.
        for (index, line) in lines.enumerated() {
            var words = line.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)(<!--.*?-->)?"#, with: "", options: .regularExpression)
            words = words.replacingOccurrences(of: #"<(https?://[^>]+)>"#, with: "$1", options: .regularExpression)
            words = Self.plain(words).trimmingCharacters(in: .whitespaces)
            if words.isEmpty || ["-", "+", "*"].contains(words) { continue }
            return (words, lines.count - 1 - index)
        }
        return (nil, lines.count)
    }

    /// A card collapsed to its peek: what it is called — an untitled one,
    /// its first line — and what it says after, as plain words run on, as
    /// much as two lines could show.
    public func peek(of title: String) -> (title: String, summary: String) {
        let text = (drafts[title] ?? tiddler(title))?.text ?? ""
        var lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("```") }
        let name = peekName(title)
        // Its own title — a first heading, or an untitled page's first line — says nothing more.
        if let head = lines.first, Untitled.title(from: head).caseInsensitiveCompare(name) == .orderedSame { lines.removeFirst() }
        var words: [String] = []
        var length = 0
        for line in lines where length < 400 {
            var plain = line.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)(<!--.*?-->)?"#, with: "", options: .regularExpression)
            plain = plain.replacingOccurrences(of: #"<(https?://[^>]+)>"#, with: "$1", options: .regularExpression)
            // A link to an untitled page, as the page begins.
            if plain.contains("[[untitled-") {
                for match in plain.matches(of: #/\[\[(untitled-[0-9a-z-]+)\]\]/#).reversed() where Untitled.isName(String(match.1)) {
                    plain.replaceSubrange(match.range, with: shownTitle(String(match.1)))
                }
            }
            plain = Self.plain(plain).trimmingCharacters(in: .whitespaces)
            // *Emphasis* and _emphasis_: the words alone.
            plain = plain.replacingOccurrences(of: #"(?<![\w*])[*_]([^*_\n]+)[*_](?![\w*])"#, with: "$1", options: .regularExpression)
            if plain.isEmpty || ["-", "+", "*"].contains(plain) { continue }
            words.append(plain)
            length += plain.count
        }
        return (name, words.joined(separator: " · "))
    }

    /// What a folded card is called: what it is called open. A title given
    /// it — in its frontmatter, or as it is being written — before what it
    /// begins with; only an untitled draft's from its words as they are now.
    func peekName(_ title: String) -> String {
        guard let draft = drafts[title] else { return shownTitle(title) }
        let given = draft.title.trimmingCharacters(in: .whitespaces)
        if !given.isEmpty, !Untitled.isName(given), given != title { return given }
        guard Untitled.isName(title), Untitled.isName(given) || given.isEmpty else { return shownTitle(title) }
        return Untitled.name(of: draft.text) ?? "Untitled"
    }

    /// The first pictures a page shows — their sources, as written — for
    /// its peek: a page of pictures alone says something, peeking.
    public func peekPictures(of title: String, limit: Int = 2) -> [String] {
        let text = (drafts[title] ?? tiddler(title))?.text ?? ""
        guard text.contains("![") else { return [] }
        return text.matches(of: #/!\[[^\]]*\]\(<?([^)\s>]+)>?/#).prefix(limit).map { String($0.1) }
    }

    // MARK: Folds

    /// Which rows of a page's outline were folded last on this device — as
    /// Prism keeps a note's: how a card opens in a river that has no folds
    /// of its own for it. A river keeps its own, as it keeps its cards.
    public func folds(of title: String) -> [OutlineFolds.Mark] {
        guard let key = foldsKey(title), let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([OutlineFolds.Mark].self, from: data)) ?? []
    }

    public func setFolds(_ marks: [OutlineFolds.Mark], of title: String) {
        guard let key = foldsKey(title) else { return }
        if marks.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(marks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// By the page's file, which a rename keeps; none for a page not yet written.
    private func foldsKey(_ title: String) -> String? {
        guard let root, let path = wiki?.entries[title]?.path else { return nil }
        return "Folds:\(root.path):\(path)"
    }

    // MARK: Related pages

    /// A page a card is related to, without a link in its text.
    public struct RelatedPage: Hashable, Sendable {
        public let title: String
        public let exists: Bool
        /// Written in this card's frontmatter — else in the other's, naming this one.
        public let isOwn: Bool
    }

    /// A card's relations, both ways — frontmatter `related:`, as Prism
    /// writes it: those it names, in order, then those naming it, by title.
    public func related(of title: String) -> [RelatedPage] {
        watch(title)
        _ = listsVersion
        var seen = Set<String>([NoteIndex.foldKey(title)])
        var found: [RelatedPage] = []
        for name in relatedNames(title) {
            let resolved = wiki?.title(for: name)
            guard seen.insert(NoteIndex.foldKey(resolved ?? name)).inserted else { continue }
            found.append(RelatedPage(title: resolved ?? name, exists: resolved != nil, isOwn: true))
        }
        for other in wiki?.relating(to: title) ?? [] where seen.insert(NoteIndex.foldKey(other)).inserted {
            found.append(RelatedPage(title: other, exists: true, isOwn: false))
        }
        return found
    }

    /// The saved river a page calls its home — its frontmatter `river:` —
    /// as its draft has it: a link's target or a name alike.
    public func homeRiver(of title: String) -> String? {
        watch(title)
        let named: String? = switch (drafts[title] ?? tiddler(title))?[field: RiverLink.homeKey] {
        case .text(let text): text
        case .list(let items): items.first
        case nil: nil
        }
        let name = named.map(Related.clean).map { RiverLink.name($0) ?? $0 }?.trimmingCharacters(in: .whitespaces)
        return name?.isEmpty == false ? name : nil
    }

    /// A page's home river set — or taken off, for nil.
    public func setHomeRiver(_ name: String?, of title: String) {
        let before = homeRiver(of: title)
        guard name != before else { return }
        change(title) { $0[field: RiverLink.homeKey] = name.map { .text($0) } }
        if !river(writing: title) { finishEditing(title) }
        undoable(name == nil ? "Remove Home River" : "Set Home River") { [weak self] in self?.setHomeRiver(before, of: title) }
    }

    /// A page's own icon — frontmatter `icon:`, an SF Symbol's name — as
    /// its draft has it; nil for none. A link's target, by any of its names.
    public func icon(of title: String) -> String? {
        let page = drafts[title] ?? tiddler(title) ?? wiki?.title(for: title).flatMap { drafts[$0] ?? tiddler($0) }
        if let own = page.flatMap(PageIcon.symbol(of:)) { return own }
        // None of its own: a captured link's, as its note in the index has it.
        let name = wiki?.title(for: title) ?? title
        return wiki?.entries[name]?.note.icon
    }

    /// What a link leads to's own icon: a saved river's, or a page's.
    public func linkIcon(_ name: String) -> String? {
        if let river = RiverLink.name(name) { return savedRiverIcon(river) }
        return icon(of: name)
    }

    /// What a page is shown with: its own icon, else its kind's.
    public func symbol(of title: String) -> String {
        icon(of: title) ?? kind(title).symbol
    }

    /// A page's icon set — or taken off, for nil.
    public func setIcon(_ symbol: String?, of title: String) {
        let before = icon(of: title)
        guard symbol != before else { return }
        change(title) { $0[field: PageIcon.key] = symbol.map { .text($0) } }
        if !river(writing: title) { finishEditing(title) }
        undoable(symbol == nil ? "Remove Icon" : "Set Icon") { [weak self] in self?.setIcon(before, of: title) }
    }

    /// The names a page's own frontmatter relates it to, as its draft has them.
    private func relatedNames(_ title: String) -> [String] {
        switch (drafts[title] ?? tiddler(title))?[field: Related.key] {
        case .list(let items): items.map(Related.clean).filter { !$0.isEmpty }
        case .text(let text): text.isEmpty ? [] : [Related.clean(text)]
        case nil: []
        }
    }

    private func setRelatedNames(_ names: [String], of title: String) {
        change(title) { $0[field: Related.key] = names.isEmpty ? nil : .list(names) }
        if !river(writing: title) { finishEditing(title) }
    }

    /// Two pages related, the relation written in the first's frontmatter.
    public func relate(_ title: String, to other: String) {
        let other = canonicalTitle(other.trimmingCharacters(in: .whitespaces))
        guard !other.isEmpty, NoteIndex.foldKey(other) != NoteIndex.foldKey(title),
              !related(of: title).contains(where: { NoteIndex.foldKey($0.title) == NoteIndex.foldKey(other) }) else { return }
        setRelatedNames(relatedNames(title) + [other], of: title)
        undoable("Relate to “\(shownTitle(other))”") { [weak self] in self?.unrelate(title, from: other, undoable: false) }
    }

    /// Two pages related no longer: taken out of whichever's frontmatter
    /// names the other.
    public func unrelate(_ title: String, from other: String, undoable: Bool = true) {
        func names(_ page: String) -> Set<String> { Set(pageNames(page).map(NoteIndex.foldKey) + [NoteIndex.foldKey(page)]) }
        let others = names(other), mine = names(title)
        var undo: [(String, [String])] = []
        for (page, removed) in [(title, others), (other, mine)] {
            let before = relatedNames(page)
            let after = before.filter { !removed.contains(NoteIndex.foldKey($0)) }
            guard after.count != before.count else { continue }
            undo.append((page, before))
            setRelatedNames(after, of: page)
        }
        guard undoable, !undo.isEmpty else { return }
        self.undoable("Unrelate “\(shownTitle(other))”") { [weak self] in
            for (page, names) in undo { self?.setRelatedNames(names, of: page) }
        }
    }

    // MARK: Prism's lenses

    /// The pages in the inbox, newest first, as Prism's Inbox lists them.
    public func inbox() -> [String] { lens(.inbox) }

    /// The pinned pages, in their order, as Prism's Pinned lists them.
    public func pinned() -> [String] { lens(.pinned) }

    private func lens(_ lens: Lens) -> [String] {
        _ = listsVersion
        guard let wiki, let query = lens.query else { return [] }
        return query.run(in: wiki, this: "")
    }

    /// Every open task in the graph — Prism's `+ [ ]` — grouped as its
    /// Tasks lens groups them: current, overdue, upcoming, then by page.
    public func taskGroups() -> [TaskGroup] {
        _ = listsVersion
        if let cached = tasksCache, cached.version == listsVersion { return cached.groups }
        guard let wiki else { return [] }
        let tasks = wiki.entries.values.flatMap { entry -> [NoteTask] in
            guard !entry.note.path.hasPrefix("templates/"), entry.page.text.containsText("+ [") else { return [] }
            return Tasks.tasks(in: entry.page.text, path: entry.note.path, entry: entry.note).filter { !$0.done }
        }
        let groups = Tasks.group(tasks, today: .today)
        tasksCache = (listsVersion, groups)
        return groups
    }

    @ObservationIgnored private var tasksCache: (version: Int, groups: [TaskGroup])?

    /// The page a task is in, by its file.
    public func title(atPath path: String) -> String? { wiki?.entry(atPath: path)?.page.title }

    /// A task ticked off, or not: written into its page.
    public func setTask(_ task: NoteTask, done: Bool) {
        guard let title = title(atPath: task.notePath),
              let text = (drafts[title] ?? tiddler(title))?.text,
              let ticked = Tasks.setting(done: done, ordinal: task.ordinal, in: text) else { return }
        setText(title, ticked)
    }

    /// A page in the inbox, or out of it: Prism's `inbox: true`.
    public func isInInbox(_ title: String) -> Bool {
        watch(title)
        return wiki?.entries[title]?.note.isInInbox ?? false
    }

    public func setInbox(_ title: String, _ inbox: Bool) {
        change(title) { $0[field: "inbox"] = inbox ? .text("true") : nil }
        if !river(writing: title) { finishEditing(title) }
    }

    /// Whether a page is itself a thing to do, and whether done: as it is
    /// being written, else as saved.
    public func taskState(_ title: String) -> Tiddler.TaskState? {
        (draftHead(title) ?? tiddler(title))?.taskState
    }

    /// A page made a thing to do, checked off — the day in `done:` — opened
    /// again, or made no longer one.
    public func setTaskState(_ title: String, _ state: Tiddler.TaskState?) {
        change(title) { page in
            page.taskState = state
            if state == .done { page[field: "done"] = .text(FieldSpec.value(of: Date())) }
        }
        if !river(writing: title) { finishEditing(title) }
    }

    /// The pages that are things still to do, the latest written first.
    public func todoPages() -> [String] {
        _ = listsVersion
        guard let wiki else { return [] }
        return wiki.pages(flagged: .todo).sorted {
            (wiki.entries[$0]?.note.modified ?? .distantPast) > (wiki.entries[$1]?.note.modified ?? .distantPast)
        }
    }

    /// A page's file, by a title a link gives it — an alias, another case —
    /// and what it says: for a link's card. Nil, a page not written yet.
    public func noteFile(_ title: String) -> (path: String, source: String)? {
        guard let entry = wiki?.entries[canonicalTitle(title)] else { return nil }
        return (entry.path, entry.source)
    }

    /// Whether a page is private, `private: true`: its links not looked up on the web.
    public func isPrivate(_ title: String) -> Bool {
        watch(title)
        return wiki?.entries[title]?.note.isPrivate ?? false
    }

    /// A page pinned — after those pinned already — or not: Prism's `pinned:`.
    public func isPinned(_ title: String) -> Bool {
        watch(title)
        return wiki?.entries[title]?.note.pin != nil
    }

    public func setPinned(_ title: String, _ pinned: Bool) {
        let next: Int = {
            let highest = wiki?.entries.values.compactMap { entry -> Double? in
                if case .order(let order) = entry.note.pin { return order }
                return nil
            }.max()
            return highest.map { min(Int($0) + 1024, Int(Int32.max)) } ?? 1024
        }()
        change(title) { $0[field: "pinned"] = pinned ? .text(String(next)) : nil }
        if !river(writing: title) { finishEditing(title) }
    }

    /// Whether a card is being written in, in any river: its draft is left
    /// to be saved when it is let go.
    func river(writing title: String) -> Bool { rivers.contains { $0.isWriting(title) } }

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

    public func backlinks(_ title: String) -> [String] {
        watch(title)
        return wiki?.backlinks(to: title) ?? []
    }

    public func tagged(_ tag: String) -> [String] {
        watch(tag)
        return wiki?.tagged(tag) ?? []
    }

    /// What a query river's query finds, in its order, each with its place.
    func riverOrder(_ query: Query) -> [(title: String, place: Query.Place)] {
        _ = graphVersion
        return wiki.map { query.ordered(in: $0) } ?? []
    }

    /// A page's place in a query river's order.
    func riverPlace(_ query: Query, of title: String) -> Query.Place? {
        wiki.map { query.place(of: title, in: $0) }
    }

    public func tags() -> [(tag: String, count: Int)] {
        _ = listsVersion
        return wiki?.tags() ?? []
    }

    public func recent() -> [String] {
        _ = listsVersion
        return wiki?.recent(limit: 100) ?? []
    }

    public func missing() -> [String] {
        _ = listsVersion
        return wiki?.missing() ?? []
    }

    /// What a query finds, asked from a tiddler.
    public func run(_ query: Query, this: String) -> [String] {
        _ = graphVersion
        // Words, or when pages changed, asked: run again for every save.
        if !query.textContains.isEmpty || query.sort == .modified { _ = textVersion }
        guard let wiki else { return [] }
        return query.run(in: wiki, this: this)
    }

    /// The fields a tiddler's tags give it.
    public func schema(for tiddler: Tiddler) -> [FieldSpec] {
        // A tag's page says its fields.
        for tag in tiddler.tags + NoteIndex.tags(in: tiddler.text) { watch(tag) }
        return wiki?.schema(for: tiddler) ?? []
    }

    /// Every title, for completing links.
    public var titles: [String] {
        _ = namesVersion
        return wiki?.titles ?? []
    }

    public var count: Int {
        _ = namesVersion
        return wiki?.entries.count ?? 0
    }

    /// Pages about what is typed, by meaning — words like its words — the
    /// nearest first, leaving out those already found.
    public func meaningHits(_ search: String, excluding found: Set<String> = [], limit: Int = 6) -> [String] {
        _ = listsVersion
        _ = textVersion
        let words = Query(search: search).textContains.trimmingCharacters(in: .whitespaces)
        guard words.count >= 3 else { return [] }
        return (wiki?.meaningMatches(words, limit: limit + found.count) ?? []).filter { !found.contains($0) }.prefix(limit).map { $0 }
    }

    /// Pages by what is typed — words, `"phrases"`, `-left out`, `#tag`,
    /// `is:todo`, `edited:today` — those named so first, then by what they
    /// say, best first: each with the lines saying it.
    public func searchHits(_ search: String, limit: Int = 60, lines: Int = 2) -> [PageIndex.TextHit] {
        _ = listsVersion
        _ = textVersion
        return wiki?.searchText(search, limit: limit, lines: lines) ?? []
    }

    /// A tiddler's file.
    public func path(of title: String) -> URL? {
        watch(title)
        guard let root, let entry = wiki?.entries[title] else { return nil }
        return root.appendingPathComponent(entry.path)
    }

    /// A picture's file in the graph, for a source like `assets/cat.png`.
    public func file(_ source: String) -> URL? {
        guard let root, !source.contains("://"), !source.hasPrefix("/") else { return nil }
        let path = source.removingPercentEncoding ?? source
        return root.appendingPathComponent(path)
    }

    // MARK: Writing

    /// Every card is written in where it stands — there is no Edit and no
    /// Preview. One being written has a draft, begun with its first change:
    /// what it says, its title, tags and fields, as typed — saved a moment
    /// after typing pauses. When the caret leaves the card the draft is
    /// written and let go, and a new title takes effect.
    public func isEditing(_ title: String) -> Bool {
        watchDraftHead(title)
        return editing.contains(title)
    }

    /// Cards whose other fields are shown.
    public var fieldsShown: Set<String> = []

    /// Changes what a card says — its body, tags or fields — beginning its
    /// draft if this is the first change.
    public func change(_ title: String, _ change: (inout Tiddler) -> Void) {
        beginDraft(title)
        guard var draft = drafts[title] else { return }
        change(&draft)
        updateDraft(title, draft)
    }

    private func beginDraft(_ title: String) {
        guard drafts[title] == nil else { return }
        drafts[title] = tiddler(title) ?? Tiddler(title: title)
        editing.insert(title)
        draftBases[title] = wiki?[title]
        draftChanged(title)
    }

    // MARK: Rivers

    private struct Held { weak var river: River? }
    @ObservationIgnored private var held: [Held] = []

    /// The rivers open: a tab's each, on the Mac; the phone's.
    public var rivers: [River] { held.compactMap(\.river) }

    /// A river opened: told what changes the graph — a page renamed or
    /// deleted, the graph changed.
    public func adopt(_ river: River) {
        held.removeAll { $0.river == nil || $0.river === river }
        held.append(Held(river: river))
    }

    /// A river closed: what it was writing in, written; the cards only it
    /// had open, closed.
    public func release(_ river: River) {
        held.removeAll { $0.river == nil || $0.river === river }
        for title in river.cards { cardClosed(title) }
    }

    /// A river closed a card: unless another has it open, its draft is
    /// written and let go.
    func cardClosed(_ title: String) {
        guard !rivers.contains(where: { $0.cards.contains(title) }) else { return }
        if isEditing(title) { finishEditing(title, closing: true) }
        dropDraft(title)
    }

    private func dropDraft(_ title: String) {
        drafts[title] = nil
        draftChanged(title)
        editing.remove(title)
        draftBases[title] = nil
    }

    /// The cards the Mac's window opens with when it kept none of its own:
    /// those of the river changed last, per graph, on this device.
    public var lastRiver: [String]? {
        get { UserDefaults.standard.stringArray(forKey: "River:\(root?.path ?? "")") }
        set { UserDefaults.standard.set(newValue, forKey: "River:\(root?.path ?? "")") }
    }

    // MARK: Saved rivers

    /// Saved rivers are files in the graph's `rivers/` folder — one a name,
    /// a link to each card a line — synced with the rest. They are not
    /// pages: nothing links to them, and no search finds them.
    static let riversFolder = RiverLink.folder

    static func riverPath(_ name: String) -> String { RiverLink.path(name) }

    /// Bumped when a saved river comes, goes, or changes.
    public private(set) var savedVersion = 0 {
        didSet { savedCardsKept = nil }
    }
    /// Each saved river's cards, read once and kept until a river changes.
    @ObservationIgnored private var savedCardsKept: [String: [String]]?

    /// The saved rivers a page is a card of, by name.
    public func rivers(holding title: String) -> [String] {
        _ = savedVersion
        let kept = savedCardsKept ?? Dictionary(uniqueKeysWithValues: savedRivers().map { ($0, savedCards($0) ?? []) })
        savedCardsKept = kept
        return kept.filter { $0.value.contains(title) }.map(\.key)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The pages linking to a saved river.
    public func linking(toRiver name: String) -> [String] {
        _ = graphVersion
        return wiki?.backlinks(to: RiverLink.target(name)) ?? []
    }

    private func riverFile(_ name: String) -> URL? {
        root?.appendingPathComponent(Self.riverPath(name))
    }

    /// A name a file can have: no slashes or colons, no dot to begin it.
    private static func riverName(_ name: String) -> String? {
        var name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while name.hasPrefix(".") { name.removeFirst() }
        return name.isEmpty ? nil : name
    }

    /// The saved rivers, by name.
    public func savedRivers() -> [String] {
        let version = savedVersion
        guard let root else { return [] }
        // Asked by every card as it is drawn: the folder read again only once it changed.
        if let known = savedRiversRead, known.version == version, known.root == root { return known.names }
        let folder = root.appendingPathComponent(Self.riversFolder)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let names = files.filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        savedRiversRead = (version, root, names)
        return names
    }

    @ObservationIgnored private var savedRiversRead: (version: Int, root: URL, names: [String])?

    /// A saved river — its cards, and what is folded of them — as its file has it.
    func savedRiver(_ name: String) -> SavedRiver? {
        guard let file = riverFile(name), let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return SavedRiver(text: text)
    }

    /// A saved river's cards, as its file has them.
    public func savedCards(_ name: String) -> [String]? { savedRiver(name)?.cards }

    private func writeSavedRiver(_ name: String, _ river: SavedRiver) -> Bool {
        guard let file = riverFile(name) else { return false }
        let text = river.text
        if (try? String(contentsOf: file, encoding: .utf8)) == text { return true }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            self.error = "Couldn't save the river “\(name)”: \(error.localizedDescription)"
            return false
        }
        savedVersion += 1
        sync?.noteChanged()
        return true
    }

    /// A river's cards changed, or what is folded of them: its file says so.
    func keepSavedRiver(_ name: String, _ river: SavedRiver) {
        _ = writeSavedRiver(name, river)
    }

    /// A river saved under a name no other has. The name it was saved under.
    func addSavedRiver(_ name: String, _ river: SavedRiver) -> String? {
        guard let name = Self.riverName(name) else { return nil }
        guard !savedRivers().contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            error = "There is already a river called “\(name)”."
            return nil
        }
        guard writeSavedRiver(name, river) else { return nil }
        savedVersion += 1
        return name
    }

    /// A saved river's icon, as its file has it: nil for none. Read once
    /// for each change to the saved rivers, as links to them are drawn.
    public func savedRiverIcon(_ name: String) -> String? {
        let version = savedVersion &+ riverIconsVersion
        if riverIcons.version != version { riverIcons = (version, [:]) }
        if let known = riverIcons.icons[name] { return known }
        let icon = savedRiver(name)?.icon
        riverIcons.icons[name] = .some(icon)
        return icon
    }

    @ObservationIgnored private var riverIcons: (version: Int, icons: [String: String?]) = (-1, [:])
    /// Bumped as a river's icon is chosen: what shows it, drawn again.
    private var riverIconsVersion = 0

    func savedRiverIconChanged() { riverIconsVersion += 1 }

    /// A saved river's icon set, whether or not it is open.
    public func setSavedRiverIcon(_ name: String, _ symbol: String?) {
        if let open = river(named: name) { open.setIcon(symbol); return }
        guard var saved = savedRiver(name), saved.icon != symbol else { return }
        let before = saved.icon
        saved.icon = symbol
        keepSavedRiver(name, saved)
        savedRiverIconChanged()
        undoable(symbol == nil ? "Remove River Icon" : "Set River Icon") { [weak self] in self?.setSavedRiverIcon(name, before) }
    }

    /// A query river saved under a name no other has: what it finds, and
    /// how it shows. The name it was saved under.
    public func addQueryRiver(_ name: String, query: Query, icon: String?, color: String?) -> String? {
        addSavedRiver(name, SavedRiver(cards: [], query: query, icon: icon, color: color))
    }

    /// A copy of a saved river, under a new name — not opened.
    public func cloneSavedRiver(_ name: String, as new: String) {
        guard let river = savedRiver(name) else { return }
        _ = addSavedRiver(new, river)
    }

    /// A name for a copy of a saved river: “Work copy”, “Work copy 2”…
    public func cloneName(_ name: String) -> String {
        let names = Set(savedRivers().map { $0.lowercased() })
        var candidate = "\(name) copy"
        var number = 2
        while names.contains(candidate.lowercased()) {
            candidate = "\(name) copy \(number)"
            number += 1
        }
        return candidate
    }

    /// Gives a saved river another name — and the river showing it. The new name.
    @discardableResult
    public func renameSavedRiver(_ name: String, to new: String) -> String? {
        guard let new = Self.riverName(new), let from = riverFile(name), let to = riverFile(new) else { return nil }
        guard new != name else { return name }
        if new.caseInsensitiveCompare(name) != .orderedSame,
           savedRivers().contains(where: { $0.caseInsensitiveCompare(new) == .orderedSame }) {
            error = "There is already a river called “\(new)”."
            return nil
        }
        do {
            try FileManager.default.moveItem(at: from, to: to)
        } catch {
            self.error = "Couldn't rename the river “\(name)”: \(error.localizedDescription)"
            return nil
        }
        for river in rivers where river.name == name { river.named(new) }
        // Links to it follow it, as links to a page renamed do.
        do {
            _ = try wiki?.relink(from: RiverLink.target(name), to: RiverLink.target(new))
        } catch {
            self.error = "Couldn't update the links to the river “\(name)”: \(error.localizedDescription)"
        }
        savedVersion += 1
        sync?.noteChanged()
        return new
    }

    /// Deletes a saved river's file. A river showing it stays open, kept on
    /// this device alone.
    public func deleteSavedRiver(_ name: String) {
        guard let file = riverFile(name) else { return }
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            self.error = "Couldn't delete the river “\(name)”: \(error.localizedDescription)"
            return
        }
        for river in rivers where river.name == name { river.forget() }
        savedVersion += 1
        sync?.noteChanged()
    }

    /// A saved river by a name as a link writes it, in whatever case: its
    /// name, or nil when none is called that.
    public func savedRiverName(_ name: String) -> String? {
        savedRivers().first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Whether a link leads somewhere: to a page, a day, a saved river.
    public func linkExists(_ target: String) -> Bool {
        if let name = RiverLink.name(target) { return savedRiverName(name) != nil }
        return exists(target)
    }

    /// What is said of a link to a saved river, under the pointer: its
    /// cards, or that none is called that.
    public func riverNote(_ target: String) -> String? {
        guard let name = RiverLink.name(target) else { return nil }
        guard let saved = savedRiverName(name), let cards = savedCards(saved) else { return "No saved river is called “\(name)”" }
        let shown = cards.prefix(6).map(shownTitle).joined(separator: ", ")
        return "Saved river “\(saved)” — \(cards.count) \(cards.count == 1 ? "card" : "cards")" + (cards.isEmpty ? "" : ": \(shown)\(cards.count > 6 ? "…" : "")")
    }

    /// The river showing a saved one, if one does.
    public func river(named name: String) -> River? {
        rivers.first { $0.name == name }
    }

    /// Changes the cards of the saved rivers no river shows — the ones
    /// shown change with their river.
    private func reviseSavedRivers(_ change: (SavedRiver) -> SavedRiver) {
        for name in savedRivers() where river(named: name) == nil {
            guard let saved = savedRiver(name) else { continue }
            let revised = change(saved)
            if revised != saved { _ = writeSavedRiver(name, revised) }
        }
    }

    // MARK: Undoing what is not typing

    /// The window's undo: what is done to pages and cards — a page deleted,
    /// a tag or field taken off, cards closed — undone there, as typing is.
    /// Where the window gives none, the store's own, which the offer undoes.
    @ObservationIgnored public weak var undoManager: UndoManager?
    @ObservationIgnored private let ownUndo = UndoManager()
    private var undo: UndoManager { undoManager ?? ownUndo }
    /// What was just done that can be undone, offered a moment over the river.
    public private(set) var undoOffer: String?
    @ObservationIgnored private var offerClearing: Task<Void, Never>?

    /// Something done, to undo: kept with the window's undo, and offered.
    /// What was done, as the offer to undo it says it: the menu's
    /// “Close …”, “Remove …” told as done — “Closed …”, “Removed …”.
    static func done(_ name: String) -> String {
        let pasts = ["Close": "Closed", "Remove": "Removed", "Delete": "Deleted", "Restore": "Restored", "Relate": "Related",
                     "Unrelate": "Unrelated", "Set": "Set"]
        guard let space = name.firstIndex(of: " "), let past = pasts[String(name[..<space])] else { return name }
        return past + name[space...]
    }

    public func undoable(_ name: String, _ action: @escaping @MainActor () -> Void) {
        undo.registerUndo(withTarget: self) { _ in MainActor.assumeIsolated { action() } }
        undo.setActionName(name)
        offer(name)
    }

    private func offer(_ name: String) {
        offerClearing?.cancel()
        undoOffer = Self.done(name)
        offerClearing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.undoOffer = nil
        }
    }

    /// The offer taken: what was just done, undone.
    public func takeUndoOffer() {
        offerClearing?.cancel()
        undoOffer = nil
        if undo.canUndo { undo.undo() }
    }

    public func dismissUndoOffer() {
        offerClearing?.cancel()
        undoOffer = nil
    }

    // MARK: Text or Outline

    /// How a card's body is edited: as an outline — in Prism's outline
    /// editor — wherever one would write it back as it was, unless text is
    /// asked for.
    public enum EditorMode: String, CaseIterable, Sendable {
        case text = "Text", outline = "Outline"

        /// What the switch in a card's header shows for it.
        public var symbol: String {
            switch self {
            case .text: "text.alignleft"
            case .outline: "list.bullet.indent"
            }
        }
    }

    /// Cards switched from how they would be edited, by title: each card
    /// told of its own, through its signal.
    @ObservationIgnored private var chosenModes: [String: EditorMode] = [:]
    /// How each other card is edited, and the text that decided it: kept
    /// while it is written in, so a card does not change editor under the caret.
    @ObservationIgnored private var defaultModes: [String: (text: String, mode: EditorMode)] = [:]

    public func editorMode(_ title: String) -> EditorMode {
        watch(title)
        if let chosen = chosenModes[title] { return chosen }
        let text = (drafts[title] ?? tiddler(title))?.text ?? ""
        if let known = defaultModes[title], known.text == text || editing.contains(title) { return known.mode }
        let mode: EditorMode = canOutline(text) ? .outline : .text
        defaultModes[title] = (text, mode)
        return mode
    }

    public func setEditorMode(_ mode: EditorMode, for title: String) {
        if mode == .outline {
            // An outline only of what it would write back as it was.
            let text = (drafts[title] ?? tiddler(title))?.text ?? ""
            guard canOutline(text) else {
                error = "“\(shownTitle(title))” can't be edited as an outline without changing how it's written."
                return
            }
        }
        chosenModes[title] = mode
        signal(title).version += 1
    }

    /// Whether a body can be edited as an outline: whether the outline
    /// would write it back as it is.
    private func canOutline(_ text: String) -> Bool {
        !text.contains(OutlineText.lineSeparator) && OutlineMarkdown.serialize(OutlineMarkdown.parse(text)) == text
    }

    /// The graph's pages, for an outline's queries and embeds to ask.
    public var pages: PageIndex? {
        _ = graphVersion
        return wiki
    }

    /// Every note by name, as Prism's index has them — for an outline's
    /// `[[` to complete from — read off the main thread once asked for.
    @ObservationIgnored public private(set) var linkNotes: NoteIndex?

    /// Told when the notes are read: every outline card asks as it is
    /// made, and the graph is read for them once.
    @ObservationIgnored private var linkNotesWaiting: [@MainActor (NoteIndex) -> Void] = []

    public func prepareLinkNotes(_ ready: @escaping @MainActor (NoteIndex) -> Void) {
        if let linkNotes { return ready(linkNotes) }
        guard let root else { return }
        linkNotesWaiting.append(ready)
        guard linkNotesWaiting.count == 1 else { return }
        let notes = NoteIndex(root: root)
        Task {
            // After the first cards are drawn, and out of their way.
            try? await Task.sleep(for: .seconds(1.5))
            await Task.detached(priority: .utility) { notes.scan() }.value
            guard self.root == root else { return }
            linkNotes = notes
            let waiting = linkNotesWaiting
            linkNotesWaiting = []
            for ready in waiting { ready(notes) }
        }
    }

    /// Notes written or synced, read again for `[[` — off the main thread.
    private func refreshLinkNotes(_ paths: [String]) {
        guard let notes = linkNotes, !paths.isEmpty else { return }
        Task.detached(priority: .utility) { for path in paths { notes.refresh(path) } }
    }

    public func draft(_ title: String) -> Tiddler? {
        watchDraft(title)
        return drafts[title]
    }

    /// A card's draft, asked again only when what is not its words
    /// changes — its title, tags, fields: for what shows those. Its text,
    /// read from this, is as it was when last asked.
    public func draftHead(_ title: String) -> Tiddler? {
        watchDraftHead(title)
        return drafts[title]
    }

    public func updateDraft(_ title: String, _ tiddler: Tiddler) {
        let before = drafts[title]
        drafts[title] = tiddler
        // Emptied, or no longer empty: what shows a placeholder is told.
        draftChanged(title, wordsOnly: before.map { Self.sameButWords($0, tiddler) && $0.text.isEmpty == tiddler.text.isEmpty } ?? false)
        autosaves[title]?.cancel()
        // A big page takes a while to write and index: written after a
        // longer pause, so typing in it is not stopped short as often.
        let pause = tiddler.text.utf8.count > 30_000 ? 2.5 : 0.8
        autosaves[title] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(pause))
            guard !Task.isCancelled else { return }
            self?.autosave(title)
        }
    }

    private static func sameButWords(_ a: Tiddler, _ b: Tiddler) -> Bool {
        var a = a, b = b
        a.text = ""
        b.text = ""
        return a == b
    }

    /// Writes what every card being edited says, now: before the app goes
    /// to the background, or quits.
    public func saveEditing() {
        // What editors hold back as typing goes on, told first.
        NotificationCenter.default.post(name: .weftFlushEdits, object: nil)
        for title in editing {
            // A title given it and not yet taken — its first line made its
            // title, that line gone from what it says — taken now: the app
            // may not come back to take it.
            if let typed = drafts[title]?.title.trimmingCharacters(in: .whitespacesAndNewlines), !typed.isEmpty, typed != title {
                finishEditing(title)
            } else {
                autosave(title)
            }
        }
    }

    /// A new tiddler with nothing in it yet, which is not worth a file.
    private func isUntouched(_ title: String, _ draft: Tiddler) -> Bool {
        wiki?[title] == nil && draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (draft.fields.allSatisfy { $0.value.text?.isEmpty ?? ($0.value.list?.isEmpty ?? true) } || draft.fields == madeFields[title])
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
        if write(tiddler, from: title) {
            draftBases[title] = wiki?[title]
            // What writing it gave it — an id and its times, made new — kept
            // in the draft too: else the draft, written again, takes them out.
            if let saved = wiki?[title], var draft = drafts[title] {
                draft.id = draft.id ?? saved.id
                draft.created = draft.created ?? saved.created
                draft.modified = saved.modified
                drafts[title] = draft
            }
        }
    }

    /// Back to Preview: the draft written, a new title taken — with what
    /// referred to it updated, unless asked not to — and the card read again.
    public func finishEditing(_ title: String, closing: Bool = false) {
        autosaves[title]?.cancel()
        autosaves[title] = nil
        guard let wiki, var tiddler = drafts[title] else { return }
        // Made and left empty — no title given it either — it goes, card and all.
        if isUntouched(title, tiddler), tiddler.title == title || Untitled.isName(tiddler.title) || tiddler.title.trimmingCharacters(in: .whitespaces).isEmpty {
            drafts[title] = nil
            draftChanged(title)
            editing.remove(title)
            draftBases[title] = nil
            // Quietly: nothing was made, so nothing is offered to undo.
            if !closing, !exists(title) { for river in rivers { river.close(title, quietly: true) } }
            return
        }
        // No title: untitled — again, its title taken away.
        tiddler.title = titleTaken(tiddler.title, by: title)
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
        draftChanged(title)
        editing.remove(title)
        draftBases[title] = nil
        createdWhileEditing.remove(title)
        if tiddler.title != title {
            for river in rivers { river.renamed(title, to: tiddler.title) }
            reviseSavedRivers { $0.renaming(title, to: tiddler.title) }
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
            refreshLinkNotes([entry.path])
        } catch {
            self.error = "Couldn't save “\(tiddler.title)”: \(error.localizedDescription)"
            return false
        }
        if !existed { createdWhileEditing.insert(title) }
        sync?.noteChanged()
        return true
    }

    /// Changes one of a tiddler's query blocks, from its card, and saves it.
    /// Rows moved from a card to a day — Do Today, Later… — put at the top
    /// of that day's page, as Prism puts them; undone with the card's undo.
    public func add(_ rows: [Row], toDay day: Day, undo: UndoManager) {
        let title = day.description
        let before = (drafts[title] ?? tiddler(title))?.text ?? ""
        let after = RowMove.adding(rows, to: before, path: GraphPaths.dailyPath(for: day))
        setText(title, after)
        undo.registerUndo(withTarget: self) { store in
            // Changed since: not undone over it.
            guard (store.drafts[title] ?? store.tiddler(title))?.text == after else { return }
            store.setText(title, before)
        }
    }

    /// A page's words, set from outside its editor: written now, unless its
    /// card is being written in, whose draft takes them.
    private func setText(_ title: String, _ text: String) {
        let wasEditing = editing.contains(title)
        change(title) { $0.text = text }
        if !wasEditing { finishEditing(title) }
    }

    public func updateQuery(in title: String, at index: Int, to query: Query) {
        guard var tiddler = tiddler(title) else { return }
        tiddler.text = MarkdownBlock.replacingQuery(at: index, in: tiddler.text, with: query)
        tiddler.modified = Date()
        do {
            try wiki?.save(tiddler)
        } catch {
            self.error = "Couldn't save “\(title)”: \(error.localizedDescription)"
        }
        sync?.noteChanged()
    }

    /// The tiddlers naming a title: linking, tagging, listing, asking for it.
    public func references(to title: String) -> [String] {
        _ = graphVersion
        return wiki?.references(to: title) ?? []
    }

    /// Takes a tiddler out, and its card. Its file goes; the history keeps it.
    public func delete(_ title: String) {
        let page = tiddler(title)
        let places = rivers.compactMap { river in river.cards.firstIndex(of: title).map { (river, $0) } }
        do {
            try wiki?.delete(title)
        } catch {
            self.error = "Couldn't delete “\(title)”: \(error.localizedDescription)"
            return
        }
        if let page {
            undoable("Delete “\(shownTitle(title))”") { [weak self] in
                guard let self, wiki?[title] == nil else { return }
                do {
                    try wiki?.save(page)
                } catch {
                    self.error = "Couldn't bring back “\(title)”: \(error.localizedDescription)"
                    return
                }
                for (river, index) in places { river.reopen(title, at: index) }
                sync?.noteChanged()
            }
        }
        for river in rivers { river.removed(title) }
        dropDraft(title)
        reviseSavedRivers { $0.removing(title) }
        sync?.noteChanged()
    }

    /// A new tiddler's draft — tagged with `tag`, when there is one, and
    /// given its fields; called `name`, and saying `text`, when it is
    /// made of something — under a title no page and no card has. Its title.
    func makeTiddler(taggedWith tag: String? = nil, named name: String? = nil, text: String = "", untitled: Bool = false,
                     seed: Query? = nil) -> String? {
        guard let wiki else { return nil }
        var title = untitled ? wiki.newUntitledName() : name ?? tag.map { "New \($0)" } ?? "New Tiddler"
        let base = title
        var number = 1
        while exists(title) || rivers.contains(where: { $0.cards.contains(title) }) {
            title = "\(base) \(number)"
            number += 1
        }
        var tiddler = Tiddler(title: title, tags: tag.map { [$0] } ?? [], text: text)
        // What Weft makes is the wiki's — but a jot, untitled, till it is named.
        tiddler.isWiki = !untitled
        // Made in a query river: filled in to be one of what it finds.
        if let seed { tiddler = seed.seeded(tiddler) }
        for spec in schema(for: tiddler) where tiddler[field: spec.name] == nil { tiddler[field: spec.name] = .text("") }
        schemaTags[title] = tiddler.tags
        madeFields[title] = tiddler.fields
        drafts[title] = tiddler
        editing.insert(title)
        draftChanged(title)
        return title
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
    /// Its page's own icon, when it has one.
    public var icon: String? = nil

    /// What it is shown with: its page's own icon, else its kind's.
    public var symbol: String { icon ?? kind.symbol }

    public enum Kind: Sendable {
        case wiki, note, day, river, new
        /// Not a page: every page searched for what is typed, as a river.
        case search

        public var symbol: String {
            switch self {
            case .wiki: "book.closed"
            case .note: "doc.text"
            case .day: "calendar"
            case .river: RiverLink.symbol
            case .new: "plus.circle"
            case .search: "text.magnifyingglass"
            }
        }

        public var label: String {
            switch self {
            case .wiki: "Wiki"
            case .note: "Note"
            case .day: "Day"
            case .river: "River"
            case .new: "New page"
            case .search: "Search"
            }
        }
    }
}

extension WikiStore {
    /// What a title leads to, as a link to it would.
    public func target(_ title: String) -> LinkTarget {
        let title = wiki?.title(for: title) ?? title
        return LinkTarget(title: title, shown: shownTitle(title), kind: kind(title), icon: icon(of: title))
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

    /// The graph's own words, its spelling not to be corrected: every word
    /// of every page's name and alias, and Weft's — kept until names change.
    public var ownWords: [String] {
        if let kept = keptWords, kept.version == namesVersion { return kept.words }
        var words: Set<String> = ["tiddler", "tiddlers", "Tiddler", "Tiddlers", "Weft", "TiddlyWiki"]
        for entry in wiki?.entries.values.map({ $0 }) ?? [] {
            for name in entry.names {
                for word in name.split(whereSeparator: { !$0.isLetter && $0 != "'" }) where word.count > 1 {
                    words.insert(String(word))
                }
            }
        }
        let sorted = words.sorted()
        keptWords = (namesVersion, sorted)
        return sorted
    }

    /// Every name a page answers to: its title and aliases.
    func pageNames(_ title: String) -> [String] {
        watch(title)
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
        var found = titles.filter { (pageNames($0) + (Untitled.isName($0) ? [shownTitle($0)] : [])).contains { name in name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil } || query.isEmpty }
            .prefix(limit).map(target)
        if let day = dayTarget(query), !found.contains(day) { found.insert(day, at: 0) }
        // Saved rivers the words name, kept a place among the pages.
        let rivers = root.map { RiverLink.matching(query, in: $0, limit: 2) } ?? []
        found = Array(found.prefix(limit - rivers.count)) + rivers.map(riverTarget)
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
            // Today first — not again among the pages written last, when it is one.
            let today = dayTarget("today")!
            return [today] + recent().map(target).filter { $0.title != today.title }.prefix(limit - 1)
        }
        var found = (wiki?.search(query, limit: limit) ?? []).map(target)
        // Saved rivers the words name, among the best pages.
        if let root { found.insert(contentsOf: RiverLink.matching(query, in: root, limit: 3).map(riverTarget), at: min(3, found.count)) }
        if let day = dayTarget(query), !found.contains(day) {
            found.insert(day, at: 0)
        } else if let day = DayQuery.day(query).map({ dayTarget($0.description)! }), !found.contains(day) {
            // `friday`, `next week`, `3 days ago`, `Jan 3`: the day, after what is called that.
            found.insert(day, at: min(1, found.count))
        }
        return Array(found.prefix(limit))
    }

    /// A saved river, as a link leads to it: `rivers/Work`, shown as Work.
    func riverTarget(_ name: String) -> LinkTarget {
        LinkTarget(title: RiverLink.target(name), shown: name, kind: .river, icon: savedRiverIcon(name))
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
        return LinkTarget(title: title, shown: shownTitle(title), kind: .day, icon: icon(of: title))
    }
}

extension Notification.Name {
    /// Editors: what was typed and not yet told, told now — the app is
    /// about to write what is being edited.
    public static let weftFlushEdits = Notification.Name("WeftFlushEdits")
    /// Settings changed whether pages are shown in the system's search.
    public static let weftSpotlightChanged = Notification.Name("WeftSpotlightChanged")
}
