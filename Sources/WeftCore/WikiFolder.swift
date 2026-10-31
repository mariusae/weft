import Foundation
import ReflectCore

/// Where the wiki is kept in a Reflect graph: `wiki/`, a file a tiddler,
/// named for its title as Reflect names notes.
public enum WikiFolder {
    public static let directory = "wiki"
    /// What keeps Reflect from listing the wiki as notes, for now.
    public static let reflectIgnore = ".reflectignore"
    static let ignoreLine = "/\(directory)/"

    /// Makes `wiki/` in the graph if it is not there, and keeps Reflect out of
    /// it with a line in the graph's `.reflectignore`.
    public static func prepare(in root: URL) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        let ignore = root.appendingPathComponent(reflectIgnore)
        let existing = (try? String(contentsOf: ignore, encoding: .utf8)) ?? ""
        let lines = existing.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !lines.contains(ignoreLine), !lines.contains("\(directory)/"), !lines.contains(directory) else { return }
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        try Data((existing + separator + ignoreLine + "\n").utf8).write(to: ignore, options: .atomic)
    }

    /// Whether a graph-relative path is a tiddler's file.
    public static func isTiddler(_ path: String) -> Bool {
        path.hasPrefix(directory + "/") && path.hasSuffix(".md") && !path.dropFirst(directory.count + 1).contains("/")
    }

    /// The path a new tiddler of this title would take: `wiki/<slug>.md`, or
    /// the first of `-2`, `-3`, … that no file has and `taken` does not hold.
    public static func path(for title: String, in root: URL, taken: Set<String> = []) -> String {
        let slug = Assets.slug(title)
        let manager = FileManager.default
        for attempt in 1... {
            let path = "\(directory)/\(attempt == 1 ? slug : "\(slug)-\(attempt)").md"
            if !taken.contains(path), !manager.fileExists(atPath: root.appendingPathComponent(path).path) { return path }
        }
        fatalError("unreachable")
    }

    /// The title a file without one in its frontmatter goes by: its name.
    static func fallbackTitle(for path: String) -> String {
        (path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
    }
}
