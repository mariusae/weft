import Foundation

/// TiddlyWiki's WikiText, as Markdown.
///
/// The common WikiText — headings, lists, emphasis, links, images,
/// transclusion, code, tables, quotes — becomes its Markdown. What has no
/// Markdown — macros, widgets, filters, pragmas — is left as written: a
/// block of it in a ```` ```tiddlywiki ```` fence, shown as a placeholder,
/// and a call within a line as it stands. Either way it is counted in the
/// result's `residue`, by kind.
public struct WikiText {
    /// Image tiddlers' titles, and the files in `assets/` they became, so a
    /// `[img[Title]]` can show the file.
    public var images: [String: String]
    /// Whether to rewrite the macros tiddlywiki.com's documentation is
    /// written with — `<<.def>>`, `<<.olink>>`, `<<.tip>>`, … — as the
    /// Markdown they come to. Only for a wiki that defines them.
    public var documentationMacros: Bool

    public init(images: [String: String] = [:], documentationMacros: Bool = false) {
        self.images = images
        self.documentationMacros = documentationMacros
    }

    public struct Result: Equatable {
        public var markdown: String
        /// What was left as written, by kind: `macro`, `widget`, `filter`,
        /// `pragma`, `transclusion`, `table`, `style`, `html`.
        public var residue: [String: Int]

        public var isComplete: Bool { residue.isEmpty }
    }

    public func convert(_ text: String) -> Result {
        var converter = Converter(images: images, documentationMacros: documentationMacros)
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let blocks = converter.blocks(lines[...])
        var markdown = blocks.joined(separator: "\n\n")
        if !markdown.isEmpty { markdown += "\n" }
        return Result(markdown: markdown, residue: converter.residue)
    }
}

private struct Converter {
    let images: [String: String]
    let documentationMacros: Bool
    var residue: [String: Int] = [:]

    init(images: [String: String], documentationMacros: Bool) {
        self.images = images
        self.documentationMacros = documentationMacros
    }

    mutating func note(_ kind: String) {
        residue[kind, default: 0] += 1
    }

    // MARK: Blocks

    /// The Markdown blocks for some lines of WikiText.
    mutating func blocks(_ lines: ArraySlice<String>) -> [String] {
        var output: [String] = []
        var index = lines.startIndex
        // Pragmas — `\define`, `\procedure`, `\import`, … — come first.
        var pragma: [String] = []
        while index < lines.endIndex {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty, !pragma.isEmpty || index == lines.startIndex {
                if !pragma.isEmpty { pragma.append(line) }
                index += 1
                continue
            }
            guard line.hasPrefix("\\") else { break }
            pragma.append(line)
            index += 1
            if Self.opensDefinition(line) {
                while index < lines.endIndex {
                    let body = lines[index]
                    pragma.append(body)
                    index += 1
                    if body.trimmingCharacters(in: .whitespaces).hasPrefix("\\end") { break }
                }
            }
        }
        if !pragma.isEmpty {
            while pragma.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { pragma.removeLast() }
            output.append(fenced(pragma, kind: "pragma"))
        }

        while index < lines.endIndex {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }
            // Code, as Markdown writes it.
            if line.hasPrefix("```") {
                var code = [line]
                index += 1
                while index < lines.endIndex {
                    code.append(lines[index])
                    index += 1
                    if lines[index - 1].hasPrefix("```") { break }
                }
                output.append(code.joined(separator: "\n"))
                continue
            }
            // A typed block: `$$$text/css` … `$$$`.
            if line.hasPrefix("$$$") {
                let type = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.endIndex, !lines[index].hasPrefix("$$$") {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                output.append("```\(Self.language(forType: type))\n" + code.joined(separator: "\n") + "\n```")
                continue
            }
            if let heading = heading(line) {
                output.append(heading)
                index += 1
                continue
            }
            if trimmed.count >= 3, trimmed.allSatisfy({ $0 == "-" }) {
                output.append("---")
                index += 1
                continue
            }
            // A block quote: `<<<` … `<<< Who said it`.
            if line.hasPrefix("<<<") {
                let opening = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var inner: [String] = []
                var citation = ""
                index += 1
                while index < lines.endIndex {
                    let next = lines[index]
                    index += 1
                    if next.hasPrefix("<<<") {
                        citation = next.dropFirst(3).trimmingCharacters(in: .whitespaces)
                        break
                    }
                    inner.append(next)
                }
                if !opening.isEmpty, !opening.hasPrefix(".") { inner.insert(opening, at: 0) }
                var quoted = blocks(inner[...]).joined(separator: "\n\n")
                if !citation.isEmpty { quoted += "\n\n— " + inline(citation) }
                output.append(Self.prefixed(quoted, with: "> "))
                continue
            }
            if Self.isListLine(line) {
                var items: [String] = []
                while index < lines.endIndex, Self.isListLine(lines[index]) {
                    items.append(lines[index])
                    index += 1
                }
                output.append(list(items))
                continue
            }
            if line.hasPrefix("|") {
                var rows: [String] = []
                while index < lines.endIndex, lines[index].hasPrefix("|") {
                    rows.append(lines[index])
                    index += 1
                }
                output.append(table(rows))
                continue
            }
            // Hard line breaks: `"""` … `"""`.
            if trimmed == "\"\"\"" {
                var inner: [String] = []
                index += 1
                while index < lines.endIndex, lines[index].trimmingCharacters(in: .whitespaces) != "\"\"\"" {
                    inner.append(lines[index])
                    index += 1
                }
                index += 1
                output.append(inner.map { inline($0, lineStarts: true) }.joined(separator: "\\\n"))
                continue
            }
            // A paragraph runs to a blank line — or, when it opens elements it
            // has not closed, on until they are.
            var paragraph: [String] = []
            var depth = 0
            while index < lines.endIndex {
                let next = lines[index]
                if next.trimmingCharacters(in: .whitespaces).isEmpty {
                    if depth <= 0 { break }
                    paragraph.append(next)
                    index += 1
                    continue
                }
                if !paragraph.isEmpty, depth <= 0, next.hasPrefix("```") { break }
                paragraph.append(next)
                depth += Self.elementDepth(next)
                index += 1
            }
            while paragraph.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { paragraph.removeLast() }
            output.append(self.paragraph(paragraph))
        }
        return output
    }

