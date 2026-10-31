import Foundation

/// A tiddler as a file: YAML frontmatter, then the body.
///
/// ```
/// ---
/// id: 01jbxk3t6y8q2zp4m9v7c5r0wd
/// title: HelloThere
/// tags: [Welcome, Table of Contents]
/// created: 2026-10-31T10:34:00Z
/// modified: 2026-10-31T10:41:12Z
/// caption: Hello
/// ---
/// Welcome to [[TiddlyWiki]]…
/// ```
///
/// Reading a file and writing it back unchanged gives the same bytes; a
/// tiddler written over its file changes only the entries that changed, and
/// the body if it did.
public enum TiddlerFile {
    /// The tiddler in a file's text. `fallbackTitle` names one whose
    /// frontmatter does not: the file's name.
    public static func read(_ source: String, fallbackTitle: String) -> Tiddler {
        let parts = split(source)
        let header = Header(raw: parts.header ?? "")
        var tiddler = Tiddler(title: header["title"]?.text.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle,
                              id: header["id"]?.text,
                              tags: tags(header["tags"]),
                              created: header["created"]?.text.flatMap(date),
                              modified: header["modified"]?.text.flatMap(date),
                              text: parts.body)
        var seen = Set<String>()
        for entry in header.entries {
            guard let key = entry.key, let value = entry.value, !Tiddler.reservedFields.contains(key),
                  seen.insert(key).inserted else { continue }
            tiddler.fields.append(Tiddler.Field(key, value))
        }
        return tiddler
    }

    /// The file's text for a tiddler, written over `source` — its file as it
    /// was — keeping what has not changed as it was written. A title that is
    /// still `fallbackTitle`, in a file that never gave one, is not written.
    public static func write(_ tiddler: Tiddler, over source: String? = nil, fallbackTitle: String? = nil) -> String {
        guard let source else {
            let lines = entries(for: tiddler, title: true).flatMap { Header.lines(key: $0.key, value: $0.value) }
            return "---\n" + lines.joined(separator: "\n") + "\n---\n" + tiddler.text
        }
        let parts = split(source)
        let old = Header(raw: parts.header ?? "")
        let wanted = entries(for: tiddler, title: old["title"] != nil || tiddler.title != fallbackTitle)
        let wantedByKey = Dictionary(wanted.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        var lines: [String] = []
        var written = Set<String>()
        for entry in old.entries {
            guard let key = entry.key else {
                lines += entry.lines
                continue
            }
            guard let value = wantedByKey[key], written.insert(key).inserted else { continue }
            lines += same(key: key, entry.value, value) ? entry.lines : Header.lines(key: key, value: value)
        }
        for entry in wanted where !written.contains(entry.key) {
            lines += Header.lines(key: entry.key, value: entry.value)
        }
        guard let header = parts.header else {
            return lines.isEmpty ? tiddler.text : "---\n" + lines.joined(separator: "\n") + "\n---\n" + tiddler.text
        }
        // An empty header's closing fence has no newline before it to keep.
        let gap = header.isEmpty && !lines.isEmpty ? "\n" : ""
        return parts.open + lines.joined(separator: "\n") + gap + parts.close + tiddler.text
    }

    // MARK: Parts

    /// A file's frontmatter (without its fences) and body; `open` and
    /// `close` are the fences as written, newlines and all. Worked out by
    /// Unicode scalars, not characters, since `\r\n` is one character.
    static func split(_ source: String) -> (open: String, header: String?, close: String, body: String) {
        let scalars = Array(source.unicodeScalars)
        func text(_ range: Range<Int>) -> String {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[range])
            return String(view)
        }
        /// Where a `---` line at `index` ends, past its newline; `...` closes too.
        func fence(at index: Int, closing: Bool) -> Int? {
            guard index + 3 <= scalars.count else { return nil }
            let marker = String(String.UnicodeScalarView(scalars[index..<(index + 3)]))
            guard marker == "---" || (closing && marker == "...") else { return nil }
            var end = index + 3
            while end < scalars.count, scalars[end] == " " || scalars[end] == "\t" { end += 1 }
            if end == scalars.count { return closing ? end : nil }
            if scalars[end] == "\r", end + 1 < scalars.count, scalars[end + 1] == "\n" { return end + 2 }
            return scalars[end] == "\n" ? end + 1 : nil
        }
        guard let open = fence(at: 0, closing: false) else { return ("", nil, "", source) }
        if let end = fence(at: open, closing: true) {
            return (text(0..<open), "", text(open..<end), text(end..<scalars.count))
        }
        var search = open
        while let newline = scalars[search...].firstIndex(of: "\n") {
            if let end = fence(at: newline + 1, closing: true) {
                // The newline before the closing fence belongs to the fence.
                let headerEnd = newline > open && scalars[newline - 1] == "\r" ? newline - 1 : newline
                return (text(0..<open), text(open..<headerEnd), text(headerEnd..<end), text(end..<scalars.count))
            }
            search = newline + 1
        }
        return ("", nil, "", source)
    }

