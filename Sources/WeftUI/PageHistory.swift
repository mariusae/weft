import Foundation
import GraphKit
import ReflectCore
import SwiftUI

/// A page as it was at a commit of the graph's history.
public struct PageVersion: Identifiable, Sendable {
    public var id: String { commit }
    public let commit: String
    public let date: Date
    public let message: String
    /// Its file, frontmatter and all.
    public let source: String

    /// What it said, without its frontmatter.
    public var body: String {
        guard source.hasPrefix("---\n"), let end = source.range(of: "\n---\n", range: source.index(source.startIndex, offsetBy: 4)..<source.endIndex) else {
            return source
        }
        return String(source[end.upperBound...])
    }
}

/// A page deleted: where it was, and when it went.
public struct DeletedPage: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let date: Date
    /// Its file, as it was just before it went.
    public let source: String

    public var title: String {
        let body = PageVersion(commit: "", date: date, message: "", source: source).body
        if let line = body.split(separator: "\n").first(where: { $0.hasPrefix("# ") }) { return String(line.dropFirst(2)) }
        return path.split(separator: "/").last.map { String($0.dropLast(3)) } ?? path
    }
}

/// The graph's history, read for pages' past: off the main thread, through
/// a git of its own — not the sync's, which may be at work meanwhile.
enum GraphHistory {
    /// How far back to look.
    static let depth = 400

    /// A page's versions, newest first, each different from the one after it.
    static func versions(of path: String, in git: any GitBackend) -> [PageVersion] {
        let commits = git.recentCommits("HEAD", limit: depth)
        let texts = git.contents(commits.map { ($0.id, path) })
        var versions: [PageVersion] = []
        for (commit, text) in zip(commits, texts) {
            guard let text else { continue }
            if versions.last?.source == text { continue }
            versions.append(PageVersion(commit: commit.id, date: commit.date, message: commit.message, source: text))
            if versions.count >= 40 { break }
        }
        return versions
    }

    /// Pages taken out lately and not back since, the latest gone first.
    static func deleted(in git: any GitBackend, root: URL) -> [DeletedPage] {
        let commits = git.recentCommits("HEAD", limit: depth)
        var found: [DeletedPage] = []
        var seen = Set<String>()
        for (newer, older) in zip(commits, commits.dropFirst()) {
            let gone = git.changedPaths(from: older.id, to: newer.id).filter { path in
                PageFolder.isPage(path) && !seen.contains(path) && !FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
            }
            guard !gone.isEmpty else { continue }
            let texts = git.contents(gone.map { (older.id, $0) })
            for (path, text) in zip(gone, texts) {
                seen.insert(path)
                if let text { found.append(DeletedPage(path: path, date: newer.date, source: text)) }
            }
            if found.count >= 60 { break }
        }
        return found
    }
}

extension WikiStore {
    /// A page's past, from the graph's history; none where there is no history.
    public func versions(of title: String) async -> [PageVersion] {
        guard let root, let path = pages?.entries[title]?.path, let git = makeHistory(root) else { return [] }
        return await Task.detached(priority: .userInitiated) { GraphHistory.versions(of: path, in: git) }.value
    }

    /// Pages deleted lately, to bring back.
    public func deletedPages() async -> [DeletedPage] {
        guard let root, let git = makeHistory(root) else { return [] }
        return await Task.detached(priority: .userInitiated) { GraphHistory.deleted(in: git, root: root) }.value
    }

    /// A page as it was, written over it as it is — undoable.
    public func restore(_ version: PageVersion, of title: String) {
        guard let path = pages?.entries[title]?.path, let current = try? String(contentsOf: root!.appendingPathComponent(path), encoding: .utf8) else { return }
        if isEditing(title) { finishEditing(title) }
        writeFile(version.source, at: path)
        undoable("Restore “\(shownTitle(title))”") { [weak self] in self?.writeFile(current, at: path) }
    }

    /// A page deleted, brought back where it was — and opened.
    @discardableResult
    public func restore(_ page: DeletedPage) -> String? {
        writeFile(page.source, at: page.path)
        return pages?.entry(atPath: page.path)?.page.title
    }

    private func writeFile(_ source: String, at path: String) {
        guard let root else { return }
        let url = root.appendingPathComponent(path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            self.error = "Couldn't write “\(path)”: \(error.localizedDescription)"
            return
        }
        pages?.reload(path: path)
        sync?.noteChanged()
    }
}

/// A card's past: each version, when and why, what it said; one put back.
struct HistorySheet: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State private var versions: [PageVersion]?
    @State private var chosen: PageVersion.ID?

    var body: some View {
        NavigationStack {
            Group {
                if let versions {
                    if versions.isEmpty {
                        ContentUnavailableView("No History", systemImage: "clock.arrow.circlepath",
                                               description: Text("The graph's history has no other version of “\(store.shownTitle(title))”."))
                    } else {
                        list(versions)
                    }
                } else {
                    ProgressView("Reading the history…")
                }
            }
            .navigationTitle("History of \(store.shownTitle(title))")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 460)
        #endif
        .task { versions = await store.versions(of: title) }
    }

    private func list(_ versions: [PageVersion]) -> some View {
        List(versions, selection: $chosen) { version in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(version.date.formatted(date: .abbreviated, time: .shortened)).font(.callout.weight(.semibold))
                    Spacer()
                    if version.id == versions.first?.id {
                        Text("Now").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Restore") {
                            store.restore(version, of: title)
                            dismiss()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Ink.accent.color)
                    }
                }
                Text(version.message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(version.body.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.callout)
                    .lineLimit(chosen == version.id ? nil : 4)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
            .tag(version.id)
        }
    }
}

/// Pages deleted lately: each brought back, its card opened.
struct DeletedPagesSheet: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    @Environment(\.dismiss) private var dismiss
    @State private var pages: [DeletedPage]?

    var body: some View {
        NavigationStack {
            Group {
                if let pages {
                    if pages.isEmpty {
                        ContentUnavailableView("Nothing Deleted", systemImage: "trash",
                                               description: Text("No page deleted lately is missing from the graph."))
                    } else {
                        List(pages) { page in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(page.title).lineLimit(1)
                                    Text("Deleted \(page.date.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Restore") {
                                    if let title = store.restore(page) { river.open(title) }
                                    self.pages?.removeAll { $0.id == page.id }
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(Ink.accent.color)
                            }
                        }
                    }
                } else {
                    ProgressView("Reading the history…")
                }
            }
            .navigationTitle("Recently Deleted")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
        .task { pages = await store.deletedPages() }
    }
}