    private static func opensDefinition(_ line: String) -> Bool {
        let words = ["\\define", "\\procedure", "\\function", "\\widget"]
        guard words.contains(where: { line.hasPrefix($0 + " ") }) else { return false }
        // `\define name(params) text` is one line; with nothing after the
        // parameters, the body runs to `\end`.
        guard let close = line.lastIndex(of: ")") else { return true }
        return line[line.index(after: close)...].trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func language(forType type: String) -> String {
        switch type {
        case "text/css", ".css": "css"
        case "application/javascript", "text/javascript", ".js": "js"
        case "application/json", ".json": "json"
        case "text/html", ".html": "html"
        case "text/vnd.tiddlywiki", ".tid", ".wikitext": "tiddlywiki"
        case "text/x-markdown", "text/markdown", ".md": "markdown"
        default: ""
        }
    }

    private mutating func fenced(_ lines: [String], kind: String) -> String {
        note(kind)
        let body = lines.joined(separator: "\n")
        let fence = body.contains("```") ? "````" : "```"
        return "\(fence)tiddlywiki\n\(body)\n\(fence)"
    }

    static func prefixed(_ text: String, with prefix: String) -> String {
        text.components(separatedBy: "\n").map { $0.isEmpty ? prefix.trimmingCharacters(in: .whitespaces) : prefix + $0 }
            .joined(separator: "\n")
    }

    // MARK: Headings, lists

    private mutating func heading(_ line: String) -> String? {
        let level = line.prefix { $0 == "!" }.count
        guard level > 0 else { return nil }
        var rest = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        // `!.class Heading`: the classes go.
        while rest.hasPrefix(".") {
            rest = rest.drop { !$0.isWhitespace }.trimmingCharacters(in: .whitespaces)
        }
        return String(repeating: "#", count: min(level, 6)) + " " + inline(rest)
    }

    /// A line beginning `*`, `#`, `;`, `:` or `>` is a list's, as TiddlyWiki has it.
    private static func isListLine(_ line: String) -> Bool {
        line.first.map { "*#;:>".contains($0) } ?? false
    }

    private mutating func list(_ lines: [String]) -> String {
        var output: [String] = []
        for line in lines {
            let markers = Array(line.prefix { "*#;:>".contains($0) })
            var content = line.dropFirst(markers.count).trimmingCharacters(in: .whitespaces)
            while content.hasPrefix(".") {
                content = content.drop { !$0.isWhitespace }.trimmingCharacters(in: .whitespaces)
            }
            let text = inline(content)
            if markers.allSatisfy({ $0 == ">" }) {
                output.append(String(repeating: "> ", count: markers.count) + text)
                continue
            }
            // Each enclosing list's marker sets how far this one is indented.
            var indent = ""
            for marker in markers.dropLast() {
                indent += marker == "#" ? "   " : marker == ">" ? "> " : "  "
            }
            switch markers.last {
            case "#": output.append(indent + "1. " + text)
            case ";": output.append(indent + "**" + text + "**")
            case ":": output.append(indent + "  " + text)
            default: output.append(indent + "- " + text)
            }
        }
        return output.joined(separator: "\n")
    }

    // MARK: Tables

    private mutating func table(_ lines: [String]) -> String {
        var caption: String?
        var header: [String]?
        var rows: [[String]] = []
        for line in lines {
            var body = line.trimmingCharacters(in: .whitespaces)
            var kind: Character?
            if let last = body.last, "hfck".contains(last), body.dropLast().hasSuffix("|") {
                kind = last
                body.removeLast()
            }
            guard body.hasSuffix("|"), body.count >= 2 else { return fenced(lines, kind: "table") }
            let cells = Self.cells(String(body.dropFirst().dropLast()))
            if cells.contains(where: { ["~", "<", ">", "^"].contains($0.trimmingCharacters(in: .whitespaces)) }) {
                return fenced(lines, kind: "table")
            }
            switch kind {
            case "c": caption = cells.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            case "k": continue
            case "h": header = cells
            default:
                if rows.isEmpty, header == nil, cells.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).hasPrefix("!") }) {
                    header = cells
                } else {
                    rows.append(cells)
                }
            }
        }
        let width = max(header?.count ?? 0, rows.map(\.count).max() ?? 0)
        guard width > 0 else { return fenced(lines, kind: "table") }
        func row(_ cells: [String]) -> String {
            let padded = cells + Array(repeating: "", count: width - cells.count)
            return "| " + padded.map { cell(String($0)) }.joined(separator: " | ") + " |"
        }
        var output: [String] = []
        if let caption { output.append("*" + inline(caption) + "*\n") }
        output.append(row(header ?? []))
        output.append("|" + Array(repeating: " --- |", count: width).joined())
        output += rows.map(row)
        return output.joined(separator: "\n")
    }

    private mutating func cell(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("!") { text.removeFirst() }
        // `^` and `,` set a cell's vertical alignment, which Markdown has not.
        if text.hasPrefix("^") || text.hasPrefix(",") { text.removeFirst() }
        return inline(text.trimmingCharacters(in: .whitespaces)).replacingOccurrences(of: "|", with: "\\|")
    }

    /// A row's cells, split at `|` outside links, transclusions and macros.
    private static func cells(_ row: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var depth = 0
        let characters = Array(row)
        var index = 0
        while index < characters.count {
            let pair = index + 1 < characters.count ? String(characters[index...(index + 1)]) : ""
            if ["[[", "{{", "<<"].contains(pair) {
                depth += 1
                current += pair
                index += 2
                continue
            }
            if ["]]", "}}", ">>"].contains(pair), depth > 0 {
                depth -= 1
                current += pair
                index += 2
                continue
            }
            if characters[index] == "|", depth == 0 {
                cells.append(current)
                current = ""
            } else {
                current.append(characters[index])
            }
            index += 1
        }
        cells.append(current)
        return cells
    }

    // MARK: Paragraphs

    /// How many more elements — widgets and HTML — a line opens than it closes.
    static func elementDepth(_ line: String) -> Int {
        var depth = 0
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            guard characters[index] == "<", index + 1 < characters.count else {
                index += 1
                continue
            }
            let next = characters[index + 1]
            // A macro call is no element.
            if next == "<" {
                var scanner = InlineScanner(characters)
                scanner.index = index
                if scanner.takeMacro() != nil {
                    index = scanner.index
                } else {
                    index += 2
                }
                continue
            }
            let closing = next == "/"
            let nameStart = closing ? index + 2 : index + 1
            guard nameStart < characters.count, characters[nameStart] == "$" || characters[nameStart].isLetter else {
                index += 1
                continue
            }
            var end = nameStart
            while end < characters.count, characters[end] != ">" {
                if characters[end] == "\"" || characters[end] == "'" {
                    let quote = characters[end]
                    end += 1
                    while end < characters.count, characters[end] != quote { end += 1 }
                }
                end += 1
            }
            let name = String(characters[nameStart..<min(end, characters.count)].prefix { !$0.isWhitespace && $0 != "/" && $0 != ">" })
            let selfClosing = end > 0 && end < characters.count && characters[end - 1] == "/"
            if !selfClosing, !Self.voidElements.contains(name.lowercased()) {
                depth += closing ? -1 : 1
            }
            index = end + 1
        }
        return depth
    }

    static let voidElements: Set<String> = ["br", "hr", "img", "input", "meta", "link", "area", "base", "col", "embed", "source", "track", "wbr"]

    private mutating func paragraph(_ lines: [String]) -> String {
        let text = lines.joined(separator: "\n")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A paragraph that is one element, macro call or filter: a block of it.
        if trimmed.hasPrefix("<<"), let call = MacroCall(wholly: trimmed) {
            if let query = Self.query(for: call) { return query.block }
            if let block = rewrite(call, block: true) { return block }
        }
        if let query = Self.query(forElement: trimmed) { return query.block }
        if let heading = htmlHeading(trimmed) { return heading }
        if trimmed.hasPrefix("<$") || trimmed.hasPrefix("<<") && MacroCall(wholly: trimmed) != nil
            || trimmed.hasPrefix("{{{") && trimmed.hasSuffix("}}}") {
            let kind = trimmed.hasPrefix("<$") ? "widget" : trimmed.hasPrefix("<<") ? "macro" : "filter"
            return fenced(lines, kind: kind)
        }
        if let first = trimmed.first, first == "<", lines.count > 1 || Self.elementDepth(trimmed) != 0,
           trimmed.dropFirst().first?.isLetter == true {
            return fenced(lines, kind: "html")
        }
        // `@@.class` … `@@` around a paragraph: the styling goes.
        if lines.count > 2, lines[0].hasPrefix("@@"), lines[lines.count - 1].trimmingCharacters(in: .whitespaces) == "@@" {
            note("style")
            return blocks(lines[1..<(lines.count - 1)]).joined(separator: "\n\n")
        }
        return inline(text, lineStarts: true)
    }

    /// A paragraph that is one HTML heading — `<h2 class="…" style="…">Text</h2>` —
    /// as a Markdown heading, its styling gone.
    private mutating func htmlHeading(_ text: String) -> String? {
        let pattern = #"^<h([1-6])(?:\s[^>]*)?>(.*)</h\1>$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let levelRange = Range(match.range(at: 1), in: text), let level = Int(text[levelRange]),
              let bodyRange = Range(match.range(at: 2), in: text) else { return nil }
        let body = text[bodyRange].split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty, !body.contains("<h") else { return nil }
        return String(repeating: "#", count: level) + " " + inline(body)
    }

    // MARK: Inline

    /// Inline WikiText as Markdown. With `lineStarts`, the text is lines of
    /// their own, and one Markdown would read as a heading, list or quote
    /// is escaped.
    mutating func inline(_ text: String, lineStarts: Bool = false) -> String {
        var scanner = InlineScanner(Array(text))
        var output = ""
        var plain = ""
        func flush() {
            output += Self.escape(plain, lineStarts: lineStarts, atLineStart: output.isEmpty || output.hasSuffix("\n"))
            plain = ""
        }
        while let character = scanner.current {
            if let converted = inlineRule(&scanner) {
                flush()
                output += converted
            } else {
                plain.append(character)
                scanner.advance()
            }
        }
        flush()
        return output
    }

    /// The Markdown for an inline construct at the scanner, which it passes;
    /// nil, and the scanner where it was, when there is none there.
    private mutating func inlineRule(_ s: inout InlineScanner) -> String? {
        if s.at("``"), let body = s.take(from: "``", to: "``") { return "``" + body + "``" }
        if s.at("`"), let body = s.take(from: "`", to: "`") { return "`" + body + "`" }
        if s.at("''"), let body = s.take(from: "''", to: "''") { return "**" + inline(body) + "**" }
        if s.at("//"), let body = s.take(from: "//", to: "//") { return "*" + inline(body) + "*" }
        if s.at("__"), let body = s.take(from: "__", to: "__") { return "<u>" + inline(body) + "</u>" }
        if s.at("^^"), let body = s.take(from: "^^", to: "^^") { return "<sup>" + inline(body) + "</sup>" }
        if s.at(",,"), let body = s.take(from: ",,", to: ",,") { return "<sub>" + inline(body) + "</sub>" }
        if s.at("~~"), let body = s.take(from: "~~", to: "~~") { return "~~" + inline(body) + "~~" }
        if s.at("[[") , let body = s.take(from: "[[", to: "]]") { return link(body) }
        if s.at("[ext["), let body = s.take(from: "[ext[", to: "]]") {
            let (shown, target) = Self.splitLink(body)
            return "[\(Self.escape(shown))](\(target))"
        }
        if s.at("[img"), let image = image(&s) { return image }
        if s.at("{{{"), let body = s.take(from: "{{{", to: "}}}") {
            note("filter")
            return "{{{" + body + "}}}"
        }
        if s.at("{{"), let body = s.take(from: "{{", to: "}}") {
            let simple = !body.contains("!!") && !body.contains("##") && !body.contains("|")
                && !body.trimmingCharacters(in: .whitespaces).isEmpty
            if simple { return "![[" + body.trimmingCharacters(in: .whitespaces) + "]]" }
            note("transclusion")
            return "{{" + body + "}}"
        }
        if s.at("<<"), let call = s.takeMacro() {
            if let parsed = MacroCall(wholly: call), let rewritten = rewrite(parsed, block: false) { return rewritten }
            note("macro")
            return call
        }
        if s.at("<$") || s.at("</$"), let tag = s.takeTag() {
            note("widget")
            return tag
        }
        if s.at("<!--"), let body = s.take(from: "<!--", to: "-->") { return "<!--" + body + "-->" }
        if s.at("<"), s.peek(1).map({ $0.isLetter || $0 == "/" }) == true, let tag = s.takeTag() { return tag }
        if s.at("@@"), let body = s.take(from: "@@", to: "@@") {
            note("style")
            // `@@.class text@@`, `@@color:red;text@@`: the text alone.
            var text = Substring(body)
            while text.hasPrefix(".") { text = text.drop { !$0.isWhitespace }.drop { $0.isWhitespace } }
            if let semicolon = text.lastIndex(of: ";"), text[..<semicolon].contains(":"), !text[..<semicolon].contains(" ") {
                text = text[text.index(after: semicolon)...]
            }
            return inline(String(text))
        }
        if s.at("~"), s.peek(1)?.isUppercase == true {
            // `~CamelCase`: TiddlyWiki's way of not linking a word.
            s.advance()
            return ""
        }
        if s.atWordStart, let url = s.takeURL() { return url }
        if s.at("&"), let entity = s.takeEntity() { return entity }
        return nil
    }

    private func link(_ body: String) -> String {
        let (shown, target) = Self.splitLink(body)
        if Self.isURL(target) { return "[\(Self.escape(shown))](\(target))" }
        return shown == target ? "[[\(target)]]" : "[[\(target)|\(shown)]]"
    }

    /// `text|target`, or `target` alone.
    private static func splitLink(_ body: String) -> (shown: String, target: String) {
        guard let bar = body.firstIndex(of: "|") else { return (body, body) }
        return (String(body[..<bar]), String(body[body.index(after: bar)...]).trimmingCharacters(in: .whitespaces))
    }

    private static func isURL(_ text: String) -> Bool {
        ["http://", "https://", "mailto:", "ftp://", "file://"].contains { text.lowercased().hasPrefix($0) }
    }

    /// `[img[src]]`, `[img[tooltip|src]]`, `[img width=32 [src]]`.
    private func image(_ s: inout InlineScanner) -> String? {
        let start = s.index
        guard let body = s.take(from: "[img", to: "]]"), let open = body.firstIndex(of: "[") else {
            s.index = start
            return nil
        }
        let attributes = body[..<open]
        let (tooltip, source) = Self.splitLink(String(body[body.index(after: open)...]))
        let alt = tooltip == source ? "" : tooltip
        var size: [String] = []
        for name in ["width", "height"] {
            if let range = attributes.range(of: "\(name)=") {
                let value = attributes[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                    .prefix { $0.isNumber }
                if !value.isEmpty { size.append("\"\(name)\":\(value)") }
            }
        }
        let sizeNote = size.isEmpty ? "" : "<!-- {\(size.joined(separator: ","))} -->"
        if let asset = images[source] { return "![\(Self.escape(alt))](\(asset))" + sizeNote }
        if Self.isURL(source) || source.contains("/") && !source.contains(" ") {
            return "![\(Self.escape(alt))](\(source.replacingOccurrences(of: " ", with: "%20")))" + sizeNote
        }
        return "![[\(source)]]"
    }

    /// Plain text, with what Markdown would take as markup escaped.
    static func escape(_ text: String, lineStarts: Bool = false, atLineStart: Bool = false) -> String {
        var output = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if lineStarts, index == 0 ? atLineStart : characters[index - 1] == "\n", Self.startsBlock(characters[index...]) {
                output += "\\"
            }
            switch character {
            case "*", "[", "]":
                output += "\\" + String(character)
            case "_":
                // Within a word, `_` is only an underscore.
                let before = index > 0 ? characters[index - 1] : " "
                let after = index + 1 < characters.count ? characters[index + 1] : " "
                let inWord = (before.isLetter || before.isNumber) && (after.isLetter || after.isNumber)
                output += inWord ? "_" : "\\_"
            case "\\":
                let after = index + 1 < characters.count ? characters[index + 1] : " "
                output += after.isPunctuation || after.isSymbol ? "\\\\" : "\\"
            default:
                output.append(character)
            }
        }
        return output
    }
}

