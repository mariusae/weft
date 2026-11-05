import Foundation
import Testing

/// A card's layout on the Mac is made of its rows' columns — its margin,
/// its gutter, what it says — and the measures they share: nothing in it
/// is moved into place by a nudge. This keeps it so: the files a card is
/// drawn by, as the Mac compiles them, have no offsets and no nudges
/// worked out from the size of type.
struct CardLayoutTests {
    /// The files a card is laid out by.
    static let files = ["Card.swift", "CardEditor.swift", "Measures.swift", "QueryRiverHeader.swift",
                        "RelatedRow.swift", "InRiversRow.swift"]

    /// What moves a view by so much rather than laying it out.
    static let nudges = [".offset(", "padding(.top, TextSettings.size *", "padding(.leading, TextSettings.size *"]

    @Test(arguments: files)
    func hasNoNudgesOnTheMac(_ name: String) throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/WeftUI/\(name)")
        let text = try String(contentsOf: source, encoding: .utf8)
        var found: [String] = []
        for (number, line) in Self.macLines(text) where Self.nudges.contains(where: line.contains) {
            found.append("\(name):\(number): \(line.trimmingCharacters(in: .whitespaces))")
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    /// The lines the Mac compiles, by number: those not under `#if os(iOS)`,
    /// nor the `#else` of `#if os(macOS)`. Comments aside.
    static func macLines(_ text: String) -> [(Int, String)] {
        var compiled: [Bool] = []
        var lines: [(Int, String)] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if ") {
                compiled.append(!trimmed.contains("os(iOS)"))
            } else if trimmed.hasPrefix("#elseif") {
                if !compiled.isEmpty { compiled[compiled.count - 1] = !trimmed.contains("os(iOS)") }
            } else if trimmed.hasPrefix("#else") {
                if let last = compiled.popLast() { compiled.append(!last) }
            } else if trimmed.hasPrefix("#endif") {
                _ = compiled.popLast()
            } else if compiled.allSatisfy({ $0 }), !trimmed.isEmpty, !trimmed.hasPrefix("//") {
                lines.append((index + 1, line))
            }
        }
        return lines
    }

    @Test func readsWhatTheMacCompiles() {
        let text = "a\n#if os(iOS)\nb\n#else\nc\n#endif\n#if os(macOS)\nd\n#else\ne\n#endif\n// f.offset(\n"
        #expect(Self.macLines(text).map(\.1) == ["a", "c", "d"])
    }
}
