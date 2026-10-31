import Foundation

/// Which tiddlers, and how to show them: what TiddlyWiki says with a filter
/// and a list widget, said as a form — and written in a tiddler as a
/// ```` ```query ```` block, a line for each condition:
///
/// ```
/// tag: Filter Operators
/// not tag: Deprecated
/// sort: -modified
/// limit: 10
/// show: table
/// columns: caption, op-purpose
/// ```
///
/// `{this}` stands for the tiddler the query is in: `tag: {this}` is what
/// is tagged with it.
public struct Query: Equatable, Sendable {
    /// Tagged with every one of these.
    public var tags: [String] = []
    /// Tagged with none of these.
    public var excludedTags: [String] = []
    /// Words in the title, and in the body.
    public var titleContains = ""
    public var textContains = ""
    /// Tiddlers linking to this one, and those this one links to.
    public var linksTo = ""
    public var linkedFrom = ""
    /// The titles in this tiddler's `list` field, in their order.
    public var listedIn = ""
    /// Having each of these fields.
    public var hasFields: [String] = []
    public var sort: Sort = .automatic
    public var descending = false
    public var limit: Int?
    public var show: Display = .list
    /// The fields a table shows beside the title.
    public var columns: [String] = []
    /// Lines weft did not understand, kept so that they are written back.
    public var unknown: [String] = []

    public init() {}

    public enum Sort: String, CaseIterable, Sendable {
        /// In the order the source gives — a tag's or a list's — else by title.
        case automatic, title, created, modified
    }

    public enum Display: String, CaseIterable, Sendable {
        case list, inline, table, cards, count, tree
    }

    public static let this = "{this}"

    // MARK: Text