extension Converter {
    /// Whether a line beginning so would be read by Markdown as a heading,
    /// list item, quote or rule.
    static func startsBlock(_ line: ArraySlice<Character>) -> Bool {
        guard let first = line.first else { return false }
        let second = line.dropFirst().first
        if "#>".contains(first) { return true }
        if "+-=".contains(first), second == nil || second == " " || second == first { return true }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count < 10 {
            let after = line.dropFirst(digits.count)
            return (after.first == "." || after.first == ")") && (after.dropFirst().first == " " || after.count == 1)
        }
        return false
    }

    /// The Markdown a macro call comes to, when it is one weft knows; nil
    /// otherwise. `block` when the call is a paragraph of its own.
    mutating func rewrite(_ call: MacroCall, block: Bool) -> String? {
        guard documentationMacros else { return nil }
        let first = call.argument(0, "_")
        func text(_ value: String?) -> String? { value.map { inline($0) } }
        func code(_ value: String?) -> String? {
            guard let value else { return nil }
            let fence = value.contains("`") ? "``" : "`"
            return fence + (fence == "``" ? " \(value) " : value) + fence
        }
        func link(_ target: String, _ shown: String) -> String {
            target == shown ? "[[\(target)]]" : "[[\(target)|\(shown.replacingOccurrences(of: "]", with: ""))]]"
        }
        switch call.name {
        case ".def", ".em": return text(first).map { "*\($0)*" }
        case ".strong": return text(first).map { "**\($0)**" }
        case ".word": return text(first).map { "\"\($0)\"" }
        case ".place", ".tid", ".tag", ".field", ".value", ".op", ".var", ".attr", ".param": return code(first)
        case ".wid": return first.map { "`<$\($0)>`" }
        case ".key", ".keys": return first.map { "<kbd>\($0)</kbd>" }
        case ".button": return first.map { "**\($0)**" }
        case ".mlink": return first.map { link("\($0) Macro", $0) }
        case ".olink": return first.map { link("\($0) Operator", $0) }
        case ".vlink": return first.map { link("\($0) Variable", $0) }
        case ".olink2":
            guard let shown = first, let to = call.argument(1, "to") else { return nil }
            return link("\(to) Operator", shown)
        case ".wlink": return call.argument(0, "to").map { link($0, $0) }
        case ".link", ".clink", ".dlink", ".wlink2", ".mlink2", ".vlink2":
            guard let shown = first, let to = call.argument(1, "to") else { return nil }
            return link(to, shown)
        case ".tab", ".sidebar-tab", ".more-tab", ".info-tab", ".controlpanel-tab", ".advancedsearch-tab", ".example-tab":
            return first.map { "**\($0.split(separator: "/").last.map(String.init) ?? $0)**" }
        case ".toc-tab": return "**Contents**"
        case ".from-version": return first.map { "*Introduced in v\($0)*" }
        case ".tip", ".note", ".warning":
            guard let body = first else { return nil }
            let kind = String(call.name.dropFirst()).uppercased()
            guard block else { return "**\(kind.capitalized):** " + inline(body) }
            let inner = blocks(body.components(separatedBy: "\n")[...]).joined(separator: "\n\n")
            return Self.prefixed("[!\(kind)]\n" + inner, with: "> ")
        case ".operator-example":
            guard let example = call.argument(1, "eg") else { return nil }
            let result = call.argument(2, "ie").map { " → " + inline($0) } ?? ""
            return (code(example) ?? "") + result
        case "wikitext-example", "wikitext-example-without-html":
            guard block, let source = call.argument(0, "src") else { return nil }
            let fence = source.contains("```") ? "````" : "```"
            let shown = WikiText(images: images, documentationMacros: true).convert(source)
            for (kind, count) in shown.residue { residue[kind, default: 0] += count }
            return "\(fence)wikitext\n\(source.trimmingCharacters(in: .newlines))\n\(fence)\n\nThat renders as:\n\n"
                + shown.markdown.trimmingCharacters(in: .newlines)
        default:
            if call.name.hasPrefix(".link-badge-"), let target = call.argument(0, "link") {
                return "[\(call.name.dropFirst(".link-badge-".count))](\(target))"
            }
            return nil
        }
    }
}

