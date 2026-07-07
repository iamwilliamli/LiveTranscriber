import SwiftUI
import UIKit

@MainActor
private enum HomeScreenQuickAction {
    static let startRecordingType = "com.iamwilliamli.LiveTranscriber.startRecording"
    static let startRecordingURL = URL(string: "livetranscriber://record?start=1")!
}

@MainActor
final class HomeScreenQuickActionRouter {
    static let shared = HomeScreenQuickActionRouter()
    static let didRequestRoute = Notification.Name("HomeScreenQuickActionRouter.didRequestRoute")

    private var pendingURL: URL?

    private init() {}

    func route(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard shortcutItem.type == HomeScreenQuickAction.startRecordingType else {
            return false
        }

        pendingURL = HomeScreenQuickAction.startRecordingURL
        NotificationCenter.default.post(name: Self.didRequestRoute, object: nil)
        return true
    }

    func consumePendingURL() -> URL? {
        let url = pendingURL
        pendingURL = nil
        return url
    }
}

final class LiveTranscriberAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.shortcutItems = []
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcutItem = options.shortcutItem {
            Task { @MainActor in
                _ = HomeScreenQuickActionRouter.shared.route(shortcutItem)
            }
        }

        return UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            completionHandler(HomeScreenQuickActionRouter.shared.route(shortcutItem))
        }
    }
}

@main
struct LiveTranscriberApp: App {
    @UIApplicationDelegateAdaptor(LiveTranscriberAppDelegate.self) private var appDelegate

    init() {
        AppTypography.configureUIKitAppearances()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
