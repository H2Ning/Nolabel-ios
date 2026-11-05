import SwiftUI
import UIKit

/// Keeps the system interactive pop gesture alive when the navigation bar is
/// hidden. SwiftUI disables the recognizer together with the bar, and UIKit
/// leaves it disabled after a pop, so it is re-enabled every time the page
/// appears again.
struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = EnablerController()
        controller.coordinator = context.coordinator
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        (controller as? EnablerController)?.enablePopGesture()
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

    private final class EnablerController: UIViewController {
        weak var coordinator: Coordinator?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            enablePopGesture()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enablePopGesture()
        }

        func enablePopGesture() {
            guard let navigationController else { return }
            coordinator?.navigationController = navigationController
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
            navigationController.interactivePopGestureRecognizer?.delegate = coordinator

            // UIKit disables the recognizer while a pop transition runs and
            // does not always turn it back on afterwards.
            DispatchQueue.main.async { [weak self] in
                guard let self, let navigationController = self.navigationController else { return }
                navigationController.interactivePopGestureRecognizer?.isEnabled = true
            }
        }
    }
}
