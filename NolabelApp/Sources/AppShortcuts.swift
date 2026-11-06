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

    static func handle(_ shortcut: AppShortcut) {
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
