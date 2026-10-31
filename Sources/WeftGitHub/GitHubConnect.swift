import AuthenticationServices
import ReflectGit2
import SwiftUI

/// Connecting to GitHub: signing in, choosing the repository the graph is
/// kept in, and bringing it down into weft's own folder — or opening the
/// one already here. In onboarding, and in the Mac's GitHub window.
public struct GitHubConnect: View {
    /// Told when a graph is ready to open: brought down, or already here.
    let open: () -> Void
    @Environment(GitHubAccount.self) private var account
    @Environment(\.webAuthenticationSession) private var session

    @State private var repositories: [GitHubRepository]?
    @State private var cloning: GitHubRepository?
    @State private var busy = false
    @State private var error: String?

    public init(open: @escaping () -> Void) {
        self.open = open
    }

    public var body: some View {
        Group {
            if !GitHubApp.isConfigured {
                ContentUnavailableView("GitHub Is Not Set Up", systemImage: "gearshape",
                                       description: Text("This build has no GitHub App. Its details come from reflect-mac’s iOS/GitHub.local.xcconfig."))
            } else if let cloning {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Bringing down \(cloning.fullName)…").foregroundStyle(.secondary)
                    Text("All of its history comes too; a large graph takes a while.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !account.isSignedIn {
                ContentUnavailableView {
                    Label("Sign In to GitHub", systemImage: "person.crop.circle.badge.checkmark")
                } description: {
                    Text("Weft signs in with the same GitHub App as Prism, and only sees the repositories you give it.")
                } actions: {
                    Button {
                        run { try await account.signIn(session.github) }
                    } label: {
                        Text("Sign In with GitHub").frame(maxWidth: 260)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(busy)
                }
            } else {
                choose
            }
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task(id: account.isSignedIn) { await loadRepositories() }
    }

    private var choose: some View {
        Form {
            if GitHubGraph.exists {
                Section {
                    row(GitHubGraph.repositoryName(for: GitHubGraph.root) ?? "Your Graph", symbol: "checkmark.circle.fill", action: open)
                } header: {
                    Text("Already Here")
                } footer: {
                    Text("Brought down before, and kept in step with GitHub.")
                }
            } else if let repositories {
                Section {
                    ForEach(repositories) { repository in
                        row(repository.fullName, symbol: repository.isPrivate ? "lock" : "book.closed") { bringDown(repository) }
                    }
                } header: {
                    Text("Choose Your Graph")
                } footer: {
                    Text(repositories.isEmpty
                         ? "Weft has not been given any repositories yet."
                         : "The graph comes down to this device, into weft’s own folder, and is kept in step with GitHub.")
                }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
            Section {
                if let user = account.user {
                    Text("Signed in as \(user.login)").foregroundStyle(.secondary)
                }
                Button("Choose Repositories on GitHub…") {
                    run {
                        try await account.chooseRepositories(session.github)
                        await loadRepositories()
                    }
                }
                .disabled(busy)
                Button("Sign Out", role: .destructive) {
                    account.signOut()
                    repositories = nil
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .refreshable { await loadRepositories() }
    }

    /// A repository to choose: the whole row a button, leading on.
    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: symbol).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadRepositories() async {
        guard account.isSignedIn, !GitHubGraph.exists else { return }
        do {
            repositories = try await account.repositories()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func bringDown(_ repository: GitHubRepository) {
        cloning = repository
        Task {
            do {
                try await GitHubGraph.clone(repository)
                open()
            } catch {
                self.error = error.localizedDescription
            }
            cloning = nil
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        Task {
            do {
                try await work()
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                // Closed by the person: nothing to say.
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