extension Converter {
    /// The query block a macro making a list comes to: `<<list-links>>`,
    /// `<<toc>>` and its kin, `<<tabs>>`, `<<timeline>>`.
    static func query(for call: MacroCall) -> Query? {
        switch call.name {
        case "list-links":
            return call.argument(0, "filter").flatMap { Query(tiddlyWikiFilter: $0) }
        case "list-links-draggable", "list-tagged-draggable":
            var query = Query()
            if call.name == "list-links-draggable" {
                guard let tiddler = call.argument(0, "tiddler") else { return nil }
                query.listedIn = tiddler
            } else {
                guard let tag = call.argument(0, "tag") else { return nil }
                query.tags = [tag]
            }
            return query
        case "toc", "toc-expandable", "toc-selective-expandable", "toc-tabbed-internal-nav", "toc-tabbed-external-nav":
            guard let tag = call.argument(0, "tag") else { return nil }
            var query = Query()
            query.tags = [tag]
            query.show = .tree
            return query
        case "tabs":
            return call.argument(0, "tabsList").flatMap { Query(tiddlyWikiFilter: $0, show: .cards) }
        case "timeline":
            var query = Query()
            query.sort = .modified
            query.descending = true
            query.limit = call.argument(0, "limit").flatMap { Int($0) } ?? 100
            return query
        default:
            return nil
        }
    }

