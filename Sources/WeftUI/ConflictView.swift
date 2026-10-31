import ReflectCore
import SwiftUI
import WeftCore

/// A tiddler both devices changed in the same place: what each wrote, side
/// by side, and which to keep. Choosing writes the file directly, the
/// markers never passing through the editor; every version stays in the
/// repository's history.
struct ConflictView: View {
    @Environment(WikiStore.self) private var store
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Changed on two devices", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Both devices changed the same part of this tiddler. Choose what to keep; the other version stays in the history.")
                .font(.callout)
                .foregroundStyle(.secondary)
            let segments = ConflictMarkers.segments(store.source(title) ?? "")
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                switch segment {
                case .text(let text):
                    let shown = Self.context(text, before: index > 0, after: index < segments.count - 1)
                    if !shown.isEmpty {
                        Text(shown)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                case .conflict(let ours, let theirs):
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 10) { side(ours, mine: true); side(theirs, mine: false) }
                        VStack(alignment: .leading, spacing: 10) { side(ours, mine: true); side(theirs, mine: false) }
                    }
                }
            }
            HStack {
                Button("Keep This Device’s") { withAnimation { store.resolve(title, keeping: .ours) } }
                Button("Keep the Other Device’s") { withAnimation { store.resolve(title, keeping: .theirs) } }
                Button("Keep Both") { withAnimation { store.resolve(title, keeping: .both) } }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    /// The few lines of unchanged text next to a conflict: the first after
    /// one before it, the last before one after it.
    static func context(_ text: String, before: Bool, after: Bool) -> String {
        let lines = text.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
        let keep = 3
        if lines.count <= keep || before && after && lines.count <= keep * 2 {
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let shown = (before ? Array(lines.prefix(keep)) : []) + ["…"] + (after ? Array(lines.suffix(keep)) : [])
        return shown.joined(separator: "\n")
    }

    private func side(_ side: ConflictMarkers.Side, mine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mine ? "This device" : "Other device").font(.caption.weight(.semibold))
                .foregroundStyle(mine ? Ink.accent.color : .secondary)
            Text(side.text.isEmpty ? "(nothing)" : side.text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(mine ? Ink.accent.color.opacity(0.4) : Color.secondary.opacity(0.3)))
    }
}
