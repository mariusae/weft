import AuthenticationServices
import Foundation
import Observation
import ReflectCore
import ReflectGit2
import SwiftUI

/// The sync relay, followed: GitHub tells it of each push to the graph's
/// repository, and it tells this device over a WebSocket held open, so
/// another device's writing comes in within seconds. Needs a GitHub
/// sign-in — the relay checks the token with GitHub — and a graph whose
/// `origin` is on GitHub.
@MainActor @Observable
public final class Relay {
    public private(set) var listener: SyncRelayListener?
    @ObservationIgnored private var followed: URL?

    public init() {}

    /// Follows the repository of the graph at `root` — or stops, for none —
    /// syncing when told of a push.
    public func follow(_ root: URL?, onPush: @escaping @MainActor () -> Void) {
        guard root != followed || listener == nil else { return }
        listener?.stop()
        listener = nil
        followed = root
        guard let root, SyncRelay.host != nil, GitHubGraph.account.isSignedIn,
              let repository = GitHubGraph.repositoryName(for: root) else { return }
        let listener = SyncRelayListener(repository: repository, accessToken: { try await GitHubGraph.account.validAccessToken() },
                                         onPush: { Task { @MainActor in onPush() } })
        listener.start()
        self.listener = listener
    }

    /// After waking, or coming back to the network.
    public func reconnect() { listener?.reconnect() }
}

extension GitHubGraph {
    /// `owner/name` of the GitHub repository a graph is a checkout of.
    public static func repositoryName(for root: URL) -> String? {
        SyncRelay.repository(fromRemote: LibGit2Backend(root: root)?.remoteURL())
    }

    /// Tells the relay this phone's push token, for the graph's repository:
    /// a silent push then wakes the app to sync when another device pushes.
    public static func register(deviceToken: Data, for root: URL) async throws {
        guard SyncRelay.host != nil, account.isSignedIn, let repository = repositoryName(for: root) else { return }
        try await SyncRelay.register(deviceToken: deviceToken, repository: repository,
                                     topic: Bundle.main.bundleIdentifier ?? "com.mariusae.weft",
                                     sandbox: SyncRelay.isSandbox, accessToken: try await account.validAccessToken())
    }
}

extension WebAuthenticationSession {
    /// GitHub's pages in the system's browser sheet, to sign in through.
    public var github: GitHubAuthenticator {
        { url, scheme in
            try await authenticate(using: url, callback: .customScheme(scheme), preferredBrowserSession: .shared, additionalHeaderFields: [:])
        }
    }
}
