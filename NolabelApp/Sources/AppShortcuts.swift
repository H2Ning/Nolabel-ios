import UIKit

enum AppShortcut: String, Sendable {
    case newEntry = "com.h2ning.nolabel.new-entry"
    case analysis = "com.h2ning.nolabel.analysis"
}

/// Bridges home-screen quick actions to the SwiftUI model. Cold-launch
/// shortcuts wait here until the root view has bootstrapped.
@MainActor
enum AppShortcutRouter {
    static var pending: AppShortcut?
    static var handler: ((AppShortcut) -> Void)?
    private static var lastHandled: (shortcut: AppShortcut, at: Date)?

    static func handle(_ shortcut: AppShortcut) {
        let now = Date()
        if let lastHandled, lastHandled.shortcut == shortcut,
           now.timeIntervalSince(lastHandled.at) < 0.8 {
            return
        }
        lastHandled = (shortcut, now)
        if let handler {
            handler(shortcut)
        } else {
            pending = shortcut
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem,
           let shortcut = AppShortcut(rawValue: item.type) {
            Task { @MainActor in AppShortcutRouter.handle(shortcut) }
        }
        return true
    }

    /// Scene-based launches deliver the shortcut with the scene request, not
    /// through didFinishLaunching. SwiftUI keeps this custom delegate in its
    /// forwarding box, so the WindowGroup still renders normally.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let item = options.shortcutItem,
           let shortcut = AppShortcut(rawValue: item.type) {
            Task { @MainActor in AppShortcutRouter.handle(shortcut) }
        }
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = NolabelSceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let shortcut = AppShortcut(rawValue: shortcutItem.type) else {
            completionHandler(false)
            return
        }
        Task { @MainActor in AppShortcutRouter.handle(shortcut) }
        completionHandler(true)
    }
}

/// Quick actions arrive on the window scene: `connectionOptions` on a cold
/// launch, `performActionFor` while the app is already running.
final class NolabelSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let item = connectionOptions.shortcutItem,
           let shortcut = AppShortcut(rawValue: item.type) {
            Task { @MainActor in AppShortcutRouter.handle(shortcut) }
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let shortcut = AppShortcut(rawValue: shortcutItem.type) else {
            completionHandler(false)
            return
        }
        Task { @MainActor in AppShortcutRouter.handle(shortcut) }
        completionHandler(true)
    }
}
