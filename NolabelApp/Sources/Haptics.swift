import SwiftfulHaptics
import SwiftUI
import UIKit

enum HapticLevel: String, CaseIterable, Identifiable {
    case rich
    case soft
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rich: return "丰富"
        case .soft: return "轻柔"
        case .off: return "关闭"
        }
    }
}

/// A small, retained haptic vocabulary.
///
/// The app uses five families: tick, detent, lift, settle and reject. High
/// frequency interactions stay to one short pulse; only rare moments use a
/// short multi-beat signature.
@MainActor
enum Haptics {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    private static var prepared = false
    private static let manager = HapticManager()
    private(set) static var level: HapticLevel = .rich

    static func setLevel(_ value: HapticLevel) {
        level = value
        if value != .off {
            prepare()
        }
    }

    static func prepare() {
        guard !prepared else { return }
        prepared = true
        lightGenerator.prepare()
        softGenerator.prepare()
        mediumGenerator.prepare()
        rigidGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
        manager.prepareHaptic(option: .success)
        manager.prepareHaptic(option: .swipeAction(actionType: "delete"))
    }

    private static var enabled: Bool { level != .off }

    private static var scale: Double {
        switch level {
        case .rich: return 1.0
        case .soft: return 0.62
        case .off: return 0
        }
    }

    private static func impact(_ generator: UIImpactFeedbackGenerator, _ intensity: Double) {
        guard enabled else { return }
        generator.impactOccurred(intensity: max(0, min(1, intensity * scale)))
        generator.prepare()
    }

    private static func selection() {
        guard enabled else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard enabled else { return }
        if level == .soft {
            switch type {
            case .success:
                impact(lightGenerator, 0.55)
            case .warning:
                impact(mediumGenerator, 0.52)
            case .error:
                impact(rigidGenerator, 0.55)
            @unknown default:
                impact(mediumGenerator, 0.50)
            }
            return
        }
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }

    private static func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            action()
        }
    }

    /// Numeric keys, backspace and other repeated, low-weight actions.
    static func key() {
        impact(lightGenerator, 0.68)
    }

    /// Opening and closing a surface. Felt, but not distracting.
    static func soft() {
        impact(softGenerator, 0.65)
    }

    /// Operators and equals, slightly firmer than a digit.
    static func operatorKey() {
        impact(mediumGenerator, 0.55)
    }

    /// A committed change, such as switching month or appearance.
    static func pick() {
        selection()
    }

    /// A small mechanical detent while swiping.
    static func detent() {
        selection()
    }

    /// A crisp timer-wheel detent while the cash model rotates.
    static func rotationDetent() {
        impact(rigidGenerator, 0.55)
    }

    /// First beat after equals; the button itself supplies the firmer press.
    static func equalsSettle() {
        after(0.045) {
            impact(lightGenerator, 0.38)
        }
    }

    /// Mode 1, 2 and 3 get one, two and three detents.
    static func cashMode(_ mode: Int) {
        selection()
        if mode >= 2 {
            after(0.045) {
                impact(lightGenerator, 0.40)
            }
        }
        if mode >= 3 {
            after(0.090) {
                impact(softGenerator, 0.55)
            }
        }
    }

    /// A swipe that snaps open.
    static func swipeOpen() {
        impact(softGenerator, 0.52)
    }

    /// A swipe that settles closed.
    static func swipeClose() {
        impact(lightGenerator, 0.30)
    }

    /// A full-screen surface rising from the bottom.
    static func lift() {
        impact(softGenerator, 0.55)
        after(0.070) {
            impact(lightGenerator, 0.34)
        }
    }

    /// A full-screen surface returning down.
    static func lower() {
        impact(softGenerator, 0.42)
    }

    /// Selecting the 丰富 level: SwiftfulHaptics' double-tap confirmation.
    static func doubleTapConfirm() {
        guard enabled else { return }
        manager.playHaptic(option: .doubleTapLike())
    }

    /// Saving a bill: the system success notification.
    static func cashCounted() {
        guard enabled else { return }
        manager.playHaptic(option: .success)
    }

    /// A committed delete: SwiftfulHaptics' swipe-to-delete action.
    static func deleteCommitted() {
        guard enabled else { return }
        manager.playHaptic(option: .swipeAction(actionType: "delete"))
    }

    /// A committed action, such as confirming the date sheet.
    static func complete() {
        impact(lightGenerator, 0.45)
    }

    /// The destructive confirmation prompt.
    static func deletePrompt() {
        notify(.warning)
    }

    /// Switching months; crossing a year adds a second tiny detent.
    static func monthShift(crossesYear: Bool) {
        selection()
        if crossesYear {
            after(0.060) {
                selection()
            }
        }
    }

    static func success() {
        notify(.success)
    }

    static func warning() {
        notify(.warning)
    }

    static func error() {
        notify(.error)
    }
}

/// Press styling for the calculator keys. The feedback fires on touch-down,
/// matching the visual press, instead of waiting for the action on release.
struct HapticKeyStyle: ButtonStyle {
    var weight: SensoryFeedback.Weight = .light
    var intensity: Double = 0.7
    var level: HapticLevel = .rich

    func makeBody(configuration: Configuration) -> some View {
        let active = level != .off
        let resolved: Double
        switch level {
        case .rich: resolved = min(1, intensity * 1.12)
        case .soft: resolved = intensity * 0.62
        case .off: resolved = 0
        }
        return configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .sensoryFeedback(
                SensoryFeedback.impact(weight: weight, intensity: resolved),
                trigger: configuration.isPressed,
                condition: { _, newValue in newValue && active }
            )
    }
}
