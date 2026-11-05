import SwiftUI
import UIKit

/// A horizontal-only UIKit pan over a bill row.
///
/// SwiftUI's DragGesture begins on vertical movement too, which makes a row
/// inside a ScrollView feel stuck. This recognizer refuses vertical pans so the
/// enclosing scroll view keeps ownership, while still forwarding taps.
struct HorizontalSwipeArea: UIViewRepresentable {
    var onTouchDown: () -> Void
    var onTouchUp: () -> Void
    var onBegan: () -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat) -> Void
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = TouchReportingView()
        view.onTouchDown = onTouchDown
        view.onTouchUp = onTouchUp
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        tap.require(toFail: pan)
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? TouchReportingView)?.onTouchDown = onTouchDown
        (uiView as? TouchReportingView)?.onTouchUp = onTouchUp
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HorizontalSwipeArea

        init(_ parent: HorizontalSwipeArea) {
            self.parent = parent
        }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view else { return }
            let translation = pan.translation(in: view)
            switch pan.state {
            case .began:
                parent.onTouchUp()
                parent.onBegan()
            case .changed:
                parent.onChanged(translation.x)
            case .ended, .cancelled:
                let velocity = pan.velocity(in: view)
                let predicted = translation.x + velocity.x * 0.22
                parent.onEnded(translation.x, predicted)
            default:
                break
            }
        }

        @objc func handleTap(_ tap: UITapGestureRecognizer) {
            guard tap.state == .ended else { return }
            parent.onTap()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else {
                return true
            }
            let translation = pan.translation(in: view)
            if abs(translation.x) > 1 || abs(translation.y) > 1 {
                return abs(translation.x) >= abs(translation.y)
            }
            let velocity = pan.velocity(in: view)
            return abs(velocity.x) >= abs(velocity.y)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private final class TouchReportingView: UIView {
    var onTouchDown: (() -> Void)?
    var onTouchUp: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouchDown?()
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouchUp?()
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouchUp?()
        super.touchesCancelled(touches, with: event)
    }
}
