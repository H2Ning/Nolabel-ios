import UIKit

/// iOS presents its own confirmation alert whenever an alternate app icon is
/// set. The app shows a "图标已更改" toast instead, so the system alert is
/// swallowed for a short window around the change.
enum AlternateIconAlert {
    private static var installed = false
    private static var suppressDeadline = DispatchTime.now()

    static func install() {
        guard !installed else { return }
        installed = true
        let original = #selector(UIViewController.present(_:animated:completion:))
        let replacement = #selector(UIViewController.nolabel_present(_:animated:completion:))
        guard
            let originalMethod = class_getInstanceMethod(UIViewController.self, original),
            let replacementMethod = class_getInstanceMethod(UIViewController.self, replacement)
        else { return }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }

    static func suppress(for seconds: Double = 1.5) {
        suppressDeadline = .now() + seconds
    }

    static var isSuppressed: Bool {
        DispatchTime.now() < suppressDeadline
    }
}

extension UIViewController {
    @objc fileprivate func nolabel_present(
        _ viewControllerToPresent: UIViewController,
        animated flag: Bool,
        completion: (() -> Void)? = nil
    ) {
        if AlternateIconAlert.isSuppressed, viewControllerToPresent is UIAlertController {
            completion?()
            return
        }
        nolabel_present(viewControllerToPresent, animated: flag, completion: completion)
    }
}
