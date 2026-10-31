import ReflectCore
import SwiftUI
import WeftCore

/// A tiddler's body, shown: headings, paragraphs, lists, quotes and
/// callouts, code, tables, pictures, and other tiddlers embedded live.
struct MarkdownView: View {
    @Environment(WikiStore.self) private var store
    let blocks: [MarkdownBlock]
    /// The card this is shown in, for links opened from it.
    let card: String
    /// How deep in embeds this is; embedding stops a few levels down.
    var depth = 0
    /// Whether these are the card's own blocks, whose queries can be edited.
    var editable = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(for: block, at: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Which query block, among the card's, the block at `index` is — when
    /// it can be edited in place: at the top of the card, not in an embed.
    private func queryIndex(_ index: Int) -> Int? {
        guard depth == 0, editable else { return nil }
        return blocks[..<index].filter { if case .query = $0 { true } else { false } }.count
    }

    @ViewBuilder private func view(for block: MarkdownBlock, at index: Int) -> some View {
        switch block {
        case .heading(let level, let text):
            InlineText(text: text)
                .font(Self.headingFont(level))
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            InlineText(text: text)
        case .list(let items):
            ListBlock(items: items)
        case .quote(let inner):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(.tertiary).frame(width: 3)
                MarkdownView(blocks: inner, card: card, depth: depth, editable: false).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .callout(let kind, let inner):
            Callout(kind: kind) { MarkdownView(blocks: inner, card: card, depth: depth, editable: false) }
        case .code(_, let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        case .wikiText(let text):
            WikiTextPlaceholder(text: text)
        case .query(let query):
            QueryView(query: query, card: card, index: queryIndex(index), depth: depth)
        case .table(let header, let rows):
            TableBlock(header: header, rows: rows)
        case .image(let alt, let source, let width):
            PictureView(reference: ImageReference(source: source, alt: alt, width: width))
        case .embed(let title):
            Embed(title: title, card: card, depth: depth)
        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(size: 20, weight: .semibold)
        case 2: .system(size: 17, weight: .semibold)
        case 3: .system(size: 15, weight: .semibold)
        default: .system(size: 14, weight: .semibold)
        }
    }
}

/// A line of inline Markdown: emphasis, code, links — a link to a tiddler
/// no one has written shown faded and slanted, as TiddlyWiki shows them —
/// its pictures under its words, and a link alone in it shown as its card.
struct InlineText: View {
    @Environment(WikiStore.self) private var store
    let text: String
    /// Whether a link alone shows its card: not where the card itself
    /// falls back to its link.
    var cards = true

    var body: some View {
        let pieces = MarkdownCache.pieces(text)
        if cards, let card = pieces.card {
            LinkCardView(source: card.source, text: card.text)
        } else if pieces.pictures.isEmpty {
            words(text)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if !pieces.words.isEmpty { words(pieces.words) }
                ForEach(Array(pieces.pictures.enumerated()), id: \.offset) { _, picture in
                    PictureView(reference: picture)
                }
            }
        }
    }

    private func words(_ text: String) -> some View {
        Text(attributed(text))
            .textSelection(.enabled)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func attributed(_ text: String) -> AttributedString {
        var string = MarkdownCache.attributed(text)
        for run in string.runs {
            guard let url = run.link, let title = InlineMarkdown.title(from: url) else { continue }
            if store.exists(title) {
                string[run.range].foregroundColor = .accentColor
            } else {
                string[run.range].foregroundColor = .secondary
                string[run.range].inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.emphasized)
            }
        }
        return string
    }
}

private struct ListBlock: View {
    let items: [MarkdownBlock.ListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(numbered.enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(entry.item, number: entry.number)
                        .frame(minWidth: 14, alignment: .trailing)
                    InlineText(text: entry.item.text)
                }
                .padding(.leading, CGFloat(entry.item.depth) * 20)
            }
        }
    }

    @ViewBuilder private func marker(_ item: MarkdownBlock.ListItem, number: Int) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? Ink.accent.color : .secondary)
        } else if item.ordered {
            Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
        } else {
            Text(item.depth % 2 == 0 ? "•" : "◦").foregroundStyle(.secondary)
        }
    }

    /// Each item and its number among the numbered items at its depth.
    private var numbered: [(item: MarkdownBlock.ListItem, number: Int)] {
        var counters: [Int: Int] = [:]
        return items.map { item in
            counters = counters.filter { $0.key <= item.depth }
            counters[item.depth, default: 0] += 1
            return (item, counters[item.depth]!)
        }
    }
}

private struct Callout<Content: View>: View {
    let kind: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(kind.capitalized, systemImage: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8).fill(color.opacity(0.7)).frame(width: 3)
        }
    }

    private var symbol: String {
        switch kind {
        case "tip": "lightbulb"
        case "warning", "caution": "exclamationmark.triangle"
        case "important": "exclamationmark.circle"
        default: "info.circle"
        }
    }

    private var color: Color {
        switch kind {
        case "tip": .green
        case "warning", "caution": .orange
        case "important": .purple
        default: .blue
        }
    }
}

/// WikiText the import couldn't turn into anything weft shows: said so,
/// with the WikiText a click away.
private struct WikiTextPlaceholder: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "puzzlepiece.extension")
                    Text(summary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
            if expanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    /// What the WikiText is, from how it starts.
    private var summary: String {
        let start = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if start.hasPrefix("\\") { return "TiddlyWiki definitions" }
        if start.hasPrefix("<<"), let name = start.dropFirst(2).split(whereSeparator: { $0.isWhitespace || $0 == ">" }).first {
            return "TiddlyWiki macro: \(name)"
        }
        if start.hasPrefix("<$"), let name = start.dropFirst(2).split(whereSeparator: { $0.isWhitespace || $0 == ">" || $0 == "/" }).first {
            return "TiddlyWiki widget: \(name)"
        }
        return "TiddlyWiki markup"
    }
}

private struct TableBlock: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 0, verticalSpacing: 0) {
                if header.contains(where: { !$0.isEmpty }) {
                    GridRow {
                        ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                            InlineText(text: cell).fontWeight(.semibold).padding(.horizontal, 10).padding(.vertical, 6)
                        }
                    }
                    .background(.quaternary.opacity(0.5))
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(0..<width, id: \.self) { column in
                            InlineText(text: column < row.count ? row[column] : "")
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                    }
                    .background(index % 2 == 1 ? Color.secondary.opacity(0.05) : .clear)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        }
        .font(.callout)
    }

    private var width: Int { max(header.count, rows.map(\.count).max() ?? 0) }
}

/// Another tiddler shown inside this one, live — TiddlyWiki's transclusion.
private struct Embed: View {
    @Environment(WikiStore.self) private var store
    let title: String
    let card: String
    let depth: Int

    var body: some View {
        if let tiddler = store.tiddler(title), depth < 3, title != card {
            VStack(alignment: .leading, spacing: 8) {
                Link(destination: InlineMarkdown.url(for: title)) {
                    Label(title, systemImage: "square.on.square")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                MarkdownView(blocks: MarkdownCache.blocks(tiddler.text), card: card, depth: depth + 1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        } else {
            InlineText(text: "[[\(title)]]")
        }
    }
}
