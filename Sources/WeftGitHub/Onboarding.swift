import ReflectGit2
import SwiftUI

/// The first launch: what weft is, where its wiki is to live — a GitHub
/// repository brought down into weft's own folder, or, on the Mac, a
/// folder already there — and a few things to know.
public struct Onboarding: View {
    /// Whether a folder on this device may be chosen instead: the Mac's way.
    let allowsFolder: Bool
    /// Chooses a folder, and opens it; true when one was.
    let chooseFolder: () -> Bool
    /// Opens the graph brought down from GitHub, or already here.
    let openClone: () -> Void
    /// Onboarding is over.
    let finish: () -> Void

    /// Where it starts: the welcome, unless `WEFT_ONBOARDING_STEP` names
    /// another page — for looking at one without clicking there.
    @State private var step: Step = Step(rawValue: ProcessInfo.processInfo.environment["WEFT_ONBOARDING_STEP"] ?? "") ?? .welcome

    enum Step: String { case welcome, place, github, ready }

    public init(allowsFolder: Bool, chooseFolder: @escaping () -> Bool = { false }, openClone: @escaping () -> Void,
                finish: @escaping () -> Void) {
        self.allowsFolder = allowsFolder
        self.chooseFolder = chooseFolder
        self.openClone = openClone
        self.finish = finish
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .place: place
                case .github:
                    GitHubConnect {
                        openClone()
                        withAnimation { step = .ready }
                    }
                case .ready: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            HStack {
                if step == .place || step == .github {
                    Button("Back") { withAnimation { step = step == .github ? .place : .welcome } }
                }
                Spacer()
                dots
                Spacer()
                if step == .welcome {
                    Button("Continue") { withAnimation { step = .place } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 520)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach([Step.welcome, .place, .github, .ready], id: \.self) { dot in
                Circle()
                    .fill(dot == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 22) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("Welcome to Weft").font(.largeTitle.weight(.semibold))
            Text("A wiki of small notes, kept in your Reflect graph.")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 16) {
                feature("rectangle.stack", "Cards in a river",
                        "Open a tiddler and its card joins the river; follow a link and the next opens beside it.")
                feature("link", "Links, tags and queries",
                        "Link with [[ ]], tag freely, and let a query keep a list of what belongs together.")
                feature("arrow.triangle.2.circlepath", "One graph with Reflect",
                        "Tiddlers sit in your graph’s wiki/ folder, link to your notes and days, and sync as they do.")
            }
            .frame(maxWidth: 440)
            .padding(.top, 8)
        }
        .padding(32)
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var place: some View {
        VStack(spacing: 18) {
            Text("Where is your graph?").font(.title.weight(.semibold))
            Text("Weft keeps its tiddlers beside your Reflect notes, in the same repository.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                choice("icloud.and.arrow.down", "Connect to GitHub", "Recommended",
                       "Sign in, choose the repository your graph is kept in, and Weft brings it down into a folder of its own, kept in step with GitHub — instantly, through the sync relay.") {
                    withAnimation { step = .github }
                }
                if allowsFolder {
                    choice("folder", "Use a Folder on This Mac", nil,
                           "Open a checkout of your graph that is already here — the one Reflect Mac uses — synced through the Mac’s own git.") {
                        if chooseFolder() { withAnimation { step = .ready } }
                    }
                }
            }
            .frame(maxWidth: 460)
        }
        .padding(32)
    }

    private func choice(_ symbol: String, _ title: String, _ badge: String?, _ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .contentShape(Rectangle())
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var ready: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.green)
            Text("You’re Set").font(.largeTitle.weight(.semibold))
            VStack(alignment: .leading, spacing: 12) {
                tip("plus", "Make a tiddler", "⌘N, or the + above the river.")
                tip("link", "Link as you write", "Type [[ and choose a title — a tiddler, a note, or a day.")
                tip("tag", "Tag it", "Tags are tiddlers too: a tag’s card lists what it tags, and can give it fields.")
                tip("line.3.horizontal.decrease.circle", "Ask a query", "Insert Query keeps a live list, table or tree in a tiddler.")
                tip("calendar", "Today", "⌘T opens today’s Reflect note beside your tiddlers.")
            }
            .frame(maxWidth: 440)
            Button("Start Writing", action: finish)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
    }

    private func tip(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 24)
            Text(title).fontWeight(.semibold) + Text(" — ") + Text(text).foregroundStyle(.secondary)
        }
    }
}
