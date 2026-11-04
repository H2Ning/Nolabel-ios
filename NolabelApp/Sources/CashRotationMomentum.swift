import QuartzCore
import SwiftUI

/// Carries the horizontal drag velocity into a decaying spin after release.
/// The yaw itself is unbounded; this only decides how the model slows down.
@MainActor
final class CashRotationMomentum: NSObject, ObservableObject {
    private var displayLink: CADisplayLink?
    private var velocity: Double = 0
    private var lastTimestamp: CFTimeInterval = 0

    var onDelta: ((Double) -> Void)?

    func start(velocity: Double) {
        stop()
        guard abs(velocity) > 18 else { return }
        self.velocity = max(-760, min(760, velocity))
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        lastTimestamp = CACurrentMediaTime()
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        velocity = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let deltaTime = min(0.05, max(0.001, now - lastTimestamp))
        lastTimestamp = now

        onDelta?(velocity * deltaTime)
        velocity *= exp(-3.2 * deltaTime)
        if abs(velocity) < 5 {
            stop()
        }
    }

    deinit {
        displayLink?.invalidate()
    }
}