    public init(text: String) {
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let colon = trimmed.firstIndex(of: ":") else {
                unknown.append(line)
                continue
            }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "tag": tags.append(value)
            case "not tag": excludedTags.append(value)
            case "title": titleContains = value
            case "text": textContains = value
            case "links to": linksTo = value
            case "linked from": linkedFrom = value
            case "listed in": listedIn = value
            case "has": hasFields += Self.items(value)
            case "sort":
                descending = value.hasPrefix("-")
                sort = Sort(rawValue: value.trimmingCharacters(in: CharacterSet(charactersIn: "-+ ")).lowercased()) ?? .automatic
            case "limit": limit = Int(value)
            case "show": show = Display(rawValue: value.lowercased()) ?? .list
            case "columns": columns = Self.items(value)
            default: unknown.append(line)
            }
        }
    }

    private static func items(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The query as a block's lines, in weft's order.
    public var text: String {
        var lines: [String] = []
        lines += tags.map { "tag: \($0)" }
        lines += excludedTags.map { "not tag: \($0)" }
        if !titleContains.isEmpty { lines.append("title: \(titleContains)") }
        if !textContains.isEmpty { lines.append("text: \(textContains)") }
        if !linksTo.isEmpty { lines.append("links to: \(linksTo)") }
        if !linkedFrom.isEmpty { lines.append("linked from: \(linkedFrom)") }
        if !listedIn.isEmpty { lines.append("listed in: \(listedIn)") }
        if !hasFields.isEmpty { lines.append("has: \(hasFields.joined(separator: ", "))") }
        if sort != .automatic || descending { lines.append("sort: \(descending ? "-" : "")\(sort.rawValue)") }
        if let limit { lines.append("limit: \(limit)") }
        if show != .list { lines.append("show: \(show.rawValue)") }
        if !columns.isEmpty { lines.append("columns: \(columns.joined(separator: ", "))") }
        lines += unknown
        return lines.joined(separator: "\n")
    }

    /// The query as a fenced block, to put in a tiddler.
    public var block: String { "```query\n\(text)\n```" }

    /// What the query asks, in a few words: "Tagged Filters, by title".
    public var summary: String {
        var parts: [String] = []
        if !listedIn.isEmpty { parts.append("Listed in \(listedIn)") }
        if !tags.isEmpty { parts.append("Tagged \(tags.joined(separator: " and "))") }
        if !excludedTags.isEmpty { parts.append("not \(excludedTags.joined(separator: " or "))") }
        if !linksTo.isEmpty { parts.append("Linking to \(linksTo)") }
        if !linkedFrom.isEmpty { parts.append("Linked from \(linkedFrom)") }
        if !titleContains.isEmpty { parts.append("titled “\(titleContains)”") }
        if !textContains.isEmpty { parts.append("mentioning “\(textContains)”") }
        if !hasFields.isEmpty { parts.append("with \(hasFields.joined(separator: ", "))") }
        if parts.isEmpty { parts.append("Every tiddler") }
        if sort != .automatic { parts.append("by \(sort.rawValue)\(descending ? ", newest first" : "")") }
        if let limit { parts.append("first \(limit)") }
        return parts.joined(separator: ", ").replacingOccurrences(of: Self.this, with: "this tiddler")
    }

    // MARK: Asking

    /// The tiddlers the query finds in a wiki, in order. `this` is the
    /// tiddler it is asked from.
    public func run(in wiki: Wiki, this: String) -> [String] {
        func resolve(_ value: String) -> String { value == Self.this ? this : value }
        let tags = tags.map(resolve), excludedTags = excludedTags.map(resolve)
        let ordered: Bool
        var titles: [String]
        if !listedIn.isEmpty {
            titles = (wiki[resolve(listedIn)]?[field: "list"]?.list ?? []).filter { wiki[$0] != nil }
            ordered = true
        } else if let first = tags.first {
            titles = wiki.tagged(first)
            ordered = true
        } else if !linksTo.isEmpty {
            titles = wiki.backlinks(to: resolve(linksTo))
            ordered = false
        } else if !linkedFrom.isEmpty {
            titles = wiki.links(from: resolve(linkedFrom)).filter { wiki[$0] != nil }.sorted()
            ordered = false
        } else {
            titles = wiki.titles
            ordered = false
        }
        let linkingTo = linksTo.isEmpty ? nil : Set(wiki.backlinks(to: resolve(linksTo)))
        let linkedFromSet = linkedFrom.isEmpty ? nil : wiki.links(from: resolve(linkedFrom))
        titles = titles.filter { title in
            guard let tiddler = wiki[title] else { return false }
            if !tags.allSatisfy(tiddler.tags.contains) { return false }
            if excludedTags.contains(where: tiddler.tags.contains) { return false }
            if !titleContains.isEmpty, title.range(of: titleContains, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
                return false
            }
            if !textContains.isEmpty, tiddler.text.range(of: textContains, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
                return false
            }
            if let linkingTo, !linkingTo.contains(title) { return false }
            if let linkedFromSet, !linkedFromSet.contains(title) { return false }
            if !hasFields.allSatisfy({ field in Self.has(tiddler, field) }) { return false }
            return true
        }
        switch sort {
        case .automatic:
            if !ordered { titles.sort { $0.localizedStandardCompare($1) == .orderedAscending } }
        case .title:
            titles.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        case .created, .modified:
            func date(_ title: String) -> Date {
                let tiddler = wiki[title]
                return (sort == .created ? tiddler?.created : tiddler?.modified) ?? .distantPast
            }
            titles.sort { date($0) < date($1) }
        }
        if descending { titles.reverse() }
        if let limit { titles = Array(titles.prefix(max(0, limit))) }
        return titles
    }

    private static func has(_ tiddler: Tiddler, _ field: String) -> Bool {
        switch field {
        case "tags": !tiddler.tags.isEmpty
        case "text": !tiddler.text.isEmpty
        case "created": tiddler.created != nil
        case "modified": tiddler.modified != nil
        default:
            switch tiddler[field: field] {
            case .text(let text): !text.isEmpty
            case .list(let list): !list.isEmpty
            case nil: false
            }
        }
    }
}

extension MarkdownBlock {
    /// A tiddler's text with its `index`th query block — counting from 0 —
    /// holding `query` instead.
    public static func replacingQuery(at index: Int, in text: String, with query: Query) -> String {
        var lines = text.components(separatedBy: "\n")
        var seen = 0
        var line = 0
        while line < lines.count {
            let ticks = lines[line].prefix { $0 == "`" }
            if ticks.count >= 3 {
                let language = lines[line].dropFirst(ticks.count).trimmingCharacters(in: .whitespaces)
                var end = line + 1
                while end < lines.count, !(lines[end].hasPrefix(ticks) && lines[end].allSatisfy { $0 == "`" || $0 == " " }) { end += 1 }
                if language == "query" {
                    if seen == index {
                        lines.replaceSubrange((line + 1)..<min(end, lines.count), with: query.text.components(separatedBy: "\n"))
                        return lines.joined(separator: "\n")
                    }
                    seen += 1
                }
                line = end + 1
                continue
            }
            line += 1
        }
        return text
    }
}
