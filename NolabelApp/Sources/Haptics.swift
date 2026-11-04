import SwiftUI
import UIKit

/// A small, retained haptic engine.
///
/// Feedback generators are cheap to fire but expensive to wake up. Keeping one
/// instance per style and preparing it after every use removes the first-tap
/// latency that made the keypad feel inert.
@MainActor
enum Haptics {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    private static var prepared = false

    static func prepare() {
        guard !prepared else { return }
        prepared = true
        lightGenerator.prepare()
        softGenerator.prepare()
        mediumGenerator.prepare()
        rigidGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }

    /// Numeric keys, backspace and other repeated, low-weight actions.
    static func key() {
        lightGenerator.impactOccurred(intensity: 0.72)
        lightGenerator.prepare()
    }

    /// Opening and closing a surface. Felt, but not distracting.
    static func soft() {
        softGenerator.impactOccurred(intensity: 0.65)
        softGenerator.prepare()
    }

    /// Operators and equals, slightly firmer than a digit.
    static func operatorKey() {
        mediumGenerator.impactOccurred(intensity: 0.55)
        mediumGenerator.prepare()
    }

    /// A committed change, such as switching month or appearance.
    static func pick() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// A destructive action that has just been confirmed.
    static func delete() {
        rigidGenerator.impactOccurred(intensity: 0.9)
        rigidGenerator.prepare()
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    static func warning() {
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }

    static func error() {
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
    }

    /// Kept for source compatibility with the first native build.
    static func light() {
        key()
    }
}


/// Press styling for the calculator keys. The feedback fires on touch-down,
/// matching the visual press, instead of waiting for the action on release.
struct HapticKeyStyle: ButtonStyle {
    var weight: SensoryFeedback.Weight = .light
    var intensity: Double = 0.7

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .sensoryFeedback(
                SensoryFeedback.impact(weight: weight, intensity: intensity),
                trigger: configuration.isPressed,
                condition: { _, newValue in newValue }
            )
    }
}
