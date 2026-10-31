import Foundation
import ReflectCore
import ReflectGit2
import WeftCore

/// The phone's graph: a clone of the GitHub repository the notes are kept
/// in, in weft's own folder, synced through libgit2 with the GitHub account
/// signed in with — as Prism's is, and through the same GitHub App.
@MainActor
public enum GitHubGraph {
    /// The account, shared by the page that signs in and the sync.
    public static let account = GitHubAccount()

    /// Where the clone is.
    public static let root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Weft", isDirectory: true).appendingPathComponent("Graph", isDirectory: true)

    /// Whether there is a clone to open.
    public static var exists: Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
    }

    /// The sync for a graph in a repository: libgit2, with the account's
    /// token, refreshed before each cycle. Nil for a folder in no repository.
    public static func sync(for root: URL) -> WikiSync? {
        guard let backend = LibGit2Backend(root: root) else { return nil }
        let token = account.currentToken
        backend.credentials = { token.credentials }
        if let identity = account.user?.identity { backend.identity = identity }
        let sync = WikiSync(git: Git(backend: backend))
        sync.prepare = {
            guard account.isSignedIn else { throw GitHubError("Signed out of GitHub. Sign in again from the sidebar.") }
            _ = try await account.validAccessToken()
        }
        return sync
    }

    /// Brings a repository down into weft's folder.
    public static func clone(_ repository: GitHubRepository) async throws {
        try await GraphClone.clone(repository, account: account, into: root)
    }
}