    /// The query a paragraph that is only a list widget —
    /// `<$list filter="…"/>`, or one listing links — or a filtered
    /// transclusion, `{{{ … }}}`, comes to.
    static func query(forElement text: String) -> Query? {
        if text.hasPrefix("{{{"), text.hasSuffix("}}}"), !text.dropFirst(3).dropLast(3).contains("}}}") {
            let filter = text.dropFirst(3).dropLast(3)
            guard !filter.contains("||"), !filter.contains("|") else { return nil }
            return Query(tiddlyWikiFilter: String(filter))
        }
        let patterns = [
            #"^<\$list\s+filter=(?:"([^"]*)"|'([^']*)'|"{3}(.*?)"{3})\s*/>$"#,
            #"^<\$list\s+filter=(?:"([^"]*)"|'([^']*)'|"{3}(.*?)"{3})\s*>\s*(?:<li>)?\s*<\$link\s*/>\s*(?:</li>)?\s*</\$list>$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            for group in 1...3 {
                if let range = Range(match.range(at: group), in: text) {
                    return Query(tiddlyWikiFilter: String(text[range]))
                }
            }
        }
        return nil
    }
}

/// A macro call, `<<name a "b c" name:[[d]]>>`, its parameters read as
/// TiddlyWiki reads them.
struct MacroCall {
    var name: String
    var parameters: [(name: String?, value: String)]