    // MARK: Entries

    private static func entries(for tiddler: Tiddler, title: Bool) -> [(key: String, value: Tiddler.Value)] {
        var entries: [(key: String, value: Tiddler.Value)] = []
        if let id = tiddler.id { entries.append(("id", .text(id))) }
        if title { entries.append(("title", .text(tiddler.title))) }
        if !tiddler.tags.isEmpty { entries.append(("tags", .list(tiddler.tags))) }
        if let created = tiddler.created { entries.append(("created", .text(format(created)))) }
        if let modified = tiddler.modified { entries.append(("modified", .text(format(modified)))) }
        for field in tiddler.fields where !Tiddler.reservedFields.contains(field.name) {
            entries.append((field.name, field.value))
        }
        return entries
    }

    private static func same(key: String, _ old: Tiddler.Value?, _ new: Tiddler.Value) -> Bool {
        guard let old else { return false }
        if key == "created" || key == "modified", let a = old.text.flatMap(date), let b = new.text.flatMap(date) {
            return milliseconds(a) == milliseconds(b)
        }
        if key == "tags" { return tags(old) == tags(new) }
        return old == new
    }

    private static func tags(_ value: Tiddler.Value?) -> [String] {
        switch value {
        case .list(let items): items
        case .text(let text): text.isEmpty ? [] : [text]
        case nil: []
        }
    }

    // MARK: Dates

    /// `2026-10-31T10:41:12Z`, with milliseconds when there are any.
    public static func format(_ date: Date) -> String {
        let total = milliseconds(date)
        let fraction = Int(((total % 1000) + 1000) % 1000)
        let seconds = Date(timeIntervalSince1970: Double(total - Int64(fraction)) / 1000)
        let whole = seconds.formatted(Date.ISO8601FormatStyle())
        return fraction == 0 ? whole : whole.dropLast() + String(format: ".%03dZ", fraction)
    }

    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// An ISO 8601 date, with or without a time or fractions of a second, or
    /// TiddlyWiki's `YYYYMMDDhhmmssSSS`.
    public static func date(_ text: String) -> Date? {
        let text = text.trimmingCharacters(in: .whitespaces)
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle()) { return date }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle().year().month().day()) { return date }
        return TiddlyWikiDate.parse(text)
    }
}

/// TiddlyWiki's dates: `YYYYMMDDhhmmssSSS`, in UTC, the later parts optional.
public enum TiddlyWikiDate {
    public static func parse(_ text: String) -> Date? {
        let digits = Array(text.utf8)
        guard digits.count >= 8, digits.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        func number(_ start: Int, _ length: Int) -> Int {
            guard start + length <= digits.count else { return 0 }
            return digits[start..<(start + length)].reduce(0) { $0 * 10 + Int($1 - 48) }
        }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "UTC")
        components.year = number(0, 4)
        components.month = number(4, 2)
        components.day = number(6, 2)
        components.hour = number(8, 2)
        components.minute = number(10, 2)
        components.second = number(12, 2)
        guard let date = components.date else { return nil }
        return date.addingTimeInterval(Double(number(14, 3)) / 1000)
    }
}
