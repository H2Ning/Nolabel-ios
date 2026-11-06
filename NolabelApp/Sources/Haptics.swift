import CoreHaptics
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
    private static var engine: CHHapticEngine?
    private(set) static var level: HapticLevel = .rich

    /// The save signature: a bill lands on the stack, is counted, then the
    /// drawer settles shut.
    private static let saveSignature: CHHapticPattern? = try? CHHapticPattern(
        events: [
            transient(at: 0.000, sharpness: 0.90, intensity: 0.75),
            continuous(at: 0.055, duration: 0.090, sharpness: 0.15, intensity: 0.55),
            transient(at: 0.160, sharpness: 0.95, intensity: 0.35),
            transient(at: 0.205, sharpness: 0.95, intensity: 0.50),
            continuous(at: 0.300, duration: 0.120, sharpness: 0.30, intensity: 0.50),
            continuous(at: 0.420, duration: 0.100, sharpness: 0.20, intensity: 0.22)
        ],
        parameters: []
    )

    /// The delete signature: pinch the paper, pull it out, and leave a low gap.
    private static let deleteSignature: CHHapticPattern? = try? CHHapticPattern(
        events: [
            transient(at: 0.000, sharpness: 1.00, intensity: 0.50),
            continuous(at: 0.040, duration: 0.050, sharpness: 0.80, intensity: 0.55),
            continuous(at: 0.090, duration: 0.050, sharpness: 0.55, intensity: 0.42),
            continuous(at: 0.140, duration: 0.050, sharpness: 0.30, intensity: 0.30),
            continuous(at: 0.200, duration: 0.090, sharpness: 0.05, intensity: 0.45),
            transient(at: 0.300, sharpness: 0.40, intensity: 0.15)
        ],
        parameters: []
    )

    private static func transient(at time: TimeInterval, sharpness: Float, intensity: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
            ],
            relativeTime: time
        )
    }

    private static func continuous(
        at time: TimeInterval,
        duration: TimeInterval,
        sharpness: Float,
        intensity: Float
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
            ],
            relativeTime: time,
            duration: duration
        )
    }

    private static func ensureEngine() -> CHHapticEngine? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        if engine == nil {
            guard let created = try? CHHapticEngine() else { return nil }
            created.playsHapticsOnly = true
            created.isAutoShutdownEnabled = true
            created.resetHandler = { [weak created] in
                try? created?.start()
            }
            engine = created
        }
        try? engine?.start()
        return engine
    }

    /// Plays a rich signature. Returns false when the level or hardware cannot,
    /// so callers can fall back to the impact vocabulary.
    private static func play(_ pattern: CHHapticPattern?) -> Bool {
        guard level == .rich, let pattern, let engine = ensureEngine() else { return false }
        do {
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            return false
        }
    }

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
        _ = saveSignature
        _ = deleteSignature
        _ = ensureEngine()
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

    /// The "cash counted" signature used after a save. Under 丰富 this is the
    /// three-act pattern; 轻柔 and devices without Core Haptics keep two beats.
    static func cashCounted() {
        if play(saveSignature) { return }
        impact(lightGenerator, 0.52)
        after(0.070) {
            impact(rigidGenerator, 0.78)
        }
    }

    /// The "bill pulled out" signature used when a delete commits: pinch,
    /// friction, then the low gap it leaves behind.
    static func deleteCommitted() {
        if play(deleteSignature) { return }
        impact(softGenerator, 0.45)
        after(0.060) {
            impact(lightGenerator, 0.28)
        }
    }

    /// A committed action, such as confirming the date sheet.
    static func complete() {
        impact(lightGenerator, 0.45)
    }

    /// A destructive prompt and its confirmation.
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