    /// The call that is all of `text`, or nil.
    init?(wholly text: String) {
        var scanner = InlineScanner(Array(text))
        guard scanner.at("<<"), let call = scanner.takeMacro(), scanner.index == scanner.characters.count else { return nil }
        let inner = Array(call.dropFirst(2).dropLast(2))
        var index = 0
        while index < inner.count, !inner[index].isWhitespace { index += 1 }
        name = String(inner[..<index])
        guard !name.isEmpty else { return nil }
        parameters = []
        while true {
            while index < inner.count, inner[index].isWhitespace { index += 1 }
            guard index < inner.count else { break }
            var parameter: String?
            var probe = index
            while probe < inner.count, inner[probe].isLetter || inner[probe].isNumber || "-_".contains(inner[probe]) { probe += 1 }
            if probe > index, probe < inner.count, inner[probe] == ":" {
                parameter = String(inner[index..<probe])
                index = probe + 1
                while index < inner.count, inner[index].isWhitespace { index += 1 }
            }
            guard let (value, end) = Self.value(inner, at: index) else { return nil }
            parameters.append((parameter, value))
            index = end
        }
    }

    private static func value(_ text: [Character], at index: Int) -> (String, Int)? {
        func until(_ close: String, from start: Int) -> Int? {
            let needle = Array(close)
            var offset = start
            while offset + needle.count <= text.count {
                if text[offset..<(offset + needle.count)].elementsEqual(needle) { return offset }
                offset += 1
            }
            return nil
        }
        guard index < text.count else { return nil }
        let rest = text[index...]
        for (open, close) in [("\"\"\"", "\"\"\""), ("\"", "\""), ("'", "'"), ("[[", "]]")] where rest.starts(with: open) {
            guard let end = until(close, from: index + open.count) else { return nil }
            return (String(text[(index + open.count)..<end]), end + close.count)
        }
        var end = index
        while end < text.count, !text[end].isWhitespace { end += 1 }
        return (String(text[index..<end]), end)
    }

