import AuthenticationServices
import ReflectGit2
import SwiftUI
import WeftGitHub

/// Window ▸ GitHub Account: signing in, for instant sync. The Mac syncs the
/// graph with its own `git`; the account only lets the sync relay tell it,
/// within seconds, when another device pushed.
struct GitHubAccountView: View {
    @Environment(GitHubAccount.self) private var account
    @Environment(\.webAuthenticationSession) private var session
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Instant Sync", systemImage: "bolt.horizontal.circle").font(.title2.weight(.semibold))
            Text("Signed in to GitHub, Weft hears from the sync relay as soon as another device pushes to the graph’s repository, and syncs then, instead of when it next comes to the front.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !GitHubApp.isConfigured {
                Text("This build has no GitHub App: its details come from reflect-mac’s iOS/GitHub.local.xcconfig when scripts/build-app.sh runs.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else if account.isSignedIn {
                HStack {
                    Text("Signed in as \(account.user?.login ?? "you").")
                    Spacer()
                    Button("Sign Out") { account.signOut() }
                }
            } else {
                Button("Sign In with GitHub") {
                    busy = true
                    Task {
                        do {
                            try await account.signIn(session.github)
                        } catch {
                            self.error = error.localizedDescription
                        }
                        busy = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

/// File ▸ GitHub Account…
struct GitHubAccountMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("GitHub Account…") { openWindow(id: "github") }
    }
}
