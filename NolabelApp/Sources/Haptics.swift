import SwiftUI
import UIKit

/// A small, retained haptic engine.
///
/// Feedback generators are cheap to fire but expensive to wake up. Keeping one
/// instance per style and preparing it after every use removes the first-tap
/// latency that made the keypad feel inert.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    private static var prepared = false

    static func prepare() {
        guard !prepared else { return }
        prepared = true
        light.prepare()
        soft.prepare()
        medium.prepare()
        rigid.prepare()
        selection.prepare()
        notification.prepare()
    }

    /// Numeric keys, backspace and other repeated, low-weight actions.
    static func key() {
        light.impactOccurred(intensity: 0.72)
        light.prepare()
    }

    /// Opening and closing a surface. Felt, but not distracting.
    static func soft() {
        soft.impactOccurred(intensity: 0.65)
        soft.prepare()
    }

    /// Operators and equals, slightly firmer than a digit.
    static func operatorKey() {
        medium.impactOccurred(intensity: 0.55)
        medium.prepare()
    }

    /// A committed change, such as switching month or appearance.
    static func pick() {
        selection.selectionChanged()
        selection.prepare()
    }

    /// A destructive action that has just been confirmed.
    static func delete() {
        rigid.impactOccurred(intensity: 0.9)
        rigid.prepare()
    }

    static func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    static func warning() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    static func error() {
        notification.notificationOccurred(.error)
        notification.prepare()
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