    /// A parameter by its name, or else the `position`th of those given
    /// without one.
    func argument(_ position: Int, _ name: String) -> String? {
        if let named = parameters.first(where: { $0.name == name }) { return named.value }
        let unnamed = parameters.filter { $0.name == nil }
        return position < unnamed.count ? unnamed[position].value : nil
    }
}

/// A place in a line of WikiText.
struct InlineScanner {
    let characters: [Character]
    var index = 0

    init(_ characters: [Character]) {
        self.characters = characters
    }

    var current: Character? { index < characters.count ? characters[index] : nil }

    func peek(_ offset: Int) -> Character? {
        index + offset < characters.count ? characters[index + offset] : nil
    }

    mutating func advance() { index += 1 }

    var atWordStart: Bool { index == 0 || !(characters[index - 1].isLetter || characters[index - 1].isNumber) }

    func at(_ text: String) -> Bool {
        var offset = index
        for character in text {
            guard offset < characters.count, characters[offset] == character else { return false }
            offset += 1
        }
        return true
    }

    func find(_ text: String, from start: Int) -> Int? {
        let needle = Array(text)
        guard needle.count <= characters.count else { return nil }
        var offset = start
        while offset + needle.count <= characters.count {
            if characters[offset..<(offset + needle.count)].elementsEqual(needle) { return offset }
            offset += 1
        }
        return nil
    }

