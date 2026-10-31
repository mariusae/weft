import Foundation

/// A field a tag gives every tiddler tagged with it, and what kind of value
/// it holds: TiddlyWiki's templates and view cascade, as a form. A tag
/// tiddler lists them in its `fields`:
///
/// ```
/// fields:
///   - birthday (date)
///   - company (link)
///   - status (active | paused | done)
///   - rating (number)
///   - website (url)
///   - met (yes/no)
///   - notes
/// ```
public struct FieldSpec: Equatable, Hashable, Sendable {
    public var name: String
    public var kind: Kind

    public init(name: String, kind: Kind = .text) {
        self.name = name
        self.kind = kind
    }

    public enum Kind: Equatable, Hashable, Sendable {
        case text, number, date, link, url, flag
        case choice([String])

        public static let simple: [Kind] = [.text, .number, .date, .link, .url, .flag]

        public var label: String {
            switch self {
            case .text: "Text"
            case .number: "Number"
            case .date: "Date"
            case .link: "Link"
            case .url: "Web Address"
            case .flag: "Yes or No"
            case .choice: "Choice"
            }
        }
    }

    /// The field the tag tiddler keeps its specs in.
    public static let field = "fields"

    /// `birthday (date)`, `status (active | paused)`, or a bare name for text.
    public init?(item: String) {
        let trimmed = item.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasSuffix(")"), let open = trimmed.lastIndex(of: "(") else {
            self.init(name: trimmed)
            return
        }
        let name = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        let type = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let kind: Kind
        if type.contains("|") {
            kind = .choice(type.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        } else {
            switch type.lowercased() {
            case "date", "day": kind = .date
            case "number": kind = .number
            case "link", "tiddler": kind = .link
            case "url", "web", "web address": kind = .url
            case "yes/no", "flag", "bool", "yes or no": kind = .flag
            default: kind = .text
            }
        }
        self.init(name: name, kind: kind)
    }

    /// The spec as its line in the tag's `fields`.
    public var item: String {
        switch kind {
        case .text: name
        case .number: "\(name) (number)"
        case .date: "\(name) (date)"
        case .link: "\(name) (link)"
        case .url: "\(name) (url)"
        case .flag: "\(name) (yes/no)"
        case .choice(let options): "\(name) (\(options.joined(separator: " | ")))"
        }
    }

    /// The specs a tag tiddler gives.
    public static func specs(of tag: Tiddler) -> [FieldSpec] {
        (tag[field: field]?.list ?? []).compactMap(FieldSpec.init(item:))
    }

    /// A date field's value, `2026-10-31`, and the date it is: that day's
    /// start where this device is, so it is shown as that day.
    public static func date(_ value: String) -> Date? {
        try? Date(value.trimmingCharacters(in: .whitespaces), strategy: Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    public static func value(of date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    public static func flag(_ value: String) -> Bool {
        ["yes", "true", "on", "1", "y"].contains(value.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

extension Wiki {
    /// The fields a tiddler's tags give it, in the order of its tags, each
    /// once — and none the tiddler's own `fields` describes, since a tag's
    /// specs are for what it tags.
    public func schema(for tiddler: Tiddler) -> [FieldSpec] {
        var specs: [FieldSpec] = []
        var seen = Set<String>()
        for tag in tiddler.tags {
            guard let tagTiddler = self[tag] else { continue }
            for spec in FieldSpec.specs(of: tagTiddler) where !seen.contains(spec.name) && !Tiddler.reservedFields.contains(spec.name) {
                seen.insert(spec.name)
                specs.append(spec)
            }
        }
        return specs
    }
}
