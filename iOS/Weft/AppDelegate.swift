import UIKit
import WeftCore
import WeftGitHub
import WeftUI

/// What UIKit tells the app that SwiftUI does not: its push token, and the
/// silent pushes the sync relay sends when another device pushed — met with
/// a sync, even with the app in the background.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Silent pushes need no permission asked of the person.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { Push.shared.received(deviceToken) }
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void) {
        MainActor.assumeIsolated { Push.shared.pushed(completion) }
    }
}

/// The phone's side of the relay: its token registered for the graph's
/// repository, once there is a graph and a sign-in.
@MainActor
final class Push {
    static let shared = Push()
    private var deviceToken: Data?
    private var registered: URL?

    func received(_ token: Data) {
        if token != deviceToken { registered = nil }
        deviceToken = token
        register()
    }

    func register() {
        guard let deviceToken, let root = WeftApp.store.root, registered != root else { return }
        registered = root
        Task {
            do {
                try await GitHubGraph.register(deviceToken: deviceToken, for: root)
            } catch {
                registered = nil
            }
        }
    }

    /// Another device pushed: sync — opening the graph first, when the push
    /// woke the app with no window to have opened it.
    func pushed(_ completion: @escaping (UIBackgroundFetchResult) -> Void) {
        let store = WeftApp.store
        if store.root == nil, GitHubGraph.exists { store.open(graph: GitHubGraph.root) }
        guard let sync = store.sync else { return completion(.noData) }
        sync.sync { pulled in completion(pulled ? .newData : .noData) }
    }
}