    /// What lies between `open` here and the next `close`, passing both;
    /// nil, the scanner unmoved, when nothing closes it or it is empty.
    mutating func take(from open: String, to close: String) -> String? {
        let start = index + open.count
        guard let end = find(close, from: start), end > start else { return nil }
        index = end + close.count
        return String(characters[start..<end])
    }

    /// A macro call, `<<name params>>`, passing quoted parameters whole.
    mutating func takeMacro() -> String? {
        var offset = index + 2
        while offset + 1 < characters.count {
            let character = characters[offset]
            if character == "\"" || character == "'" {
                if at("\"\"\"", offset), let end = find("\"\"\"", from: offset + 3) {
                    offset = end + 3
                    continue
                }
                guard let end = characters[(offset + 1)...].firstIndex(of: character) else { return nil }
                offset = end + 1
                continue
            }
            if character == "[" && offset + 1 < characters.count && characters[offset + 1] == "[" {
                guard let end = find("]]", from: offset + 2) else { return nil }
                offset = end + 2
                continue
            }
            if character == ">" && characters[offset + 1] == ">" {
                let call = String(characters[index..<(offset + 2)])
                index = offset + 2
                return call
            }
            offset += 1
        }
        return nil
    }

    private func at(_ text: String, _ offset: Int) -> Bool {
        var copy = self
        copy.index = offset
        return copy.at(text)
    }

    /// An element's tag, `<name …>` or `</name>`, passing quoted attributes whole.
    mutating func takeTag() -> String? {
        var offset = index + 1
        while offset < characters.count {
            let character = characters[offset]
            if character == "\"" || character == "'" {
                guard let end = characters[(offset + 1)...].firstIndex(of: character) else { return nil }
                offset = end + 1
                continue
            }
            if character == "<" && offset + 1 < characters.count && characters[offset + 1] == "<" {
                guard let end = find(">>", from: offset + 2) else { return nil }
                offset = end + 2
                continue
            }
            if character == ">" {
                let tag = String(characters[index...offset])
                index = offset + 1
                return tag
            }
            offset += 1
        }
        return nil
    }

    mutating func takeURL() -> String? {
        let schemes = ["https://", "http://", "mailto:", "ftp://", "file://"]
        guard schemes.contains(where: { at($0) }) else { return nil }
        var end = index
        while end < characters.count, !characters[end].isWhitespace, !"<>{}[]`|\"\\^".contains(characters[end]) { end += 1 }
        // Trailing punctuation ends the sentence, not the address.
        while end > index, ".,;:!?)'".contains(characters[end - 1]) { end -= 1 }
        let url = String(characters[index..<end])
        index = end
        return url
    }

    mutating func takeEntity() -> String? {
        var end = index + 1
        while end < characters.count, end - index < 12, characters[end].isLetter || characters[end].isNumber || characters[end] == "#" {
            end += 1
        }
        guard end < characters.count, characters[end] == ";", end > index + 1 else { return nil }
        let entity = String(characters[index...end])
        index = end + 1
        return entity
    }
}
