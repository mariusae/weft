import Foundation
import FoundationModels
import ReflectCore
import Vision
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A new tiddler of what the pasteboard holds: its words; a link, under
/// the page's own title; pictures, kept in the graph as pasting keeps them.
/// Titled at once as well as can be told without waiting — a heading, the
/// first line, the picture's file — and then, where it can be, better: the
/// page's title, fetched; a title the device's model writes of the words,
/// or of the words read in a picture.
@MainActor
public enum PastedTiddler {
    #if os(macOS)
    /// A pasteboard of its own to read, for a snapshot: not the person's.
    public static var pasteboardName: String?
    #endif

    enum Content {
        case text(String)
        case link(URL)
        /// The pictures, and the name of the file the first came from, if any.
        case pictures([(data: Data, ext: String)], name: String?)
    }

    /// What the pasteboard holds that a tiddler can be made of: pictures
    /// with no words with them, as pasting reads it; a web address alone;
    /// else the words.
    static func read() -> Content? {
        #if os(macOS)
        let board = pasteboardName.map { NSPasteboard(name: .init($0)) } ?? .general
        let strings = board.string(forType: .string)
        let pictures = PastedPictures.pictures(on: board)
        let files = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !pictures.isEmpty, strings == nil || !files.isEmpty {
            return .pictures(pictures, name: files.first?.deletingPathExtension().lastPathComponent)
        }
        #else
        let board = UIPasteboard.general
        let strings = board.string
        if board.hasImages, !board.hasStrings {
            let pictures = PastedPictures.pictures(on: board)
            if !pictures.isEmpty { return .pictures(pictures, name: nil) }
        }
        #endif
        guard let text = strings?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let address = LinkPaste.address(in: text), let url = URL(string: address), url.scheme?.hasPrefix("http") == true {
            return .link(url)
        }
        return .text(text)
    }

    /// The tiddler at once: its title as well as can be told without
    /// waiting, and what it says. Nil, when its pictures could not be kept.
    static func draft(of content: Content) -> (title: String, text: String)? {
        switch content {
        case .text(let text):
            let told = titled(text)
            return (told.title ?? "Pasted Words", told.text)
        case .link(let url):
            return (shortName(of: url), LinkTitle.markdown(address: url.absoluteString, title: shortName(of: url)))
        case .pictures(let pictures, let name):
            let shown = pictures.compactMap { PastedPictures.keep([$0]) }
            guard !shown.isEmpty else { return nil }
            return (name.map(cleaned) ?? "Picture \(pictureTime.string(from: Date()))", shown.joined(separator: "\n"))
        }
    }

    /// A better title, where one can be had: the page's own, fetched —
    /// and the link, its words — one the model writes of words with no
    /// heading, or of a picture's words. Nil, when there is none better
    /// than the first.
    static func better(for content: Content) async -> (title: String, text: String?)? {
        switch content {
        case .text(let text):
            guard titled(text).heading == nil else { return nil }
            return await modelTitle(for: text).map { ($0, nil) }
        case .link(let url):
            return await pageTitle(of: url).map { ($0, LinkTitle.markdown(address: url.absoluteString, title: $0)) }
        case .pictures(let pictures, let name):
            guard name == nil, let first = pictures.first, let words = await recognizedText(in: first.data), !words.isEmpty,
                  let title = await modelTitle(for: words) ?? titled(words).title else { return nil }
            return (title, nil)
        }
    }

    // MARK: Telling a title

    /// When a picture was pasted, as its title says it: a name a file can have.
    private static let pictureTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter
    }()

    /// A heading's words, when the text starts with one — taken out of what
    /// it says, the card's title being it — else its first line's, cut short.
    private static func titled(_ text: String) -> (title: String?, text: String, heading: String?) {
        var lines = text.components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return (nil, text, nil) }
        let line = lines[first].trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("#"), case let words = line.drop(while: { $0 == "#" }), words.first == " " {
            let heading = cleaned(String(words))
            lines.removeSubrange(0...first)
            while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
            return (heading.isEmpty ? nil : heading, lines.isEmpty ? text : lines.joined(separator: "\n"), heading)
        }
        let title = cleaned(line)
        return (title.isEmpty ? nil : title, text, nil)
    }

    /// Words as a title: Markdown's marks out — a list's, a task's, a
    /// quote's, emphasis, a link's address — on one line, a file's name
    /// can hold, cut at a word past sixty letters.
    static func cleaned(_ words: String) -> String {
        var line = words.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["- [ ] ", "- [x] ", "+ [ ] ", "+ [x] ", "- ", "* ", "+ ", "> ", "#"] where line.hasPrefix(marker) {
            line = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        // `[words](address)`: the words; `[[Title]]`: the title.
        line = line.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        line = line.replacingOccurrences(of: #"\[\[([^\]|]*)(\|[^\]]*)?\]\]"#, with: "$1", options: .regularExpression)
        for mark in ["**", "__", "`", "~~", "=="] { line = line.replacingOccurrences(of: mark, with: "") }
        line = line.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " –")
        line = line.components(separatedBy: .newlines).first ?? line
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: " .,;").union(.whitespaces))
        guard line.count > 60 else { return line }
        let cut = line.prefix(60)
        return String(cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut).trimmingCharacters(in: .whitespaces)
    }

    /// A page's address, short: its site and the last of its path.
    private static func shortName(of url: URL) -> String {
        let site = (url.host ?? url.absoluteString).replacingOccurrences(of: "www.", with: "")
        let last = url.deletingPathExtension().lastPathComponent
        return cleaned(last.isEmpty || last == "/" ? site : "\(site) – \(last)")
    }

    // MARK: Asking

    /// The page's title, as a link's preview reads it: given a few seconds.
    private static func pageTitle(of url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let title = PageMetadata.parse(html: html, url: response.url ?? url)?.title else { return nil }
        let clean = cleaned(title)
        return clean.isEmpty ? nil : clean
    }

    /// A short title the device's model writes of some words: none, where
    /// there is no model, or it says nothing worth having.
    private static func modelTitle(for words: String) async -> String? {
        // Too few words to tell what they are about: it would make something up.
        guard words.trimmingCharacters(in: .whitespacesAndNewlines).count >= 12,
              case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: """
            You name notes. Given a note, answer with a title for it: two to seven words \
            saying what it is about, in the language the note is written in — English, \
            when unsure. Answer with the title alone: no quotes, no full stop, no preamble.
            """)
        guard let answer = try? await session.respond(to: String(words.prefix(4000))).content else { return nil }
        let title = cleaned(answer.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'").union(.whitespacesAndNewlines)))
        return title.isEmpty || title.count > 80 ? nil : title
    }

    /// The words a picture shows, read on the device.
    private static func recognizedText(in data: Data) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            // Fast: the accurate reader is made ready for each app that asks,
            // which takes the better part of a minute; this is at once, and
            // enough for a title.
            request.recognitionLevel = .fast
            guard (try? VNImageRequestHandler(data: data).perform([request])) != nil else { return nil }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }.value
    }
}
