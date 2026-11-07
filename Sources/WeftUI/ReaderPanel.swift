import PrismCore
import ReflectCore
import SwiftUI
import WebKit

/// A card's pages read, as Prism reads them: each address it has — a link
/// note's own first, then every other link and PDF — its words alone, set
/// for reading, or the site itself; where it was read to kept; a passage
/// highlighted written back into the card, under the link, and marked
/// again whenever the page is read. On the Mac beside the river; on the
/// phone over it.
struct ReaderPanel: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    /// The card whose pages these are.
    let title: String
    @State private var index = 0
    @State private var reading = true
    @State private var web = ReaderWeb()

    private var sources: [ReaderSource] {
        guard let root = store.root, let text = store.tiddler(title)?.text else { return [] }
        return ReaderSource.all(in: text, root: root)
    }

    var body: some View {
        let sources = sources
        let source = sources.indices.contains(index) ? sources[index] : nil
        VStack(spacing: 0) {
            bar(sources, source)
            Divider()
            if let source {
                ReaderWebView(web: web)
                    .task(id: "\(source.url) \(reading)") { web.show(source, reading: reading && !source.isPDF, marks: highlights(source)) }
                    .overlay(alignment: .bottom) { if store.isInInbox(title) { queueBar } }
            } else {
                ContentUnavailableView("Nothing to Read", systemImage: "doc.richtext",
                                       description: Text("“\(store.shownTitle(title))” links to no page."))
            }
        }
        .background(Color.card)
        .onAppear { reading = sources.first.map { ReaderPlace.reads($0.url) || !ReaderPlace.hasChosen($0.url) } ?? true }
        .onChange(of: title) { index = 0 }
    }

    private func bar(_ sources: [ReaderSource], _ source: ReaderSource?) -> some View {
        HStack(spacing: 14) {
            Button { river.reading = nil } label: { Image(systemName: "xmark") }
                .help("Close the Reader")
            if sources.count > 1 {
                Button { index = max(0, index - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(index == 0)
                    .help("The page before")
                Button { index = min(sources.count - 1, index + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(index >= sources.count - 1)
                    .help("The next page")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(web.title ?? source?.name ?? store.shownTitle(title))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if let source {
                    Text(source.url.host() ?? source.name)
                        .font(.caption)
                        .foregroundStyle(Ink.secondary.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let source {
                Button { highlight(source) } label: { Image(systemName: "highlighter") }
                    .help("Highlight the words chosen, into “\(store.shownTitle(title))”")
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                if !source.isPDF {
                    Button {
                        reading.toggle()
                        ReaderPlace.setReads(reading, for: source.url)
                    } label: { Image(systemName: reading ? "doc.plaintext.fill" : "doc.plaintext") }
                        .help(reading ? "Show the Site" : "Show Its Words Alone")
                }
                if source.isOnline {
                    Link(destination: source.url) { Image(systemName: "safari") }
                        .help("Open in the Browser")
                }
            }
        }
        .buttonStyle(.plain)
        .pointing()
        .foregroundStyle(Ink.accent.color)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// A page saved to read: done with it, or put off — as Prism's queue
    /// has it — and the next in the queue read, if there is one.
    private var queueBar: some View {
        HStack(spacing: 18) {
            Menu {
                ForEach(ReadingQueue.Snooze.allCases, id: \.self) { snooze in
                    Button(snooze.title, systemImage: snooze.symbol) { finish(snooze) }
                }
            } label: {
                Label("Later", systemImage: "clock")
            }
            Divider().frame(height: 18)
            Button { finish(nil) } label: { Label("Done", systemImage: "checkmark") }
        }
        .font(.callout.weight(.medium))
        .buttonStyle(.plain)
        .pointing()
        .foregroundStyle(Ink.accent.color)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.bottom, 18)
    }

    private func finish(_ snooze: ReadingQueue.Snooze?) {
        store.finishReading(title, snooze: snooze)
        let next = store.readingQueue().titles.first { $0 != title }
        if let next {
            river.open(next)
            river.reading = next
        } else {
            river.reading = nil
        }
    }

    private func highlights(_ source: ReaderSource) -> [String] {
        WebCapture.highlights(in: store.tiddler(title)?.text ?? "", of: source.address)
    }

    /// The words chosen, marked in the page and written into the card.
    private func highlight(_ source: ReaderSource) {
        web.highlight { passage in
            guard !passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            store.highlight(passage, of: source.address, in: title)
        }
    }
}

extension ReaderPlace {
    /// Whether words alone or the site was ever chosen for a page: words
    /// alone, until it was.
    static func hasChosen(_ url: URL) -> Bool { UserDefaults.standard.object(forKey: "Reader.reads." + url.absoluteString) != nil }
}

/// The reader's web view and what it does: kept by the panel, shown by
/// `ReaderWebView`.
@MainActor @Observable
final class ReaderWeb: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    /// The page's title, once its words are in.
    var title: String?
    @ObservationIgnored let view: WKWebView
    @ObservationIgnored private var shown: (url: URL, reading: Bool)?
    @ObservationIgnored private var marks: [String] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        view = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        let content = configuration.userContentController
        content.addUserScript(ReaderPage.userScript)
        for name in ["scrolled", "moved", "pinned"] { content.add(WeakMessages(self), name: name) }
        view.navigationDelegate = self
        #if os(macOS)
        view.setValue(false, forKey: "drawsBackground")
        #else
        view.isOpaque = false
        view.backgroundColor = .clear
        #endif
    }

    /// A page shown: its words alone, fetched once and kept, or the site.
    func show(_ source: ReaderSource, reading: Bool, marks: [String]) {
        guard shown?.url != source.url || shown?.reading != reading else { return }
        shown = (source.url, reading)
        self.marks = marks
        title = nil
        guard reading else {
            view.load(URLRequest(url: source.url))
            return
        }
        let present: (ReaderArticle?) -> Void = { [weak self] article in
            guard let self, self.shown?.url == source.url else { return }
            guard let article else {
                // No words to take out: the site, then.
                self.view.load(URLRequest(url: source.url))
                return
            }
            self.title = article.title
            self.view.loadHTMLString(ReaderPage.html(article, style: .current, paper: Self.paper), baseURL: source.url)
        }
        if let cached = ReaderArticle.cached(source.url) { present(cached) } else { ReaderArticle.fetch(source.url, done: present) }
    }

    func highlight(_ done: @escaping (String) -> Void) {
        view.evaluateJavaScript("prismHighlight()") { result, _ in
            if let passage = result as? String { done(passage) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let shown else { return }
        if title == nil { title = webView.title.flatMap { $0.isEmpty ? nil : $0 } }
        let place = ReaderPlace.saved(shown.url, reading: shown.reading)
        if place > 0 { webView.evaluateJavaScript("prismRestore(\(place))") }
        if let marking = ReaderPage.marking(marks) { webView.evaluateJavaScript(marking) }
    }

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard message.name == "scrolled", let shown, let place = message.body as? Double else { return }
            ReaderPlace.save(place, for: shown.url, reading: shown.reading)
        }
    }

    /// Weft's paper and ink, light and dark.
    static let paper = ReaderPage.Paper(paper: ("#fbf8f3", "#1c1a17"), ink: ("#2b2724", "#ece6dc"), soft: ("#6f6a63", "#a19b92"))
}

#if os(macOS)
struct ReaderWebView: NSViewRepresentable {
    let web: ReaderWeb
    func makeNSView(context: Context) -> WKWebView { web.view }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
struct ReaderWebView: UIViewRepresentable {
    let web: ReaderWeb
    func makeUIView(context: Context) -> WKWebView { web.view }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif
