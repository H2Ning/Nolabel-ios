import SwiftUI
import UIKit

/// Keeps the system interactive pop gesture alive when the navigation bar is
/// hidden. SwiftUI disables the recognizer together with the bar; this turns
/// the same system recognizer back on, so the edge swipe stays fully native.
struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let navigationController = controller.navigationController else { return }
            context.coordinator.navigationController = navigationController
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
            navigationController.interactivePopGestureRecognizer?.delegate = context.coordinator
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navigationController: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigationController else { return false }
            guard navigationController.viewControllers.count > 1 else { return false }
            // Never start a pop while another transition is in flight.
            return navigationController.transitionCoordinator == nil
        }
    }
}
